@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

// See board_golden_test.dart for how goldens are generated and skipped.

Future<void> openPicker(
  WidgetTester tester, {
  required String fen,
  required Square from,
  required Square to,
  BoardOrientation orientation = BoardOrientation.white,
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
          child: ChessBoard(
            controller: ChessBoardController(fen: fen),
            orientation: orientation,
            theme: theme,
          ),
        ),
      ),
    ),
  );
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => PieceSet.standard.precache(context));
  await tester.pump();
  final squares = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
  );
  final g =
      (tester.widget<CustomPaint>(squares).painter! as BoardSquaresPainter)
          .geometry;
  final origin = tester.getTopLeft(squares);
  await tester.tapAt(origin + g.squareCenter(from));
  await tester.pump();
  await tester.tapAt(origin + g.squareCenter(to));
  await tester.pump();
  // Capture the picker after it has finished appearing.
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('white promotes on the top edge', (tester) async {
    await openPicker(
      tester,
      fen: '1r5k/P7/8/8/8/8/8/K7 w - - 0 1',
      from: Square.a7,
      to: Square.a8,
    );
    await expectLater(
      find.byType(ChessBoard),
      matchesGoldenFile('goldens/promotion_white_top.png'),
    );
  });

  testWidgets('black promotes on the bottom edge, brown theme', (tester) async {
    await openPicker(
      tester,
      fen: 'k7/8/8/8/8/8/6p1/K7 b - - 0 1',
      from: Square.g2,
      to: Square.g1,
      theme: ChessBoardTheme.brown,
    );
    await expectLater(
      find.byType(ChessBoard),
      matchesGoldenFile('goldens/promotion_black_bottom_brown.png'),
    );
  });
}
