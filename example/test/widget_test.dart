import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board_example/demo_state.dart';
import 'package:modern_chess_board_example/main.dart';

Future<DemoState> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = DemoState(
    random: Random(1),
    opponentDelay: const Duration(milliseconds: 10),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(ExampleApp(state: state));
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => PieceSet.standard.precache(context));
  await tester.pumpAndSettle();
  return state;
}

/// Opens the options sheet, from the labelled button on wide screens or
/// the toolbar icon on small ones.
Future<void> openOptions(WidgetTester tester) async {
  final labelled = find.text('Options');
  await tester.tap(
    labelled.evaluate().isNotEmpty ? labelled : find.byTooltip('Options'),
  );
}

void main() {
  testWidgets('the demo shows a board and the score sheet', (tester) async {
    await pumpApp(tester);
    expect(find.byType(ChessBoard), findsOneWidget);
    expect(find.text('White to move.'), findsOneWidget);
    expect(find.text('Moves appear here as you play.'), findsOneWidget);
  });

  testWidgets('moves show up in the score sheet and can be revisited', (
    tester,
  ) async {
    final state = await pumpApp(tester);
    state.controller
      ..moveSan('e4')
      ..moveSan('e5')
      ..moveSan('Nf3');
    await tester.pumpAndSettle();
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('Nf3'), findsOneWidget);
    expect(find.text('Black to move.'), findsOneWidget);
    await tester.tap(find.text('e5'));
    await tester.pumpAndSettle();
    expect(state.controller.ply, 2);
    await tester.tap(find.byTooltip('Latest position'));
    await tester.pumpAndSettle();
    expect(state.controller.ply, 3);
  });

  testWidgets('take back and new game', (tester) async {
    final state = await pumpApp(tester);
    state.controller.moveSan('d4');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take back'));
    await tester.pumpAndSettle();
    expect(state.controller.history, isEmpty);
    state.controller.moveSan('c4');
    await tester.pumpAndSettle();
    await tester.tap(find.text('New game'));
    await tester.pumpAndSettle();
    expect(state.controller.history, isEmpty);
  });

  testWidgets('each theme tile shows a sample of its squares', (tester) async {
    await pumpApp(tester);
    await openOptions(tester);
    await tester.pumpAndSettle();
    final squares = [
      for (final e
          in find
              .descendant(
                of: find.byType(OptionsSheet),
                matching: find.byType(ColoredBox),
              )
              .evaluate())
        (
          tester.getSize(find.byWidget(e.widget)),
          (e.widget as ColoredBox).color,
        ),
    ].where((s) => s.$1.width >= 20).toList();
    // Five themes, four squares each, all visible.
    expect(squares, hasLength(20));
    for (final (size, _) in squares) {
      expect(size, const Size(24, 24));
    }
    expect(squares.first.$2, ChessBoardTheme.green.lightSquareColor);
    expect(squares[1].$2, ChessBoardTheme.green.darkSquareColor);
  });

  testWidgets('the options sheet changes the board', (tester) async {
    final state = await pumpApp(tester);
    await openOptions(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Brown board'));
    await tester.pumpAndSettle();
    expect(state.theme, ChessBoardTheme.brown);
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).theme,
      ChessBoardTheme.brown,
    );
  });

  testWidgets('the random opponent answers the user', (tester) async {
    final state = await pumpApp(tester);
    state.opponent = Opponent.randomBlack;
    await tester.pumpAndSettle();
    state.controller.moveSan('e4');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(state.controller.history.length, 2);
    expect(state.controller.turn, PieceColor.white);
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).interactiveSide,
      InteractiveSide.white,
    );
  });

  testWidgets('a premove plays after the opponent replies', (tester) async {
    final state = await pumpApp(tester);
    state.opponent = Opponent.randomBlack;
    await tester.pumpAndSettle();
    state.controller.moveSan('e4');
    await tester.pump();
    // During black's "thinking", queue Nf3 by tapping.
    final board = find.byType(ChessBoard);
    final origin = tester.getTopLeft(board);
    final square = tester.getSize(board).width / 8;
    Offset at(Square s) =>
        origin + Offset((s.file + 0.5) * square, (7 - s.rank + 0.5) * square);
    await tester.tapAt(at(Square.g1));
    await tester.pump();
    await tester.tapAt(at(Square.f3));
    await tester.pump();
    expect(state.controller.history.length, 1);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    // Black replied, the premove played at once, and black replied again.
    final sans = state.controller.history.map((m) => m.san).toList();
    expect(sans.length, greaterThanOrEqualTo(3));
    expect(sans[2], 'Nf3');
  });

  testWidgets('a game starting with black numbers like a score sheet', (
    tester,
  ) async {
    final state = await pumpApp(tester);
    state.loadAny(
      'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 12',
    );
    state.controller
      ..moveSan('e5')
      ..moveSan('Nf3');
    await tester.pumpAndSettle();
    expect(find.text('12.'), findsOneWidget);
    expect(find.text('13.'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    state.controller.back();
    await tester.pumpAndSettle();
    expect(find.textContaining('12… e5'), findsOneWidget);
  });

  testWidgets('a PGN loads, including one with no headers', (tester) async {
    final state = await pumpApp(tester);
    expect(state.loadAny('not chess at all'), isFalse);
    expect(state.loadAny('1. e4 e5 2. Nf3 Nc6'), isTrue);
    expect(state.controller.history.length, 4);
    await tester.pumpAndSettle();
    expect(find.text('Nc6'), findsOneWidget);
  });

  testWidgets('a finished game shows its result', (tester) async {
    final state = await pumpApp(tester);
    for (final m in ['f3', 'e5', 'g4', 'Qh4#']) {
      state.controller.moveSan(m);
    }
    await tester.pumpAndSettle();
    expect(find.text('Checkmate. Black wins.'), findsOneWidget);
    expect(find.text('0–1'), findsOneWidget);
  });

  testWidgets('loading a bad FEN explains what went wrong', (tester) async {
    await pumpApp(tester);
    await openOptions(tester);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Load a FEN or PGN'),
      100,
      scrollable: find.descendant(
        of: find.byType(OptionsSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Load a FEN or PGN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not a position');
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    // The dialog stays open with the reason, so the text can be fixed.
    expect(find.textContaining("can't read that"), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('on a wide screen the score sheet sits beside the board', (
    tester,
  ) async {
    final state = await pumpApp(tester, size: const Size(1280, 800));
    for (final m in ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6']) {
      state.controller.moveSan(m);
    }
    await tester.pumpAndSettle();
    final board = tester.getRect(find.byType(ChessBoard));
    final sheet = tester.getRect(find.text('Nf3'));
    expect(board.height, greaterThan(700));
    expect(sheet.left, greaterThan(board.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the options sheet fits a phone', (tester) async {
    await pumpApp(tester, size: const Size(360, 740));
    await openOptions(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Coordinates'),
      100,
      scrollable: find.descendant(
        of: find.byType(OptionsSheet),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(800, 600), Size(844, 390), Size(360, 640)]) {
    testWidgets('fits $size without overflow', (tester) async {
      await pumpApp(tester, size: size);
      expect(tester.takeException(), isNull);
      final board = tester.getRect(find.byType(ChessBoard));
      expect(board.bottom, lessThanOrEqualTo(size.height));
      expect(board.right, lessThanOrEqualTo(size.width));
      expect(board.width, greaterThan(150));
    });
  }

  testWidgets('fits a phone screen without overflow', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));
    expect(find.byType(ChessBoard), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The board fills the width less the margins.
    expect(tester.getSize(find.byType(ChessBoard)).width, greaterThan(350));
  });
}
