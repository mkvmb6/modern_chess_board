import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/animation/move_animator.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

const _duration = Duration(milliseconds: 150);

Widget host(ChessBoard board, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Material(
      child: Center(child: SizedBox.square(dimension: 400, child: board)),
    ),
  ),
);

Future<void> pumpBoard(
  WidgetTester tester,
  ChessBoard board, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(host(board, reduceMotion: reduceMotion));
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => board.pieceSet.precache(context));
  await tester.pump();
}

Finder _squares() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
);

Offset boardOrigin(WidgetTester tester) => tester.getTopLeft(_squares());

BoardSquaresPainter painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_squares()).painter! as BoardSquaresPainter;

Offset centerOf(WidgetTester tester, Square square) =>
    boardOrigin(tester) + painter(tester).geometry.squareCenter(square);

Future<void> tapSquare(WidgetTester tester, Square square) async {
  await tester.tapAt(centerOf(tester, square));
  await tester.pump();
}

/// Every place [piece] is drawn right now, as global rects: on the board
/// and in flight.
List<Rect> drawn(WidgetTester tester, Piece piece) => [
  for (final v in tester.widgetList<ChessPieceView>(
    find.byType(ChessPieceView),
  ))
    if (v.piece == piece) tester.getRect(find.byWidget(v)),
];

/// The pieces drawn by the animation layer.
Iterable<ChessPieceView> inFlight(WidgetTester tester) =>
    tester.widgetList<ChessPieceView>(
      find.descendant(
        of: find.byType(MoveAnimationLayer),
        matching: find.byType(ChessPieceView),
      ),
    );

