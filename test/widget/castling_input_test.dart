import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

const _bothSides = 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1';

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

Future<void> tapSquare(WidgetTester tester, Square square) async {
  await tester.tapAt(centerOf(tester, square));
  await tester.pump();
}

Future<void> dragTo(WidgetTester tester, Square from, Square to) async {
  final start = centerOf(tester, from);
  final end = centerOf(tester, to);
  final gesture = await tester.startGesture(start);
  for (var i = 1; i <= 6; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / 6)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

typedef Input = Future<void> Function(WidgetTester, Square, Square);

Future<void> tapInput(WidgetTester t, Square from, Square to) async {
  await tapSquare(t, from);
  await tapSquare(t, to);
}

void main() {
  // Each case: who moves, king from, target pressed, side, rook from/to.
  final cases = [
    (
      PieceColor.white,
      Square.e1,
      Square.g1,
      CastleSide.kingside,
      Square.h1,
      Square.f1,
    ),
    (
      PieceColor.white,
      Square.e1,
      Square.h1,
      CastleSide.kingside,
      Square.h1,
      Square.f1,
    ),
    (
      PieceColor.white,
      Square.e1,
      Square.c1,
      CastleSide.queenside,
      Square.a1,
      Square.d1,
    ),
    (
      PieceColor.white,
      Square.e1,
      Square.a1,
      CastleSide.queenside,
      Square.a1,
      Square.d1,
    ),
    (
      PieceColor.black,
      Square.e8,
      Square.g8,
      CastleSide.kingside,
      Square.h8,
      Square.f8,
    ),
    (
      PieceColor.black,
      Square.e8,
      Square.h8,
      CastleSide.kingside,
      Square.h8,
      Square.f8,
    ),
    (
      PieceColor.black,
      Square.e8,
      Square.c8,
      CastleSide.queenside,
      Square.a8,
      Square.d8,
    ),
    (
      PieceColor.black,
      Square.e8,
      Square.a8,
      CastleSide.queenside,
      Square.a8,
      Square.d8,
    ),
  ];

  for (final (inputName, input) in <(String, Input)>[
    ('tap', tapInput),
    ('drag', dragTo),
  ]) {
    for (final (color, king, target, side, rookFrom, rookTo) in cases) {
      testWidgets(
        '${color.name} castles ${side.name} by $inputName to ${target.name}',
        (tester) async {
          final fen = color == PieceColor.white
              ? _bothSides
              : _bothSides.replaceFirst(' w ', ' b ');
          final c = ChessBoardController(fen: fen);
          await pumpBoard(tester, ChessBoard(controller: c));
          await input(tester, king, target);
          expect(c.lastMove?.castle, side, reason: 'castled');
          final kingTo = side == CastleSide.kingside
              ? Square.at(6, king.rank)
              : Square.at(2, king.rank);
          expect(c.pieceAt(kingTo), Piece(color, PieceType.king));
          expect(c.pieceAt(rookTo), Piece(color, PieceType.rook));
          expect(c.pieceAt(rookFrom), isNull);
          expect(c.lastMove!.to, kingTo, reason: 'reported as the king move');
        },
      );
    }
  }

  testWidgets('tapping the own rook without castling rights switches the '
      'selection instead', (tester) async {
    final c = ChessBoardController(
      fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w kq - 0 1',
    );
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e1);
    await tapSquare(tester, Square.h1);
    expect(c.history, isEmpty);
    // The rook is now selected and can move.
    await tapSquare(tester, Square.g1);
    expect(c.pieceAt(Square.g1), Piece.whiteRook);
  });

  testWidgets('king onto rook is not castling when the path is blocked', (
    tester,
  ) async {
    final c = ChessBoardController(
      fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3KB1R w KQkq - 0 1',
    );
    await pumpBoard(tester, ChessBoard(controller: c));
    await dragTo(tester, Square.e1, Square.h1);
    expect(c.history, isEmpty);
    expect(c.pieceAt(Square.e1), Piece.whiteKing);
  });

  testWidgets('king onto rook is not castling while in check', (tester) async {
    final c = ChessBoardController(
      fen: 'r3k2r/pppp1ppp/8/8/4r3/8/PPPP1PPP/R3K2R w KQkq - 0 1',
    );
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e1);
    await tapSquare(tester, Square.h1);
    expect(c.lastMove, isNull);
  });

  testWidgets('with rights on one side only, the other rook is selected', (
    tester,
  ) async {
    final c = ChessBoardController(
      fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w K - 0 1',
    );
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e1);
    await tapSquare(tester, Square.a1);
    expect(c.history, isEmpty, reason: 'no queenside rights');
    await tapSquare(tester, Square.e1);
    await tapSquare(tester, Square.h1);
    expect(c.lastMove!.castle, CastleSide.kingside);
  });

  testWidgets('king onto rook castles with black at the bottom', (
    tester,
  ) async {
    final c = ChessBoardController(fen: _bothSides);
    await pumpBoard(
      tester,
      ChessBoard(controller: c, orientation: BoardOrientation.black),
    );
    await dragTo(tester, Square.e1, Square.a1);
    expect(c.lastMove!.castle, CastleSide.queenside);
  });

  testWidgets('an ordinary two-square king move elsewhere is not castling', (
    tester,
  ) async {
    final c = ChessBoardController(fen: '4k3/8/8/8/3K4/8/8/8 w - - 0 1');
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.d4);
    await tapSquare(tester, Square.f4);
    expect(c.history, isEmpty, reason: 'kings move one square');
  });
}
