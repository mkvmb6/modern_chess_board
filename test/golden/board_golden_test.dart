@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

// Goldens are generated on Windows with Roboto loaded by
// test/flutter_test_config.dart. Font rendering differs slightly between
// operating systems, so other platforms should skip them:
//   flutter test --exclude-tags golden
// Regenerate on Windows with:
//   flutter test --update-goldens --tags golden

const _names = ['green', 'brown', 'blue', 'purple', 'monochrome'];

/// A position with pieces of every kind and some open squares, so square
/// colors, labels and pieces all show.
const _fen =
    'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5';

Future<void> pumpGolden(
  WidgetTester tester,
  Widget board, {
  double side = 320,
  Color background = const Color(0xFFFFFFFF),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size.square(side);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto', brightness: brightness),
      home: Material(
        color: background,
        child: Center(child: board),
      ),
    ),
  );
  // Wait for the piece set to finish loading, rather than a fixed delay.
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => PieceSet.standard.precache(context));
  await tester.pump();
}

Future<void> expectGolden(String name) => expectLater(
  find.byType(ChessBoard),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  for (final (i, theme) in ChessBoardTheme.presets.indexed) {
    for (final mode in CoordinateMode.values) {
      testWidgets('${_names[i]} ${mode.name}', (tester) async {
        await pumpGolden(
          tester,
          ChessBoard(
            controller: ChessBoardController(fen: _fen),
            theme: theme,
            coordinates: mode,
          ),
        );
        await expectGolden('${_names[i]}_${mode.name}');
      });
    }
  }

  testWidgets('black at the bottom', (tester) async {
    await pumpGolden(
      tester,
      ChessBoard(
        controller: ChessBoardController(fen: _fen),
        orientation: BoardOrientation.black,
      ),
    );
    await expectGolden('green_black_bottom');
  });

  testWidgets('small board hides crowded labels', (tester) async {
    await pumpGolden(
      tester,
      ChessBoard(controller: ChessBoardController(fen: _fen)),
      side: 140,
    );
    await expectGolden('green_small');
  });

  testWidgets('outside labels on a dark app', (tester) async {
    await pumpGolden(
      tester,
      ChessBoard(
        controller: ChessBoardController(fen: _fen),
        theme: ChessBoardTheme.brown,
        coordinates: CoordinateMode.outside,
      ),
      background: const Color(0xFF262421),
      brightness: Brightness.dark,
    );
    await expectGolden('brown_outside_dark_app');
  });
}
