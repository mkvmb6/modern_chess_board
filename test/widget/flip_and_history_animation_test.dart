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

Offset origin(WidgetTester tester) => tester.getTopLeft(_squares());

/// Global top-left of [square] with white or black at the bottom.
Offset squareTopLeft(WidgetTester tester, Square square, bool whiteBottom) {
  const s = 50.0; // 400px board, no margin
  final col = whiteBottom ? square.file : 7 - square.file;
  final row = whiteBottom ? 7 - square.rank : square.rank;
  return origin(tester) + Offset(col * s, row * s);
}

/// Global rects of every drawn view of [piece].
List<Rect> drawn(WidgetTester tester, Piece piece) => [
  for (final v in tester.widgetList<ChessPieceView>(
    find.byType(ChessPieceView),
  ))
    if (v.piece == piece) tester.getRect(find.byWidget(v)),
];

Iterable<ChessPieceView> inFlight(WidgetTester tester) =>
    tester.widgetList<ChessPieceView>(
      find.descendant(
        of: find.byType(MoveAnimationLayer),
        matching: find.byType(ChessPieceView),
      ),
    );

void main() {
  group('history navigation', () {
    testWidgets('back() slides the last move in reverse', (tester) async {
      final c = ChessBoardController()..moveSan('Nf3');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.back();
      await tester.pump();
      await tester.pump(_duration * 0.5);
      expect(inFlight(tester).map((v) => v.piece), [Piece.whiteKnight]);
      await tester.pumpAndSettle();
      expect(
        drawn(tester, Piece.whiteKnight).map((r) => r.topLeft),
        contains(squareTopLeft(tester, Square.g1, true)),
      );
    });

    testWidgets('forward() replays the move', (tester) async {
      final c = ChessBoardController()
        ..moveSan('Nf3')
        ..back();
      await pumpBoard(tester, ChessBoard(controller: c));
      c.forward();
      await tester.pump();
      await tester.pump(_duration * 0.5);
      expect(inFlight(tester).map((v) => v.piece), [Piece.whiteKnight]);
      await tester.pumpAndSettle();
    });

    testWidgets('stepping back over a capture brings the captured piece '
        'back in', (tester) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('d5')
        ..moveSan('exd5');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.back();
      await tester.pump();
      await tester.pump(_duration * 0.5);
      // The white pawn slides back to e4; the black pawn reappears on d5.
      expect(inFlight(tester).map((v) => v.piece).toSet(), {
        Piece.whitePawn,
        Piece.blackPawn,
      });
      await tester.pumpAndSettle();
      expect(drawn(tester, Piece.blackPawn), hasLength(8));
    });

    testWidgets('stepping back over castling moves both pieces home', (
      tester,
    ) async {
      final c = ChessBoardController(
        fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
      )..moveSan('O-O');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.back();
      await tester.pump();
      await tester.pump(_duration * 0.5);
      expect(inFlight(tester).map((v) => v.piece).toSet(), {
        Piece.whiteKing,
        Piece.whiteRook,
      });
      await tester.pumpAndSettle();
    });

    testWidgets('stepping back over a promotion slides a pawn back', (
      tester,
    ) async {
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1')
        ..move(Square.a7, Square.a8, promotion: PieceType.queen);
      await pumpBoard(tester, ChessBoard(controller: c));
      c.back();
      await tester.pump();
      await tester.pump(_duration * 0.5);
      // The pawn travels back, not the queen.
      expect(inFlight(tester).map((v) => v.piece), [Piece.whitePawn]);
      await tester.pumpAndSettle();
      expect(drawn(tester, Piece.whiteQueen), isEmpty);
    });

    testWidgets('jumps of more than one move snap', (tester) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5')
        ..moveSan('Nf3');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.goToStart();
      await tester.pump();
      expect(inFlight(tester), isEmpty);
      c.goToEnd();
      await tester.pump();
      expect(inFlight(tester), isEmpty);
    });

    testWidgets('each step lands the previous one first', (tester) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.back();
      await tester.pump();
      await tester.pump(_duration * 0.3);
      c.back();
      await tester.pump();
      expect(inFlight(tester).map((v) => v.piece), [Piece.whitePawn]);
      expect(drawn(tester, Piece.blackPawn), hasLength(8));
      await tester.pumpAndSettle();
      expect(c.fen, kInitialFen);
    });
  });

  group('flip', () {
    testWidgets('midway, pieces turn around the center; at the end they '
        'are in the black orientation', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tester.pumpWidget(
        host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
      );
      await tester.pump(_duration * 0.5);
      // Midway, a1's rook is neither where white orientation put it nor
      // where black orientation will, and no piece is at the center.
      final rookA1 = drawn(
        tester,
        Piece.whiteRook,
      ).map((r) => r.topLeft).toList();
      expect(rookA1, isNot(contains(squareTopLeft(tester, Square.a1, true))));
      expect(rookA1, isNot(contains(squareTopLeft(tester, Square.a1, false))));
      await tester.pumpAndSettle();
      expect(drawn(tester, Piece.whiteRook).map((r) => r.topLeft).toSet(), {
        squareTopLeft(tester, Square.a1, false),
        squareTopLeft(tester, Square.h1, false),
      });
    });

    testWidgets('pieces keep their distance from the center while turning', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final center = origin(tester) + const Offset(200, 200);
      final before = {
        for (final r in drawn(tester, Piece.whiteKing))
          (r.center - center).distance,
      };
      await tester.pumpWidget(
        host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
      );
      await tester.pump(_duration * 0.4);
      final midway = {
        for (final r in drawn(tester, Piece.whiteKing))
          (r.center - center).distance,
      };
      expect(midway.single, closeTo(before.single, 0.5));
      await tester.pumpAndSettle();
    });

    testWidgets('zero duration and reduced motion flip at once', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c), reduceMotion: true);
      await tester.pumpWidget(
        host(
          ChessBoard(controller: c, orientation: BoardOrientation.black),
          reduceMotion: true,
        ),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        drawn(tester, Piece.whiteKing).single.topLeft,
        squareTopLeft(tester, Square.e1, false),
      );
    });

    testWidgets(
      'taps during a flip are ignored, then use the new orientation',
      (tester) async {
        final c = ChessBoardController();
        await pumpBoard(tester, ChessBoard(controller: c));
        await tester.pumpWidget(
          host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
        );
        await tester.pump(_duration * 0.3);
        Future<void> tapMove() async {
          await tester.tapAt(
            squareTopLeft(tester, Square.e2, false) + const Offset(25, 25),
          );
          await tester.pump();
          await tester.tapAt(
            squareTopLeft(tester, Square.e4, false) + const Offset(25, 25),
          );
          await tester.pump();
        }

        // Mid-flip the pieces are still turning, so input waits.
        await tapMove();
        expect(c.pieceAt(Square.e2), Piece.whitePawn);
        await tester.pumpAndSettle();
        // e2 in black orientation is row 1, column 3.
        await tapMove();
        await tester.pumpAndSettle();
        expect(c.pieceAt(Square.e4), Piece.whitePawn);
      },
    );

    testWidgets('flipping back mid-flip retraces the arc without a jump', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tester.pumpWidget(
        host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
      );
      // Frame steps are 1/30 of a 300 ms flip, so a smooth path moves a
      // corner piece well under 40 px per step.
      const step = Duration(milliseconds: 10);
      Offset king() => drawn(tester, Piece.whiteKing).single.center;
      for (var i = 0; i < 8; i++) {
        await tester.pump(step);
      }
      var last = king();
      await tester.pumpWidget(host(ChessBoard(controller: c)));
      for (var i = 0; i < 40; i++) {
        await tester.pump(step);
        final now = king();
        expect((now - last).distance, lessThan(40), reason: 'frame $i');
        last = now;
      }
      await tester.pumpAndSettle();
      expect(
        drawn(tester, Piece.whiteKing).single.topLeft,
        squareTopLeft(tester, Square.e1, true),
      );
    });

    testWidgets('the promotion picker waits out a flip', (tester) async {
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c));
      await tester.tapAt(
        squareTopLeft(tester, Square.a7, true) + const Offset(25, 25),
      );
      await tester.pump();
      await tester.tapAt(
        squareTopLeft(tester, Square.a8, true) + const Offset(25, 25),
      );
      await tester.pump();
      final picker = find.byKey(const ValueKey('promotion-queen'));
      expect(picker, findsOneWidget);
      await tester.pumpWidget(
        host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
      );
      await tester.pump(_duration * 0.5);
      // Mid-flip the picker is faded and can't be tapped.
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: picker, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, lessThan(1));
      await tester.tap(picker, warnIfMissed: false);
      await tester.pump();
      expect(c.pieceAt(Square.a7), Piece.whitePawn);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.a8), Piece.whiteQueen);
    });

    testWidgets('a resting drag re-aims its drop target after a flip', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await tester.startGesture(
        squareTopLeft(tester, Square.e2, true) + const Offset(25, 25),
      );
      // Rest over e4 (white at the bottom).
      await gesture.moveTo(
        squareTopLeft(tester, Square.e4, true) + const Offset(25, 25),
      );
      await tester.pump();
      await tester.pumpWidget(
        host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
      );
      await tester.pumpAndSettle();
      // That spot is d5 in black orientation, which e2 can't reach, so a
      // release there must not play e4.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e2), Piece.whitePawn);
      expect(c.pieceAt(Square.e4), isNull);
    });

    testWidgets('a controller swap ends a flip', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tester.pumpWidget(
        host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
      );
      await tester.pump(_duration * 0.3);
      await tester.pumpWidget(
        host(
          ChessBoard(
            controller: ChessBoardController(),
            orientation: BoardOrientation.black,
          ),
        ),
      );
      // The swap itself needs one frame; after it nothing keeps running.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      expect(
        drawn(tester, Piece.whiteKing).single.topLeft,
        squareTopLeft(tester, Square.e1, false),
      );
    });

    testWidgets('a controller swap ends a history animation', (tester) async {
      final c = ChessBoardController()..moveSan('e4');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.back();
      await tester.pump();
      await tester.pump(_duration * 0.3);
      expect(inFlight(tester), isNotEmpty);
      await tester.pumpWidget(
        host(ChessBoard(controller: ChessBoardController())),
      );
      expect(inFlight(tester), isEmpty);
    });
  });
}
