import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/animation/move_animator.dart';
import 'package:modern_chess_board/src/widget/layers/highlight_layer.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

Widget host(ChessBoard board) => MaterialApp(
  home: Material(
    child: Center(child: SizedBox.square(dimension: 400, child: board)),
  ),
);

Future<void> pumpBoard(WidgetTester tester, ChessBoard board) async {
  await tester.pumpWidget(host(board));
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => board.pieceSet.precache(context));
  await tester.pump();
}

Finder _squares() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
);

Offset centerOf(WidgetTester tester, Square square) =>
    tester.getTopLeft(_squares()) +
    (tester.widget<CustomPaint>(_squares()).painter! as BoardSquaresPainter)
        .geometry
        .squareCenter(square);

Future<void> tap(WidgetTester tester, Square square) async {
  await tester.tapAt(centerOf(tester, square));
  await tester.pump();
}

Future<void> drag(WidgetTester tester, Square from, Square to) async {
  final g = await tester.startGesture(centerOf(tester, from));
  await g.moveTo(centerOf(tester, from) + const Offset(0, -20));
  await tester.pump();
  await g.moveTo(centerOf(tester, to));
  await tester.pump();
  await g.up();
  await tester.pump();
}

/// The tints the highlight layer paints.
Map<Square, Color> tints(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BoardTintsPainter,
      ),
    )
    .painter!
    .let((p) => (p as BoardTintsPainter).highlights.tints);

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

const _theme = ChessBoardTheme.green;

/// White to play; the user plays black with premoves on.
ChessBoard blackBoard(
  ChessBoardController c, {
  bool premoves = true,
  InteractiveSide side = InteractiveSide.black,
  ValueChanged<BoardMove>? onMove,
}) => ChessBoard(
  controller: c,
  interactiveSide: side,
  enablePremoves: premoves,
  onMove: onMove,
);