void main() {
  group('a code move', () {
    testWidgets('slides the piece and it appears exactly once at every frame', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final from = centerOf(tester, Square.g1);
      final to = centerOf(tester, Square.f3);
      c.move(Square.g1, Square.f3);

      for (final (fraction, label) in [
        (0.0, 'start'),
        (0.5, 'halfway'),
        (1.0, 'end'),
      ]) {
        if (fraction == 0) {
          await tester.pump();
        } else {
          await tester.pump(_duration * 0.5);
        }
        final knights = drawn(tester, Piece.whiteKnight);
        // g1's knight is in flight or landed; b1's never moves.
        expect(knights, hasLength(2), reason: label);
        final moving = knights.firstWhere(
          (r) => (r.center - centerOf(tester, Square.b1)).distance > 1,
        );
        if (fraction == 0) {
          expect(moving.center, offsetMoreOrLessEquals(from, epsilon: 1));
        } else if (fraction == 0.5) {
          // Eased, so somewhere strictly between the squares.
          expect((moving.center - from).distance, greaterThan(1));
          expect((moving.center - to).distance, greaterThan(1));
        } else {
          expect(moving.center, offsetMoreOrLessEquals(to, epsilon: 1));
        }
      }
      await tester.pumpAndSettle();
      expect(inFlight(tester), isEmpty, reason: 'the animation ended');
    });

    testWidgets('castling slides both king and rook', (tester) async {
      final c = ChessBoardController(
        fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
      );
      await pumpBoard(tester, ChessBoard(controller: c));
      c.moveSan('O-O');
      await tester.pump();
      await tester.pump(_duration * 0.5);
      expect(inFlight(tester).map((v) => v.piece).toSet(), {
        Piece.whiteKing,
        Piece.whiteRook,
      });
      // Each appears once: no copy left on g1 or f1 underneath.
      expect(drawn(tester, Piece.whiteKing), hasLength(1));
      expect(drawn(tester, Piece.whiteRook), hasLength(2)); // a1 + in flight
      await tester.pumpAndSettle();
    });

    testWidgets('a captured piece fades out instead of vanishing', (
      tester,
    ) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('d5');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.moveSan('exd5');
      await tester.pump();
      await tester.pump(_duration * 0.25);
      // The fading capture is the only FadeTransition in the layer.
      final fading = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(MoveAnimationLayer),
          matching: find.byType(FadeTransition),
        ),
      );
      final faded = tester.widget<ChessPieceView>(
        find.descendant(
          of: find.byWidget(fading),
          matching: find.byType(ChessPieceView),
        ),
      );
      expect(faded.piece, Piece.blackPawn);
      expect(fading.opacity.value, inExclusiveRange(0.0, 1.0));
      // Fully gone by 60% of the move, before the attacker arrives.
      await tester.pump(_duration * 0.4);
      expect(fading.opacity.value, closeTo(0, 1e-9));
      await tester.pumpAndSettle();
      // Gone at the end.
      final d5 = centerOf(tester, Square.d5);
      final blackPawnsOnD5 = drawn(
        tester,
        Piece.blackPawn,
      ).where((r) => r.contains(d5));
      expect(blackPawnsOnD5, isEmpty);
    });
  });

  testWidgets('a tapped move animates too', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e2);
    await tapSquare(tester, Square.e4);
    await tester.pump(_duration * 0.5);
    expect(inFlight(tester).map((v) => v.piece), [Piece.whitePawn]);
    await tester.pumpAndSettle();
  });

  testWidgets('a dragged move does not animate', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final start = centerOf(tester, Square.e2);
    final end = centerOf(tester, Square.e4);
    final g = await tester.startGesture(start);
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(Offset.lerp(start, end, i / 6)!);
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(inFlight(tester), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'nothing runs');
    expect(c.pieceAt(Square.e4), Piece.whitePawn);
  });

  testWidgets('a dragged promotion lands without animating after the choice', (
    tester,
  ) async {
    final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
    await pumpBoard(tester, ChessBoard(controller: c));
    final start = centerOf(tester, Square.a7);
    final end = centerOf(tester, Square.a8);
    final g = await tester.startGesture(start);
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(Offset.lerp(start, end, i / 6)!);
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promotion-queen')));
    await tester.pump();
    expect(inFlight(tester), isEmpty);
    expect(c.pieceAt(Square.a8), Piece.whiteQueen);
  });

  testWidgets(
    'a second move mid-flight finishes the first and plays the next',
    (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      c.move(Square.e2, Square.e4);
      await tester.pump();
      await tester.pump(_duration * 0.4);
      c.move(Square.e7, Square.e5);
      await tester.pump();
      // Only the new move is in flight; e4's pawn is already landed.
      expect(inFlight(tester).map((v) => v.piece), [Piece.blackPawn]);
      final e4 = centerOf(tester, Square.e4);
      expect(
        drawn(tester, Piece.whitePawn).where((r) => r.contains(e4)),
        hasLength(1),
      );
      await tester.pumpAndSettle();
      expect(
        c.fen,
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
      );
      expect(drawn(tester, Piece.blackPawn), hasLength(8));
    },
  );

  testWidgets('undo, reset and loading snap without animating', (tester) async {
    final c = ChessBoardController()..moveSan('e4');
    await pumpBoard(tester, ChessBoard(controller: c));
    for (final change in <void Function()>[
      c.undo,
      () => c.loadFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1'),
      c.reset,
    ]) {
      change();
      await tester.pump();
      expect(inFlight(tester), isEmpty);
    }
  });

  testWidgets('a silent move does not animate', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    c.move(Square.e2, Square.e4, notify: false);
    c.notifyListeners();
    await tester.pump();
    expect(inFlight(tester), isEmpty);
  });

  testWidgets('zero duration settles in one pump', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(
      tester,
      ChessBoard(controller: c, animationDuration: Duration.zero),
    );
    c.move(Square.e2, Square.e4);
    await tester.pump();
    expect(inFlight(tester), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion settles in one pump', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c), reduceMotion: true);
    c.move(Square.e2, Square.e4);
    await tester.pump();
    expect(inFlight(tester), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a controller swap ends a running animation', (tester) async {
    final a = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: a));
    a.move(Square.e2, Square.e4);
    await tester.pump();
    await tester.pump(_duration * 0.3);
    expect(inFlight(tester), isNotEmpty);
    final b = ChessBoardController();
    await tester.pumpWidget(host(ChessBoard(controller: b)));
    expect(inFlight(tester), isEmpty);
    expect(drawn(tester, Piece.whitePawn), hasLength(8));
  });

  testWidgets('the duration is configurable', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(
      tester,
      ChessBoard(
        controller: c,
        animationDuration: const Duration(milliseconds: 600),
      ),
    );
    c.move(Square.e2, Square.e4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(inFlight(tester), isNotEmpty, reason: 'still moving at 300ms');
    await tester.pump(const Duration(milliseconds: 320));
    expect(inFlight(tester), isEmpty);
  });

  group('review regressions', () {
    testWidgets('a promotion chosen in the picker lands without sliding', (
      tester,
    ) async {
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('promotion-knight')));
      await tester.pump();
      expect(inFlight(tester), isEmpty);
      expect(c.pieceAt(Square.a8), Piece.whiteKnight);
    });

    testWidgets('an autoQueen tap promotion slides the pawn', (tester) async {
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c, autoQueen: true));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tester.pump(_duration * 0.5);
      expect(inFlight(tester).map((v) => v.piece), [Piece.whitePawn]);
      await tester.pumpAndSettle();
      expect(drawn(tester, Piece.whiteQueen), hasLength(1));
    });

    testWidgets('en passant fades the pawn beside the target', (tester) async {
      final c = ChessBoardController(fen: '4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.moveSan('dxe6');
      await tester.pump();
      await tester.pump(_duration * 0.2);
      final fading = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(MoveAnimationLayer),
          matching: find.byType(FadeTransition),
        ),
      );
      final at = tester.getCenter(find.byWidget(fading));
      expect(
        at,
        offsetMoreOrLessEquals(centerOf(tester, Square.e5), epsilon: 1),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a silent move then a notified one snaps instead of '
        'animating from a stale position', (tester) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.moveSan('Bc4', notify: false);
      c.moveSan('Nc6');
      await tester.pump();
      expect(inFlight(tester), isEmpty);
      expect(c.pieceAt(Square.c4), Piece.whiteBishop);
    });

    testWidgets('history navigation snaps', (tester) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.back();
      await tester.pump();
      expect(inFlight(tester), isEmpty);
      c.goTo(0);
      await tester.pump();
      expect(inFlight(tester), isEmpty);
    });

    testWidgets('a branch move animates', (tester) async {
      final c = ChessBoardController(allowBranching: true)
        ..moveSan('e4')
        ..moveSan('e5')
        ..back();
      await pumpBoard(tester, ChessBoard(controller: c));
      c.moveSan('c5');
      await tester.pump();
      await tester.pump(_duration * 0.5);
      expect(inFlight(tester).map((v) => v.piece), [Piece.blackPawn]);
      await tester.pumpAndSettle();
    });

    testWidgets('pressing a piece still in flight lands it first', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      c.move(Square.e2, Square.e4);
      c.move(Square.e7, Square.e5);
      // Now white to move; the black pawn is still sliding to e5. Drag
      // white's knight while it slides: nothing shows twice.
      await tester.pump(_duration * 0.3);
      final start = centerOf(tester, Square.g1);
      final g = await tester.startGesture(start);
      await tester.pump();
      expect(inFlight(tester), isEmpty, reason: 'landed on press');
      expect(drawn(tester, Piece.blackPawn), hasLength(8));
      await g.moveBy(const Offset(30, -30));
      await tester.pump();
      expect(drawn(tester, Piece.whiteKnight), hasLength(2));
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('castling and captures show each piece exactly once at every '
        'frame', (tester) async {
      final c = ChessBoardController(
        fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
      );
      await pumpBoard(tester, ChessBoard(controller: c));
      c.moveSan('O-O');
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        expect(drawn(tester, Piece.whiteKing), hasLength(1), reason: 'f$i');
        expect(drawn(tester, Piece.whiteRook), hasLength(2), reason: 'f$i');
        await tester.pump(_duration * 0.3);
      }
      final e = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('d5');
      await tester.pumpWidget(host(ChessBoard(controller: e)));
      await tester.pump();
      e.moveSan('exd5');
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        expect(drawn(tester, Piece.whitePawn), hasLength(8), reason: 'f$i');
        await tester.pump(_duration * 0.3);
      }
    });
  });
}
