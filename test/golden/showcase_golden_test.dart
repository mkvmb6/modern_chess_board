@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

/// A mid-game position with app arrows, a hint, marks, the last move and a
/// selection, as one picture of the board's look. It doubles as the README
/// screenshot (`doc/board.png`), so the image is always made from code.
void main() {
  testWidgets('showcase', (tester) async {
    tester.view.physicalSize = const Size(640, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ChessBoardController();
    for (final san in [
      'e4',
      'e5',
      'Nf3',
      'Nc6',
      'Bb5',
      'a6',
      'Ba4',
      'Nf6',
      'O-O',
      'Be7',
    ]) {
      c.moveSan(san);
    }
    final board = ChessBoard(
      controller: c,
      theme: ChessBoardTheme.green,
      arrows: const [Arrow('f1', 'e1'), Arrow('b1', 'c3')],
      marks: const [SquareMark('e5')],
      hint: const Arrow('d2', 'd4'),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Material(
          color: const Color(0xFF1E2620),
          child: Center(child: SizedBox.square(dimension: 600, child: board)),
        ),
      ),
    );
    final context = tester.element(find.byType(ChessBoard));
    await tester.runAsync(() => board.pieceSet.precache(context));
    await tester.pump();
    // Select the knight on f3 to show legal-move dots and a capture ring.
    await tester.tapAt(
      tester.getTopLeft(find.byType(ChessBoard)) + const Offset(412.5, 412.5),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ChessBoard),
      matchesGoldenFile('../../doc/board.png'),
    );
  });
}