void main() {
  group('queueing', () {
    testWidgets('tap queues a premove and highlights it', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      // Nothing moved yet: it is white's turn.
      expect(c.pieceAt(Square.e7), Piece.blackPawn);
      expect(tints(tester)[Square.e7], _theme.premoveColor);
      expect(tints(tester)[Square.e5], _theme.premoveColor);
    });

    testWidgets('drag queues a premove', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await drag(tester, Square.g8, Square.f6);
      expect(c.pieceAt(Square.g8), Piece.blackKnight);
      expect(tints(tester)[Square.f6], _theme.premoveColor);
    });

    testWidgets('onMove reports when played, not when queued', (tester) async {
      final c = ChessBoardController();
      final moves = <BoardMove>[];
      await pumpBoard(tester, blackBoard(c, onMove: moves.add));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      expect(moves, isEmpty);
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(moves.map((m) => m.san), ['e5']);
    });

    testWidgets('a premove may target a square the opponent might vacate', (
      tester,
    ) async {
      // Pawn captures diagonally onto an empty square: it may become a
      // capture once the opponent moves there.
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.d6);
      expect(tints(tester)[Square.d6], _theme.premoveColor);
    });
  });

  group('playing', () {
    testWidgets('plays when the opponent has moved, if legal', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e5), Piece.blackPawn);
      expect(c.turn, PieceColor.white);
      expect(tints(tester)[Square.e7], isNot(_theme.premoveColor));
    });

    testWidgets('a premoved capture plays once the piece arrives', (
      tester,
    ) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('d5')
        ..moveSan('a3');
      await pumpBoard(tester, blackBoard(c));
      // Black to move here; play it so it is white's turn.
      c.moveSan('a6');
      await tester.pumpAndSettle();
      await tap(tester, Square.d5);
      await tap(tester, Square.e4);
      c.moveSan('Nc3');
      await tester.pumpAndSettle();
      expect(c.lastMove?.san, 'dxe4');
    });

    testWidgets('is dropped silently when no longer legal', (tester) async {
      final c = ChessBoardController();
      final moves = <BoardMove>[];
      await pumpBoard(tester, blackBoard(c, onMove: moves.add));
      // Premove the e-pawn two squares, then white blocks it.
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      c
        ..move(Square.e2, Square.e4, notify: false)
        ..undo(notify: false);
      c.loadFen('rnbqkbnr/pppppppp/8/8/8/4P3/PPPP1PPP/RNBQKBNR w KQkq - 0 1');
      await tester.pumpAndSettle();
      // Loading drops the premove outright.
      expect(c.pieceAt(Square.e7), Piece.blackPawn);
      expect(moves, isEmpty);
    });

    testWidgets('an illegal premove after the opponent moves is dropped', (
      tester,
    ) async {
      // White's bishop check makes the queued pawn move illegal.
      final c = ChessBoardController(
        fen: 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
      );
      final moves = <BoardMove>[];
      await pumpBoard(tester, blackBoard(c, onMove: moves.add));
      await tap(tester, Square.a7);
      await tap(tester, Square.a6);
      c.moveSan('Bb5+');
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.a7), Piece.blackPawn);
      expect(c.turn, PieceColor.black);
      expect(moves, isEmpty);
      expect(tints(tester).values, isNot(contains(_theme.premoveColor)));
    });

    testWidgets('a promotion premove becomes a queen', (tester) async {
      final c = ChessBoardController(fen: '8/8/8/8/8/k7/6p1/K7 w - - 0 1');
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.g2);
      await tap(tester, Square.g1);
      c.moveSan('Kb1');
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.g1), Piece.blackQueen);
    });

    testWidgets('king onto its own rook premoves castling', (tester) async {
      final c = ChessBoardController(
        fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
      );
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e8);
      await tap(tester, Square.h8);
      c.moveSan('a3');
      await tester.pumpAndSettle();
      expect(c.lastMove?.castle, CastleSide.kingside);
      expect(c.pieceAt(Square.g8), Piece.blackKing);
    });
  });

  group('timing and animation', () {
    testWidgets('other listeners see the opponent move before the premove', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      final seen = <String?>[];
      c.addListener(() => seen.add(c.lastMove?.san));
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(seen, ['e4', 'e5']);
    });

    testWidgets("the opponent's move still slides in", (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.g8);
      await tap(tester, Square.f6);
      c.move(Square.e2, Square.e4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // The white pawn is still being drawn by the move animation.
      final inFlight = tester
          .widgetList<ChessPieceView>(
            find.descendant(
              of: find.byType(MoveAnimationLayer),
              matching: find.byType(ChessPieceView),
            ),
          )
          .map((v) => v.piece);
      expect(inFlight, contains(Piece.whitePawn));
      expect(c.pieceAt(Square.f6), Piece.blackKnight);
      await tester.pumpAndSettle();
    });

    testWidgets('a premoved recapture onto an own piece', (tester) async {
      // White's bishop is about to take on f6; black premoves gxf6.
      final c = ChessBoardController(
        fen: 'rnbqkb1r/pppppp1p/5np1/6B1/3P4/8/PPP1PPPP/RN1QKBNR w KQkq - 0 3',
      );
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.f6);
      expect(tints(tester)[Square.f6], _theme.premoveColor);
      c.moveSan('Bxf6');
      await tester.pumpAndSettle();
      expect(c.lastMove?.san, 'exf6');
    });

    testWidgets('a premove drag survives the opponent move', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      final g = await tester.startGesture(centerOf(tester, Square.e7));
      await g.moveTo(centerOf(tester, Square.e7) + const Offset(0, 20));
      await tester.pump();
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      await g.moveTo(centerOf(tester, Square.e5));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      // Black's turn now, so the drop is an ordinary move.
      expect(c.lastMove?.san, 'e5');
    });

    testWidgets('a premove selection carries over to a normal move', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.g8);
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      await tap(tester, Square.f6);
      await tester.pumpAndSettle();
      expect(c.lastMove?.san, 'Nf6');
    });

    testWidgets('en passant can be premoved', (tester) async {
      // Black pawn on d4; white is about to play e2-e4.
      final c = ChessBoardController(
        fen: 'rnbqkbnr/ppp1pppp/8/8/3p4/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.d4);
      await tap(tester, Square.e3);
      c.moveSan('e4');
      await tester.pumpAndSettle();
      expect(c.lastMove?.isEnPassant, isTrue);
    });

    testWidgets('castling is dropped when the right is lost meanwhile', (
      tester,
    ) async {
      // Black premoves O-O; white's bishop then checks, so it's illegal.
      final c = ChessBoardController(
        fen:
            'rnbqk2r/pppp1ppp/5n2/2b1p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 0 1',
      );
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e8);
      await tap(tester, Square.g8);
      c.moveSan('Bxf7+');
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e8), Piece.blackKing);
      expect(c.turn, PieceColor.black);
    });
  });

  group('cancelling', () {
    testWidgets('pressing off a premove destination cancels it', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      await tap(tester, Square.h4);
      expect(tints(tester).values, isNot(contains(_theme.premoveColor)));
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e7), Piece.blackPawn);
    });

    testWidgets('a new premove replaces the old one', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      await tap(tester, Square.d7);
      await tap(tester, Square.d5);
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.d5), Piece.blackPawn);
      expect(c.pieceAt(Square.e7), Piece.blackPawn);
    });

    testWidgets('undo drops a queued premove', (tester) async {
      final c = ChessBoardController()..moveSan('e4');
      await pumpBoard(tester, blackBoard(c));
      // It's black's turn; play black, then premove the next black move.
      c.moveSan('e5');
      await tester.pumpAndSettle();
      await tap(tester, Square.d7);
      await tap(tester, Square.d6);
      c.undo();
      await tester.pumpAndSettle();
      expect(tints(tester).values, isNot(contains(_theme.premoveColor)));
    });

    testWidgets('a controller swap drops a queued premove', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      final next = ChessBoardController();
      await tester.pumpWidget(host(blackBoard(next)));
      next.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(next.pieceAt(Square.e7), Piece.blackPawn);
    });

    testWidgets('turning premoves off drops a queued one', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      await tester.pumpWidget(host(blackBoard(c, premoves: false)));
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e7), Piece.blackPawn);
    });
  });

  group('availability', () {
    testWidgets('off by default', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, interactiveSide: InteractiveSide.black),
      );
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e7), Piece.blackPawn);
    });

    testWidgets('unavailable when both sides are interactive', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, blackBoard(c, side: InteractiveSide.both));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      c.move(Square.e2, Square.e4);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e7), Piece.blackPawn);
    });

    testWidgets('own-turn moves still play at once', (tester) async {
      final c = ChessBoardController()..moveSan('e4');
      await pumpBoard(tester, blackBoard(c));
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      expect(c.pieceAt(Square.e5), Piece.blackPawn);
    });
  });
}
