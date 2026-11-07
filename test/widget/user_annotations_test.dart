import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

BoardArrowsPainter arrowsPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is BoardArrowsPainter,
              ),
            )
            .painter!
        as BoardArrowsPainter;

/// Right-click drags from [from] to [to] with the mouse.
Future<void> rightDrag(WidgetTester tester, Square from, Square to) async {
  final g = await tester.startGesture(
    centerOf(tester, from),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  if (from != to) {
    await g.moveTo(centerOf(tester, to));
    await tester.pump();
  }
  await g.up();
  await tester.pump();
}

/// Long-presses [from] with a finger, then drags to [to].
Future<void> longPressDrag(WidgetTester tester, Square from, Square to) async {
  final g = await tester.startGesture(centerOf(tester, from));
  await tester.pump(const Duration(milliseconds: 450));
  if (from != to) {
    await g.moveTo(centerOf(tester, to));
    await tester.pump();
  }
  await g.up();
  await tester.pump();
}

const _theme = ChessBoardTheme.green;

void main() {
  group('drawing arrows', () {
    testWidgets('right-drag draws an arrow and reports it', (tester) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: (a) => reported = a),
      );
      await rightDrag(tester, Square.e2, Square.e4);
      final arrow = Arrow('e2', 'e4', color: _theme.annotationColors.plain);
      expect(reported, [arrow]);
      expect(arrowsPainter(tester).userArrows, [arrow]);
      // The board position is untouched.
      expect(c.pieceAt(Square.e2), Piece.whitePawn);
    });

    testWidgets('drawing the same arrow again removes it', (tester) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: (a) => reported = a),
      );
      await rightDrag(tester, Square.e2, Square.e4);
      await rightDrag(tester, Square.e2, Square.e4);
      expect(reported, isEmpty);
      expect(arrowsPainter(tester).userArrows, isEmpty);
    });

    testWidgets('a different color replaces an arrow on the same squares', (
      tester,
    ) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: (a) => reported = a),
      );
      await rightDrag(tester, Square.e2, Square.e4);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await rightDrag(tester, Square.e2, Square.e4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(reported, [
        Arrow('e2', 'e4', color: _theme.annotationColors.shift),
      ]);
    });

    testWidgets('a preview follows the pointer while drawing', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final g = await tester.startGesture(
        centerOf(tester, Square.g1),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await g.moveTo(centerOf(tester, Square.f3));
      await tester.pump();
      expect(arrowsPainter(tester).preview?.from, 'g1');
      expect(arrowsPainter(tester).preview?.to, 'f3');
      await g.up();
      await tester.pump();
      expect(arrowsPainter(tester).preview, isNull);
    });

    testWidgets('releasing off the board draws nothing', (tester) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: (a) => reported = a),
      );
      final g = await tester.startGesture(
        centerOf(tester, Square.e2),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.moveTo(const Offset(5, 5));
      await g.up();
      await tester.pump();
      expect(reported, isNull);
    });
  });

  group('modifier colors', () {
    for (final (keys, pick) in [
      (<LogicalKeyboardKey>[], (AnnotationColors a) => a.plain),
      ([LogicalKeyboardKey.shiftLeft], (AnnotationColors a) => a.shift),
      ([LogicalKeyboardKey.altLeft], (AnnotationColors a) => a.alt),
      (
        [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.altLeft],
        (AnnotationColors a) => a.shiftAlt,
      ),
    ]) {
      testWidgets('${keys.map((k) => k.keyLabel).join('+')} picks its color', (
        tester,
      ) async {
        final c = ChessBoardController();
        List<Arrow>? reported;
        await pumpBoard(
          tester,
          ChessBoard(controller: c, onUserArrowsChanged: (a) => reported = a),
        );
        for (final k in keys) {
          await tester.sendKeyDownEvent(k);
        }
        await rightDrag(tester, Square.d2, Square.d4);
        for (final k in keys) {
          await tester.sendKeyUpEvent(k);
        }
        expect(reported!.single.color, pick(_theme.annotationColors));
      });
    }
  });

  group('circles', () {
    testWidgets('right-click toggles a circle', (tester) async {
      final c = ChessBoardController();
      List<SquareMark>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserMarksChanged: (m) => reported = m),
      );
      await rightDrag(tester, Square.e4, Square.e4);
      final mark = SquareMark('e4', color: _theme.annotationColors.plain);
      expect(reported, [mark]);
      expect(arrowsPainter(tester).userMarks, [mark]);
      await rightDrag(tester, Square.e4, Square.e4);
      expect(reported, isEmpty);
    });
  });

  group('touch', () {
    testWidgets('long press then drag draws an arrow', (tester) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: (a) => reported = a),
      );
      await longPressDrag(tester, Square.e2, Square.e5);
      expect(reported, [
        Arrow('e2', 'e5', color: _theme.annotationColors.plain),
      ]);
      // The long press didn't move or keep selecting the pawn.
      expect(c.pieceAt(Square.e2), Piece.whitePawn);
      expect(c.pieceAt(Square.e5), isNull);
    });

    testWidgets('long press without moving circles the square', (tester) async {
      final c = ChessBoardController();
      List<SquareMark>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserMarksChanged: (m) => reported = m),
      );
      await longPressDrag(tester, Square.d5, Square.d5);
      expect(reported, [
        SquareMark('d5', color: _theme.annotationColors.plain),
      ]);
    });

    testWidgets('a quick drag still moves the piece', (tester) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: (a) => reported = a),
      );
      final g = await tester.startGesture(centerOf(tester, Square.e2));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(centerOf(tester, Square.e4));
      await tester.pump(const Duration(milliseconds: 500));
      await g.up();
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
      expect(reported, isNull);
    });
  });

  group('lifecycle', () {
    testWidgets('a move clears user drawings', (tester) async {
      final c = ChessBoardController();
      List<Arrow>? arrows;
      List<SquareMark>? marks;
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          onUserArrowsChanged: (a) => arrows = a,
          onUserMarksChanged: (m) => marks = m,
        ),
      );
      await rightDrag(tester, Square.e2, Square.e4);
      await rightDrag(tester, Square.d4, Square.d4);
      c.move(Square.e2, Square.e4);
      await tester.pump();
      expect(arrows, isEmpty);
      expect(marks, isEmpty);
      expect(arrowsPainter(tester).userArrows, isEmpty);
      expect(arrowsPainter(tester).userMarks, isEmpty);
    });

    testWidgets('drawings stay after a move when opted out', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, clearUserAnnotationsOnMove: false),
      );
      await rightDrag(tester, Square.e2, Square.e4);
      c.move(Square.e2, Square.e4);
      await tester.pump();
      expect(arrowsPainter(tester).userArrows, hasLength(1));
    });

    for (final (name, change) in [
      ('undo', (ChessBoardController c) => c.undo()),
      ('back', (ChessBoardController c) => c.back()),
      (
        'loadFen',
        (ChessBoardController c) => c.loadFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1'),
      ),
    ]) {
      testWidgets('$name clears drawings, which no longer fit', (tester) async {
        final c = ChessBoardController()..moveSan('e4');
        await pumpBoard(tester, ChessBoard(controller: c));
        await rightDrag(tester, Square.d2, Square.d4);
        change(c);
        await tester.pumpAndSettle();
        expect(arrowsPainter(tester).userArrows, isEmpty);
      });
    }

    testWidgets('a position change mid-draw keeps the arrow being drawn', (
      tester,
    ) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: (a) => reported = a),
      );
      final g = await tester.startGesture(
        centerOf(tester, Square.d2),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.moveTo(centerOf(tester, Square.d4));
      await tester.pump();
      c.move(Square.e2, Square.e4);
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(reported, [
        Arrow('d2', 'd4', color: _theme.annotationColors.plain),
      ]);
    });

    testWidgets('the preview follows a modifier pressed mid-drag', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final g = await tester.startGesture(
        centerOf(tester, Square.d2),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.moveTo(centerOf(tester, Square.d3));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await g.moveTo(centerOf(tester, Square.d4));
      await tester.pump();
      expect(
        arrowsPainter(tester).preview?.color,
        _theme.annotationColors.shift,
      );
      await g.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets('callbacks may setState when a swap or disable clears', (
      tester,
    ) async {
      final c = ChessBoardController();
      await tester.pumpWidget(MaterialApp(home: _DrawingHost(controller: c)));
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => PieceSet.standard.precache(context));
      await tester.pump();
      await rightDrag(tester, Square.e2, Square.e4);
      final host = tester.state<_DrawingHostState>(find.byType(_DrawingHost));
      expect(host.arrows, hasLength(1));
      host.update(() => host.enabled = false);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(host.arrows, isEmpty);
      host.update(() => host.enabled = true);
      await tester.pump();
      await rightDrag(tester, Square.e2, Square.e4);
      host.update(() => host.controller = ChessBoardController());
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(host.arrows, isEmpty);
    });

    testWidgets('disabled: right-click and long press draw nothing', (
      tester,
    ) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          enableUserAnnotations: false,
          onUserArrowsChanged: (a) => reported = a,
        ),
      );
      await rightDrag(tester, Square.e2, Square.e4);
      await longPressDrag(tester, Square.d7, Square.d5);
      expect(reported, isNull);
      expect(arrowsPainter(tester).userArrows, isEmpty);
    });

    testWidgets('turning drawing off clears what was drawn', (tester) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      void changed(List<Arrow> a) => reported = a;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: changed),
      );
      await rightDrag(tester, Square.e2, Square.e4);
      await tester.pumpWidget(
        host(
          ChessBoard(
            controller: c,
            enableUserAnnotations: false,
            onUserArrowsChanged: changed,
          ),
        ),
      );
      await tester.pump();
      expect(reported, isEmpty);
      expect(arrowsPainter(tester).userArrows, isEmpty);
    });

    testWidgets('a controller swap clears user drawings', (tester) async {
      final c = ChessBoardController();
      List<Arrow>? reported;
      void changed(List<Arrow> a) => reported = a;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserArrowsChanged: changed),
      );
      await rightDrag(tester, Square.e2, Square.e4);
      await tester.pumpWidget(
        host(
          ChessBoard(
            controller: ChessBoardController(),
            onUserArrowsChanged: changed,
          ),
        ),
      );
      await tester.pump();
      expect(reported, isEmpty);
      expect(arrowsPainter(tester).userArrows, isEmpty);
    });

    testWidgets('user drawings never change the app lists', (tester) async {
      final c = ChessBoardController();
      const appArrows = [Arrow('a2', 'a4')];
      await pumpBoard(tester, ChessBoard(controller: c, arrows: appArrows));
      await rightDrag(tester, Square.e2, Square.e4);
      expect(arrowsPainter(tester).arrows, appArrows);
      expect(arrowsPainter(tester).userArrows, hasLength(1));
    });

    testWidgets('holding a tap-to-move press does not draw', (tester) async {
      final c = ChessBoardController();
      List<SquareMark>? reported;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserMarksChanged: (m) => reported = m),
      );
      await tester.tapAt(centerOf(tester, Square.e2));
      await tester.pump();
      await longPressDrag(tester, Square.e4, Square.e4);
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
      expect(reported, isNull);
      expect(arrowsPainter(tester).userMarks, isEmpty);
    });

    testWidgets('turning drawing off mid-press stops the long press', (
      tester,
    ) async {
      final c = ChessBoardController();
      List<SquareMark>? reported;
      void changed(List<SquareMark> m) => reported = m;
      await pumpBoard(
        tester,
        ChessBoard(controller: c, onUserMarksChanged: changed),
      );
      final g = await tester.startGesture(centerOf(tester, Square.d5));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(
        host(
          ChessBoard(
            controller: c,
            enableUserAnnotations: false,
            onUserMarksChanged: changed,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await tester.pump();
      expect(reported, isNull);
    });

    testWidgets('a long-press drawing inside a scroll view does not scroll', (
      tester,
    ) async {
      final c = ChessBoardController();
      final scroll = ScrollController();
      final board = ChessBoard(controller: c);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ListView(
              controller: scroll,
              children: [
                SizedBox.square(dimension: 400, child: board),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => board.pieceSet.precache(context));
      await tester.pump();
      // An empty square: the board doesn't claim the press up front.
      final g = await tester.startGesture(centerOf(tester, Square.d5));
      await tester.pump(const Duration(milliseconds: 450));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      await g.up();
      await tester.pump();
      expect(scroll.offset, 0);
      expect(arrowsPainter(tester).userArrows, hasLength(1));
    });

    testWidgets('a quick swipe on an empty square still scrolls', (
      tester,
    ) async {
      final c = ChessBoardController();
      final scroll = ScrollController();
      final board = ChessBoard(controller: c);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ListView(
              controller: scroll,
              children: [
                SizedBox.square(dimension: 400, child: board),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.dragFrom(centerOf(tester, Square.d5), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
    });

    testWidgets('right-click cancels a selection', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tester.tapAt(centerOf(tester, Square.e2));
      await tester.pump();
      await rightDrag(tester, Square.e4, Square.e4);
      // e4 is no longer a pending destination: tapping it does nothing.
      await tester.tapAt(centerOf(tester, Square.e4));
      await tester.pump();
      expect(c.pieceAt(Square.e2), Piece.whitePawn);
    });
  });
}

/// An app that keeps the user's arrows in its own state, as apps do.
class _DrawingHost extends StatefulWidget {
  const _DrawingHost({required this.controller});

  final ChessBoardController controller;

  @override
  State<_DrawingHost> createState() => _DrawingHostState();
}

class _DrawingHostState extends State<_DrawingHost> {
  late ChessBoardController controller = widget.controller;
  bool enabled = true;
  List<Arrow> arrows = const [];

  /// Rebuilds after [change], as an app would.
  void update(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext context) => Material(
    child: Center(
      child: SizedBox.square(
        dimension: 400,
        child: ChessBoard(
          controller: controller,
          enableUserAnnotations: enabled,
          onUserArrowsChanged: (a) => setState(() => arrows = a),
        ),
      ),
    ),
  );
}
