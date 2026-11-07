@Tags(['golden'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

// See board_golden_test.dart for how goldens are generated and skipped.

Future<TestGesture> dragOver(
  WidgetTester tester, {
  required ChessBoardTheme theme,
  required Square from,
  required Square over,
  String? fen,
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
  final start = origin + g.squareCenter(from);
  final end = origin + g.squareCenter(over);
  // A mouse, so the piece sits centered on the target square.
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  for (var i = 1; i <= 6; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / 6)!);
    await tester.pump();
  }
  return gesture;
}

void main() {
  testWidgets('dragging a knight over a legal square', (tester) async {
    final g = await dragOver(
      tester,
      theme: ChessBoardTheme.green,
      from: Square.g1,
      over: Square.f3,
    );
    await expectLater(
      find.byType(ChessBoard),
      matchesGoldenFile('goldens/drag_legal.png'),
    );
    await g.up();
  });

  testWidgets('dragging a pawn over a capture keeps the target piece clear', (
    tester,
  ) async {
    final g = await dragOver(
      tester,
      theme: ChessBoardTheme.green,
      fen: 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
      from: Square.e4,
      over: Square.d5,
    );
    await expectLater(
      find.byType(ChessBoard),
      matchesGoldenFile('goldens/drag_capture.png'),
    );
    await g.up();
  });

  testWidgets('dragging a knight over an illegal square, brown', (
    tester,
  ) async {
    final g = await dragOver(
      tester,
      theme: ChessBoardTheme.brown,
      from: Square.g1,
      over: Square.g4,
    );
    await expectLater(
      find.byType(ChessBoard),
      matchesGoldenFile('goldens/drag_illegal_brown.png'),
    );
    await g.up();
  });
}
