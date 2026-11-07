import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/arrows_layer.dart';
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

Future<void> tapSquare(WidgetTester tester, Square square) async {
  await tester.tapAt(centerOf(tester, square));
  await tester.pump();
}

/// What the arrows painter is drawing.
BoardArrowsPainter arrowsPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is BoardArrowsPainter,
              ),
            )
            .painter!
        as BoardArrowsPainter;

void main() {
  group('annotation arrows and marks', () {
    testWidgets('are drawn and do not block touches', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          arrows: const [Arrow('e2', 'e4')],
          marks: const [SquareMark('e2')],
        ),
      );
      expect(arrowsPainter(tester).arrows, const [Arrow('e2', 'e4')]);
      expect(arrowsPainter(tester).marks, const [SquareMark('e2')]);
      // Taps on squares under the arrow still play.
      await tapSquare(tester, Square.e2);
      await tapSquare(tester, Square.e4);
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
    });

    testWidgets('redraw when the list changes', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, arrows: const [Arrow('e2', 'e4')]),
      );
      await tester.pumpWidget(
        host(
          ChessBoard(
            controller: c,
            arrows: const [Arrow('g1', 'f3'), Arrow('d2', 'd4')],
          ),
        ),
      );
      expect(arrowsPainter(tester).arrows, hasLength(2));
      expect(
        arrowsPainter(tester).shouldRepaint(
          BoardArrowsPainter(
            geometry: arrowsPainter(tester).geometry,
            arrows: const [Arrow('e2', 'e4')],
            marks: const [],
            hint: null,
            theme: ChessBoardTheme.green,
          ),
        ),
        isTrue,
      );
    });

    testWidgets('redraw after a flip', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, arrows: const [Arrow('e2', 'e4')]),
      );
      final before = arrowsPainter(tester).geometry;
      await tester.pumpWidget(
        host(
          ChessBoard(
            controller: c,
            orientation: BoardOrientation.black,
            arrows: const [Arrow('e2', 'e4')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(arrowsPainter(tester).geometry, isNot(before));
      expect(
        arrowsPainter(tester).geometry.orientation,
        BoardOrientation.black,
      );
    });

    testWidgets('bad square names do not crash the board', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          arrows: const [Arrow('z9', 'e4'), Arrow('e2', 'e4'), Arrow('', '')],
          marks: const [SquareMark('k1'), SquareMark('d5')],
          hint: const Arrow('x0', 'e4'),
        ),
      );
      expect(tester.takeException(), isNull);
      // Painting skips them; the good ones still draw.
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BoardArrowsPainter,
        ),
        paints..path(),
      );
    });

    testWidgets('the board never changes the app arrow list', (tester) async {
      final c = ChessBoardController();
      final arrows = [const Arrow('e2', 'e4')];
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          arrows: List.unmodifiable(arrows),
          hint: const Arrow('g1', 'f3'),
        ),
      );
      await tapSquare(tester, Square.e2);
      await tapSquare(tester, Square.e4);
      expect(arrowsPainter(tester).arrows, arrows);
    });
  });

  group('hint arrow', () {
    testWidgets('looks different from annotation arrows', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, hint: const Arrow('g1', 'f3')),
      );
      final p = arrowsPainter(tester);
      expect(p.hint, const Arrow('g1', 'f3'));
      expect(p.theme.hintArrowColor, isNot(p.theme.arrowColor));
      // Painted as a dashed stroke with an open head, not a filled shape.
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BoardArrowsPainter,
        ),
        paints..path(style: PaintingStyle.stroke),
      );
    });

    testWidgets('disappears on the next user move', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, hint: const Arrow('g1', 'f3')),
      );
      await tapSquare(tester, Square.e2);
      await tapSquare(tester, Square.e4);
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('disappears on the next code move', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, hint: const Arrow('g1', 'f3')),
      );
      c.move(Square.e2, Square.e4);
      await tester.pump();
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('stays gone when the app rebuilds with the same hint', (
      tester,
    ) async {
      final c = ChessBoardController();
      const hint = Arrow('g1', 'f3');
      await pumpBoard(tester, ChessBoard(controller: c, hint: hint));
      c.move(Square.e2, Square.e4);
      await tester.pump();
      await tester.pumpWidget(host(ChessBoard(controller: c, hint: hint)));
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('disappears when the app clears it', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, hint: const Arrow('g1', 'f3')),
      );
      await tester.pumpWidget(host(ChessBoard(controller: c)));
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('a new hint replaces the old one, even after a move', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, hint: const Arrow('g1', 'f3')),
      );
      await tester.pumpWidget(
        host(ChessBoard(controller: c, hint: const Arrow('b1', 'c3'))),
      );
      expect(arrowsPainter(tester).hint, const Arrow('b1', 'c3'));
      c.move(Square.e2, Square.e4);
      await tester.pump();
      await tester.pumpWidget(
        host(ChessBoard(controller: c, hint: const Arrow('e7', 'e5'))),
      );
      expect(arrowsPainter(tester).hint, const Arrow('e7', 'e5'));
    });

    testWidgets('disappears after its timeout with no move', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          hint: const Arrow('g1', 'f3'),
          hintTimeout: const Duration(seconds: 3),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(arrowsPainter(tester).hint, isNotNull);
      await tester.pump(const Duration(seconds: 1, milliseconds: 1));
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('a new hint restarts the timeout', (tester) async {
      final c = ChessBoardController();
      const timeout = Duration(seconds: 3);
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          hint: const Arrow('g1', 'f3'),
          hintTimeout: timeout,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(
        host(
          ChessBoard(
            controller: c,
            hint: const Arrow('b1', 'c3'),
            hintTimeout: timeout,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(arrowsPainter(tester).hint, const Arrow('b1', 'c3'));
      await tester.pump(const Duration(seconds: 1, milliseconds: 1));
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('a controller swap clears the hint', (tester) async {
      final c = ChessBoardController();
      const hint = Arrow('g1', 'f3');
      await pumpBoard(tester, ChessBoard(controller: c, hint: hint));
      await tester.pumpWidget(
        host(ChessBoard(controller: ChessBoardController(), hint: hint)),
      );
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('selecting a piece keeps the hint', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, hint: const Arrow('g1', 'f3')),
      );
      await tapSquare(tester, Square.g1);
      expect(arrowsPainter(tester).hint, isNotNull);
    });

    for (final (name, change) in [
      ('undo', (ChessBoardController c) => c.undo()),
      ('back', (ChessBoardController c) => c.back()),
      ('reset', (ChessBoardController c) => c.reset()),
      (
        'loadFen',
        (ChessBoardController c) => c.loadFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1'),
      ),
    ]) {
      testWidgets('$name retires the hint, which no longer fits', (
        tester,
      ) async {
        final c = ChessBoardController()..moveSan('e4');
        await pumpBoard(
          tester,
          ChessBoard(controller: c, hint: const Arrow('e7', 'e5')),
        );
        change(c);
        await tester.pump();
        expect(arrowsPainter(tester).hint, isNull);
      });
    }

    testWidgets('a silent move batched with a later change retires it', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, hint: const Arrow('g1', 'f3')),
      );
      c.move(Square.e2, Square.e4, notify: false);
      c.back();
      await tester.pump();
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('setting a timeout on a showing hint starts it', (
      tester,
    ) async {
      final c = ChessBoardController();
      const hint = Arrow('g1', 'f3');
      await pumpBoard(tester, ChessBoard(controller: c, hint: hint));
      await tester.pumpWidget(
        host(
          ChessBoard(
            controller: c,
            hint: hint,
            hintTimeout: const Duration(seconds: 1),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1, milliseconds: 1));
      expect(arrowsPainter(tester).hint, isNull);
    });

    testWidgets('removing the timeout keeps the hint up', (tester) async {
      final c = ChessBoardController();
      const hint = Arrow('g1', 'f3');
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          hint: hint,
          hintTimeout: const Duration(seconds: 1),
        ),
      );
      await tester.pumpWidget(host(ChessBoard(controller: c, hint: hint)));
      await tester.pump(const Duration(seconds: 2));
      expect(arrowsPainter(tester).hint, hint);
    });
  });
}
