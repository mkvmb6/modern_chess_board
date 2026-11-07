import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/src/widget/board_geometry.dart';

const _boardKey = Key('board');

/// A layout whose child marks the board's own square box.
Widget board({
  CoordinateMode coordinates = CoordinateMode.inside,
  void Function(BoardMetrics)? onMetrics,
}) => BoardLayout(
  coordinates: coordinates,
  builder: (context, metrics) {
    onMetrics?.call(metrics);
    return const ColoredBox(key: _boardKey, color: Colors.green);
  },
);

Future<Size> pumpIn(WidgetTester tester, Widget parent) async {
  await tester.pumpWidget(
    Directionality(textDirection: TextDirection.ltr, child: parent),
  );
  expect(tester.takeException(), isNull);
  return tester.getSize(find.byKey(_boardKey));
}

void main() {
  testWidgets('wide space gives a square the height of the space', (
    tester,
  ) async {
    final size = await pumpIn(
      tester,
      Center(child: SizedBox(width: 500, height: 300, child: board())),
    );
    expect(size, const Size(300, 300));
  });

  testWidgets('tall space gives a square the width of the space', (
    tester,
  ) async {
    final size = await pumpIn(
      tester,
      Center(child: SizedBox(width: 280, height: 700, child: board())),
    );
    expect(size, const Size(280, 280));
  });

  testWidgets('a forced non-square size keeps the board square and centered', (
    tester,
  ) async {
    await pumpIn(
      tester,
      Center(child: SizedBox(width: 400, height: 240, child: board())),
    );
    final rect = tester.getRect(find.byKey(_boardKey));
    expect(rect.size, const Size(240, 240));
    final outer = tester.getRect(find.byType(BoardLayout));
    expect(rect.center, outer.center);
  });

  testWidgets('inside a Column the board uses the width', (tester) async {
    final size = await pumpIn(
      tester,
      Center(
        child: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [board()]),
        ),
      ),
    );
    expect(size, const Size(360, 360));
  });

  testWidgets('inside a Row the board uses the height', (tester) async {
    final size = await pumpIn(
      tester,
      Center(
        child: SizedBox(
          height: 220,
          child: Row(mainAxisSize: MainAxisSize.min, children: [board()]),
        ),
      ),
    );
    expect(size, const Size(220, 220));
  });

  testWidgets('with no bounds at all the board falls back to a default', (
    tester,
  ) async {
    final size = await pumpIn(
      tester,
      Center(child: UnconstrainedBox(child: board())),
    );
    expect(size, const Size.square(kDefaultBoardSize));
  });

  testWidgets('in a vertical scroll view the board is as wide as the view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final size = await pumpIn(tester, SingleChildScrollView(child: board()));
    expect(size, const Size(400, 400));
  });

  testWidgets('outside mode fits board and margins in the space', (
    tester,
  ) async {
    late BoardMetrics metrics;
    await pumpIn(
      tester,
      Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: board(
            coordinates: CoordinateMode.outside,
            onMetrics: (m) => metrics = m,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(BoardLayout)), const Size(300, 300));
    expect(metrics.outerSize, 300);
    expect(metrics.boardSize + 2 * metrics.margin, closeTo(300, 1e-9));
    expect(metrics.margin, greaterThan(0));
  });

  testWidgets('works inside IntrinsicHeight next to a move list', (
    tester,
  ) async {
    await pumpIn(
      tester,
      Center(
        child: SizedBox(
          width: 600,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 300, child: board()),
                const Expanded(child: ColoredBox(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(_boardKey)), const Size(300, 300));
  });

  testWidgets('in a loose Flexible the board takes only its square', (
    tester,
  ) async {
    await pumpIn(
      tester,
      Center(
        child: SizedBox(
          width: 600,
          height: 300,
          child: Row(
            children: [
              Flexible(child: board()),
              const Text('moves'),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(BoardLayout)), const Size(300, 300));
    expect(tester.getSize(find.byKey(_boardKey)), const Size(300, 300));
  });

  testWidgets('in a Stack the board takes only its square', (tester) async {
    await pumpIn(
      tester,
      Center(
        child: SizedBox(
          width: 500,
          height: 300,
          child: Stack(children: [board()]),
        ),
      ),
    );
    expect(tester.getSize(find.byType(BoardLayout)), const Size(300, 300));
  });

  testWidgets('in a SliverToBoxAdapter the board is as wide as the view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final size = await pumpIn(
      tester,
      CustomScrollView(slivers: [SliverToBoxAdapter(child: board())]),
    );
    expect(size, const Size(360, 360));
  });

  testWidgets('the fallback size can be changed', (tester) async {
    await pumpIn(
      tester,
      Center(
        child: UnconstrainedBox(
          child: BoardLayout(
            coordinates: CoordinateMode.inside,
            fallbackSize: 180,
            builder: (context, metrics) =>
                const ColoredBox(key: _boardKey, color: Colors.green),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(_boardKey)), const Size(180, 180));
  });

  testWidgets('labels follow the app text scale', (tester) async {
    late BoardMetrics metrics;
    await pumpIn(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Center(
          child: SizedBox.square(
            dimension: 400,
            child: board(onMetrics: (m) => metrics = m),
          ),
        ),
      ),
    );
    final plain = BoardMetrics.forSide(400, CoordinateMode.inside);
    expect(metrics.labelFontSize, greaterThan(plain.labelFontSize));
  });

  testWidgets('metrics update when the space changes', (tester) async {
    final seen = <double>[];
    Widget at(double w) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: w,
          height: w,
          child: board(onMetrics: (m) => seen.add(m.outerSize)),
        ),
      ),
    );
    await tester.pumpWidget(at(200));
    await tester.pumpWidget(at(320));
    expect(seen.first, 200);
    expect(seen.last, 320);
  });
}
