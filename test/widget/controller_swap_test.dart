import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

Widget host(ChessBoardController c) => MaterialApp(
  home: Material(
    child: Center(
      child: SizedBox.square(dimension: 400, child: ChessBoard(controller: c)),
    ),
  ),
);

Future<void> settlePieces(WidgetTester tester) async {
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => PieceSet.standard.precache(context));
  await tester.pump();
}

Set<Piece> piecesShown(WidgetTester tester) => {
  for (final v in tester.widgetList<ChessPieceView>(
    find.byType(ChessPieceView),
  ))
    v.piece,
};

void main() {
  testWidgets('swapping controllers shows the new game', (tester) async {
    final a = ChessBoardController();
    final b = ChessBoardController(fen: '4k3/8/8/8/8/8/8/4K2R w K - 0 1');
    await tester.pumpWidget(host(a));
    await settlePieces(tester);
    expect(find.byType(ChessPieceView), findsNWidgets(32));

    await tester.pumpWidget(host(b));
    expect(find.byType(ChessPieceView), findsNWidgets(3));
    expect(piecesShown(tester), {
      Piece.whiteKing,
      Piece.blackKing,
      Piece.whiteRook,
    });
  });

  testWidgets('after a swap the board follows the new controller only', (
    tester,
  ) async {
    final a = ChessBoardController();
    final b = ChessBoardController(fen: '4k3/8/8/8/8/8/8/4K2R w K - 0 1');
    await tester.pumpWidget(host(a));
    await settlePieces(tester);
    await tester.pumpWidget(host(b));

    // Changes to the old controller no longer reach the board.
    a.loadFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1');
    await tester.pump();
    expect(find.byType(ChessPieceView), findsNWidgets(3));

    // Changes to the new one do.
    b.move(Square.h1, Square.h8);
    await tester.pump();
    final rookSquares = tester
        .widgetList<ChessPieceView>(find.byType(ChessPieceView))
        .where((v) => v.piece == Piece.whiteRook);
    expect(rookSquares, hasLength(1));
    expect(b.pieceAt(Square.h8), Piece.whiteRook);
  });

  testWidgets('the old controller has no listeners left from the board', (
    tester,
  ) async {
    final a = _CountingController();
    await tester.pumpWidget(host(a));
    await settlePieces(tester);
    expect(a.listeners, greaterThan(0));
    await tester.pumpWidget(host(ChessBoardController()));
    expect(a.listeners, 0);
  });

  testWidgets('removing the board removes its listeners', (tester) async {
    final a = _CountingController();
    await tester.pumpWidget(host(a));
    await settlePieces(tester);
    await tester.pumpWidget(const SizedBox());
    expect(a.listeners, 0);
  });

  testWidgets('swapping back and forth keeps working', (tester) async {
    final a = ChessBoardController();
    final b = ChessBoardController(fen: '4k3/8/8/8/8/8/8/4K2R w K - 0 1');
    await tester.pumpWidget(host(a));
    await settlePieces(tester);
    await tester.pumpWidget(host(b));
    await tester.pumpWidget(host(a));
    a.move(Square.e2, Square.e4);
    await tester.pump();
    expect(find.byType(ChessPieceView), findsNWidgets(32));
    expect(a.pieceAt(Square.e4), Piece.whitePawn);
  });
}

/// Tracks how many listeners are attached, to check the board cleans up.
class _CountingController extends ChessBoardController {
  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }
}
