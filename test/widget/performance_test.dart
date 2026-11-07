import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/chess_board.dart'
    show debugBoardBuildCount;
import 'package:modern_chess_board/src/widget/layers/highlight_layer.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

/// Guards for requirement 14: interactions rebuild and repaint only the
/// layers they touch, and never the board as a whole.

Widget host(ChessBoard board) => MaterialApp(
  home: Material(
    child: Center(child: SizedBox.square(dimension: 400, child: board)),
  ),
);

Future<void> pumpBoard(WidgetTester tester, ChessBoard board) async {
  await tester.pumpWidget(host(board));
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => board.pieceSet.precache(context));
  await tester.pumpAndSettle();
}

Finder _squares() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
);

Offset centerOf(WidgetTester tester, Square square) =>
    tester.getTopLeft(_squares()) +
    (tester.widget<CustomPaint>(_squares()).painter! as BoardSquaresPainter)
        .geometry
        .squareCenter(square);

/// Counts paints of each painter type while [body] runs.
Future<Map<Type, int>> countPaints(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final counts = <Type, int>{};
  // Both are reset before the test ends; the test binding checks that.
  debugProfilePaintsEnabled = true;
  debugOnProfilePaint = (RenderObject o) {
    if (o is RenderCustomPaint && o.painter != null) {
      counts.update(o.painter.runtimeType, (n) => n + 1, ifAbsent: () => 1);
    }
  };
  try {
    await body();
  } finally {
    debugOnProfilePaint = null;
    debugProfilePaintsEnabled = false;
  }
  return counts;
}

void main() {
  testWidgets('selecting a piece repaints only the highlight layers', (
    tester,
  ) async {
    await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
    final builds = debugBoardBuildCount;
    final paints = await countPaints(tester, () async {
      await tester.tapAt(centerOf(tester, Square.g1));
      await tester.pump();
    });
    expect(debugBoardBuildCount, builds);
    expect(paints.keys.toSet(), {BoardTintsPainter, BoardMarkersPainter});
    expect(paints[BoardTintsPainter], 1);
    expect(paints[BoardMarkersPainter], 1);
  });

  testWidgets('hovering with a selection repaints only the tints', (
    tester,
  ) async {
    await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
    await tester.tapAt(centerOf(tester, Square.g1));
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: centerOf(tester, Square.a4));
    await tester.pump();
    final builds = debugBoardBuildCount;
    final paints = await countPaints(tester, () async {
      for (final s in [Square.f3, Square.h3, Square.e4]) {
        await mouse.moveTo(centerOf(tester, s));
        await tester.pump();
      }
    });
    expect(debugBoardBuildCount, builds);
    // The legal-move dots don't change on hover, so the markers stay put.
    expect(paints[BoardMarkersPainter], isNull);
    expect(paints.keys.toSet(), {BoardTintsPainter});
    await mouse.removePointer();
  });

  testWidgets('dragging repaints no square, label or highlight layer', (
    tester,
  ) async {
    await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
    final g = await tester.startGesture(centerOf(tester, Square.e2));
    await g.moveBy(const Offset(0, -20));
    await tester.pump();
    final builds = debugBoardBuildCount;
    final paints = await countPaints(tester, () async {
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, -10));
        await tester.pump();
      }
    });
    expect(debugBoardBuildCount, builds);
    expect(paints[BoardSquaresPainter], isNull);
    expect(paints[BoardTintsPainter], isNull);
    expect(paints[BoardMarkersPainter], isNull);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a move animation rebuilds and repaints no static layer', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    c.moveSan('Nf3');
    await tester.pump();
    final builds = debugBoardBuildCount;
    final paints = await countPaints(tester, () async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
    expect(debugBoardBuildCount, builds);
    expect(paints[BoardSquaresPainter], isNull);
    expect(paints[BoardTintsPainter], isNull);
    expect(paints[BoardMarkersPainter], isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('a notification that changes nothing costs nothing', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final builds = debugBoardBuildCount;
    final paints = await countPaints(tester, () async {
      c.allowBranching = true;
      await tester.pump();
    });
    expect(debugBoardBuildCount, builds);
    expect(paints, isEmpty);
  });
}
