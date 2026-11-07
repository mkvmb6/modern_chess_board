@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

// See board_golden_test.dart for how goldens are generated and skipped.

Future<void> pumpGolden(
  WidgetTester tester,
  ChessBoardController controller, {
  ChessBoardTheme theme = ChessBoardTheme.green,
}) async {
  tester.view.physicalSize = const Size.square(320);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Material(
        child: Center(
          child: ChessBoard(controller: controller, theme: theme),
        ),
      ),
    ),
  );
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => PieceSet.standard.precache(context));
  await tester.pump();
}

Future<void> tapSquare(WidgetTester tester, Square square) async {
  final squares = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
  );
  final g =
      (tester.widget<CustomPaint>(squares).painter! as BoardSquaresPainter)
          .geometry;
  await tester.tapAt(tester.getTopLeft(squares) + g.squareCenter(square));
  await tester.pump();
}

Future<void> expectGolden(String name) => expectLater(
  find.byType(ChessBoard),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  testWidgets('a selected knight with its moves, after 1.e4 e5', (
    tester,
  ) async {
    final c = ChessBoardController()
      ..moveSan('e4')
      ..moveSan('e5');
    await pumpGolden(tester, c);
    await tapSquare(tester, Square.g1);
    await expectGolden('highlight_selection');
  });

  testWidgets('a pawn with captures on a light and a dark square', (
    tester,
  ) async {
    final c = ChessBoardController(
      fen: 'r1bqkbnr/pp1p1ppp/2n1p3/2pP4/8/8/PPP1PPPP/RNBQKBNR w KQkq - 0 4',
    );
    await pumpGolden(tester, c, theme: ChessBoardTheme.brown);
    await tapSquare(tester, Square.d5);
    await expectGolden('highlight_capture_brown');
  });

  testWidgets('a king ready to castle both ways', (tester) async {
    final c = ChessBoardController(
      fen: 'r3k2r/pppq1ppp/2n2n2/3pp3/3PP3/2N2N2/PPPQ1PPP/R3K2R w KQkq - 0 1',
    );
    await pumpGolden(tester, c, theme: ChessBoardTheme.blue);
    await tapSquare(tester, Square.e1);
    await expectGolden('highlight_castling_blue');
  });

  testWidgets('checkmate with the last move', (tester) async {
    final c = ChessBoardController();
    for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
      c.moveSan(san);
    }
    await pumpGolden(tester, c);
    await expectGolden('highlight_checkmate');
  });
}
