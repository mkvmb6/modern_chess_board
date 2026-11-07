import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/drag_feedback_layer.dart';
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

/// Starts a drag from [from] and moves the pointer onto [over].
Future<TestGesture> dragOver(
  WidgetTester tester,
  Square from,
  Square over,
) async {
  final start = centerOf(tester, from);
  final end = centerOf(tester, over);
  final gesture = await tester.startGesture(start);
  for (var i = 1; i <= 6; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / 6)!);
    await tester.pump();
  }
  return gesture;
}

/// What the drag feedback layer currently shows, or null when nothing.
DropTarget? feedback(WidgetTester tester) {
  final paint = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is DragFeedbackPainter,
  );
  if (paint.evaluate().isEmpty) return null;
  return (tester.widget<CustomPaint>(paint).painter! as DragFeedbackPainter)
      .target;
}

void main() {
  testWidgets('a legal square under the pointer shows the legal frame', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final g = await dragOver(tester, Square.g1, Square.f3);
    expect(feedback(tester), const DropTarget(Square.f3, legal: true));
    await g.up();
  });

  testWidgets('an illegal square under the pointer shows the illegal tint', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final g = await dragOver(tester, Square.g1, Square.g3);
    expect(feedback(tester), const DropTarget(Square.g3, legal: false));
    await g.up();
  });

  testWidgets('the source square shows neither', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final start = centerOf(tester, Square.e2);
    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(25, 0));
    await tester.pump();
    await g.moveTo(start);
    await tester.pump();
    expect(feedback(tester), isNull);
    await g.up();
  });

  testWidgets('off the board, nothing is shown', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final g = await dragOver(tester, Square.e2, Square.e4);
    await g.moveTo(tester.getBottomRight(_squares()) + const Offset(30, 30));
    await tester.pump();
    expect(feedback(tester), isNull);
    await g.up();
  });

  testWidgets('the indicator follows the pointer square by square', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final g = await dragOver(tester, Square.e2, Square.e3);
    expect(feedback(tester), const DropTarget(Square.e3, legal: true));
    await g.moveTo(centerOf(tester, Square.e4));
    await tester.pump();
    expect(feedback(tester), const DropTarget(Square.e4, legal: true));
    await g.moveTo(centerOf(tester, Square.e5));
    await tester.pump();
    expect(feedback(tester), const DropTarget(Square.e5, legal: false));
    await g.up();
  });

  testWidgets('dragging the king over its own rook shows legal castling', (
    tester,
  ) async {
    final c = ChessBoardController(
      fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
    );
    await pumpBoard(tester, ChessBoard(controller: c));
    final g = await dragOver(tester, Square.e1, Square.h1);
    expect(feedback(tester), const DropTarget(Square.h1, legal: true));
    await g.up();
  });

  for (final ending in ['drop', 'cancel']) {
    testWidgets('all indicators clear when the drag ends by $ending', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final g = await dragOver(tester, Square.e2, Square.e4);
      expect(feedback(tester), isNotNull);
      if (ending == 'drop') {
        await g.up();
      } else {
        await g.cancel();
      }
      await tester.pump();
      expect(feedback(tester), isNull);
    });
  }

  testWidgets('an illegal drop clears the illegal tint too', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final g = await dragOver(tester, Square.g1, Square.g4);
    expect(feedback(tester)?.legal, isFalse);
    await g.up();
    await tester.pump();
    expect(feedback(tester), isNull);
  });

  testWidgets('a read-only board never shows drag indicators', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c, readOnly: true));
    final g = await dragOver(tester, Square.e2, Square.e4);
    expect(feedback(tester), isNull);
    await g.up();
  });

  testWidgets('pointer moves repaint only the feedback layer', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final before = tester.widget<CustomPaint>(_squares()).painter;
    final g = await dragOver(tester, Square.e2, Square.e4);
    expect(
      identical(tester.widget<CustomPaint>(_squares()).painter, before),
      isTrue,
    );
    // Moves within one square leave the feedback painter untouched: the
    // same painter object means no rebuild and no repaint.
    final painter = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DragFeedbackPainter,
    );
    final first = tester.widget<CustomPaint>(painter).painter;
    final center = centerOf(tester, Square.e4);
    for (final d in const [
      Offset(5, 0),
      Offset(-6, 4),
      Offset(8, -8),
      Offset(-10, 9),
      Offset(12, 3),
    ]) {
      await g.moveTo(center + d);
      await tester.pump();
      expect(
        identical(tester.widget<CustomPaint>(painter).painter, first),
        isTrue,
      );
    }
    await g.up();
  });

  testWidgets('a pawn dragged over the last rank shows legal', (tester) async {
    final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
    await pumpBoard(tester, ChessBoard(controller: c));
    final g = await dragOver(tester, Square.a7, Square.a8);
    expect(feedback(tester), const DropTarget(Square.a8, legal: true));
    await g.up();
  });

  testWidgets('dragging into the outside label margin shows nothing', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(
      tester,
      ChessBoard(controller: c, coordinates: CoordinateMode.outside),
    );
    final g = await dragOver(tester, Square.a2, Square.a3);
    expect(feedback(tester), isNotNull);
    // Just left of the a-file, in the rank label margin.
    await g.moveTo(centerOf(tester, Square.a3) - const Offset(28, 0));
    await tester.pump();
    expect(feedback(tester), isNull);
    await g.up();
  });

  testWidgets('a code move mid-drag clears the target', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final g = await dragOver(tester, Square.e2, Square.e4);
    expect(feedback(tester), isNotNull);
    c.move(Square.d2, Square.d4);
    await tester.pump();
    expect(feedback(tester), isNull);
    await g.up();
  });

  testWidgets('on touch, the target is the square under the finger', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    // dragOver uses touch; the floating piece is drawn above the finger,
    // but the target is the finger's square.
    final g = await dragOver(tester, Square.e2, Square.e3);
    expect(feedback(tester)?.square, Square.e3);
    await g.up();
  });
}
