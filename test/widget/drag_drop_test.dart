import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/chess_board.dart'
    show BoardStateDebug;
import 'package:modern_chess_board/src/widget/interaction/drag_layer.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

Widget host(ChessBoard board, {double side = 400}) => MaterialApp(
  home: Material(
    child: Center(
      child: SizedBox.square(dimension: side, child: board),
    ),
  ),
);

Future<void> pumpBoard(
  WidgetTester tester,
  ChessBoard board, {
  double side = 400,
}) async {
  await tester.pumpWidget(host(board, side: side));
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => board.pieceSet.precache(context));
  await tester.pump();
}

BoardSquaresPainter squaresPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
              ),
            )
            .painter!
        as BoardSquaresPainter;

Offset centerOf(WidgetTester tester, Square square) =>
    tester.getTopLeft(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
      ),
    ) +
    squaresPainter(tester).geometry.squareCenter(square);

double squareSize(WidgetTester tester) =>
    squaresPainter(tester).geometry.squareSize;

BoardStateDebug state(WidgetTester tester) =>
    tester.state(find.byType(ChessBoard)) as BoardStateDebug;

/// Drags from [from] to [to] in small steps, like a real finger.
Future<TestGesture> dragTo(
  WidgetTester tester,
  Square from,
  Square to, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
  bool release = true,
}) async {
  final start = centerOf(tester, from);
  final end = centerOf(tester, to);
  final gesture = await tester.startGesture(start, kind: kind);
  await tester.pump();
  for (var i = 1; i <= 6; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / 6)!);
    await tester.pump();
  }
  if (release) {
    await gesture.up();
    await tester.pump();
  }
  return gesture;
}

/// The piece views on the board itself, not the floating drag piece.
Iterable<ChessPieceView> boardPieces(WidgetTester tester) => tester
    .widgetList<ChessPieceView>(find.byType(ChessPieceView))
    .where((v) => !_isFloating(tester, v));

bool _isFloating(WidgetTester tester, ChessPieceView view) => find
    .ancestor(of: find.byWidget(view), matching: find.byType(DragLayer))
    .evaluate()
    .isNotEmpty;

Finder floatingPiece() => find.descendant(
  of: find.byType(DragLayer),
  matching: find.byType(ChessPieceView),
);

void main() {
  group('legal and illegal drops', () {
    testWidgets('dragging a piece to a legal square moves it', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.g1, Square.f3);
      expect(c.pieceAt(Square.f3), Piece.whiteKnight);
      expect((c.lastChange as MoveApplied).source, MoveSource.user);
      expect(state(tester).debugSelection, isNull);
      expect(floatingPiece(), findsNothing);
    });

    testWidgets('an illegal drop snaps back and changes nothing', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.g1, Square.g3);
      expect(c.fen, kInitialFen);
      expect(floatingPiece(), findsNothing);
      expect(boardPieces(tester), hasLength(32));
    });

    testWidgets('dropping off the board snaps back', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final start = centerOf(tester, Square.e2);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 40));
      await gesture.moveTo(
        tester.getBottomRight(find.byType(ChessBoard)) + const Offset(30, 30),
      );
      await gesture.up();
      await tester.pump();
      expect(c.fen, kInitialFen);
      expect(floatingPiece(), findsNothing);
    });

    testWidgets('a cancelled drag snaps back', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await dragTo(
        tester,
        Square.e2,
        Square.e4,
        release: false,
      );
      expect(floatingPiece(), findsOneWidget);
      await gesture.cancel();
      await tester.pump();
      expect(c.fen, kInitialFen);
      expect(floatingPiece(), findsNothing);
    });

    testWidgets('dropping back on the source square keeps it selected', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final start = centerOf(tester, Square.e2);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveTo(start);
      await gesture.up();
      await tester.pump();
      expect(c.fen, kInitialFen);
      expect(state(tester).debugSelection, Square.e2);
    });

    testWidgets('drags follow orientation', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, orientation: BoardOrientation.black),
      );
      await dragTo(tester, Square.d2, Square.d4);
      expect(c.pieceAt(Square.d4), Piece.whitePawn);
    });

    testWidgets('a drag move is not animated: the piece lands at once', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.e2, Square.e4);
      final pawn = boardPieces(tester).where((v) {
        final r = tester.getRect(find.byWidget(v));
        return r.contains(centerOf(tester, Square.e4));
      });
      expect(pawn, hasLength(1));
    });
  });

  group('tap and drag together', () {
    testWidgets('a movement below the threshold counts as a tap', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await tester.startGesture(centerOf(tester, Square.e2));
      await gesture.moveBy(const Offset(4, 3));
      await gesture.up();
      await tester.pump();
      expect(state(tester).debugSelection, Square.e2);
      expect(floatingPiece(), findsNothing);
    });

    testWidgets('dragging a piece replaces the tap selection', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final tap = await tester.startGesture(centerOf(tester, Square.g1));
      await tap.up();
      await tester.pump();
      expect(state(tester).debugSelection, Square.g1);
      await dragTo(tester, Square.d2, Square.d4);
      expect(c.pieceAt(Square.d4), Piece.whitePawn);
      expect(c.pieceAt(Square.g1), Piece.whiteKnight, reason: 'g1 unmoved');
    });

    testWidgets('dragging an empty square does nothing', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.e4, Square.e5);
      expect(floatingPiece(), findsNothing);
      expect(c.fen, kInitialFen);
    });

    testWidgets('pieces the user cannot move do not drag', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.e7, Square.e5, release: false);
      expect(floatingPiece(), findsNothing);
    });

    testWidgets('read-only boards do not drag', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, readOnly: true));
      await dragTo(tester, Square.e2, Square.e4, release: false);
      expect(floatingPiece(), findsNothing);
      expect(c.fen, kInitialFen);
    });

    testWidgets('pressing a destination then sliding does not drag the '
        'moved piece', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final tap = await tester.startGesture(centerOf(tester, Square.e2));
      await tap.up();
      await tester.pump();
      // The press on e4 makes the move; sliding afterwards must not pick
      // the pawn up again or affect anything.
      await dragTo(tester, Square.e4, Square.e6);
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
      expect(c.history, hasLength(1));
    });
  });

  group('while dragging', () {
    testWidgets('the source square is empty and a floating piece follows', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await dragTo(
        tester,
        Square.g1,
        Square.f3,
        release: false,
      );
      expect(floatingPiece(), findsOneWidget);
      expect(boardPieces(tester), hasLength(31));
      final onG1 = boardPieces(tester).where((v) {
        return tester
            .getRect(find.byWidget(v))
            .contains(centerOf(tester, Square.g1));
      });
      expect(onG1, isEmpty);
      await gesture.up();
    });

    testWidgets('on touch, the piece floats above the finger', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await dragTo(
        tester,
        Square.e2,
        Square.e4,
        release: false,
      );
      final finger = centerOf(tester, Square.e4);
      final piece = tester.getRect(floatingPiece());
      expect(piece.center.dx, closeTo(finger.dx, 0.5));
      // Half a square up: visible past the fingertip, lower edge still on
      // the square under the finger.
      expect(
        piece.center.dy,
        closeTo(finger.dy - squareSize(tester) * 0.5, 0.5),
      );
      expect(piece.bottom, greaterThan(finger.dy - squareSize(tester) / 2));
      await gesture.up();
    });

    testWidgets('with a stylus, the piece is centered on the pointer', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await dragTo(
        tester,
        Square.e2,
        Square.e4,
        kind: PointerDeviceKind.stylus,
        release: false,
      );
      expect(
        tester.getRect(floatingPiece()).center,
        offsetMoreOrLessEquals(centerOf(tester, Square.e4), epsilon: 0.5),
      );
      await gesture.up();
    });

    testWidgets('a second finger mid-drag cancels the drag', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final first = await dragTo(tester, Square.e2, Square.e4, release: false);
      final second = await tester.startGesture(
        centerOf(tester, Square.h4),
        pointer: 9,
      );
      await tester.pump();
      expect(floatingPiece(), findsNothing);
      await second.up();
      await first.up();
      await tester.pump();
      expect(c.fen, kInitialFen);
    });

    testWidgets('dragging off the board and back in still drops', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final start = centerOf(tester, Square.g1);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveTo(start + const Offset(0, 300));
      await tester.pump();
      expect(floatingPiece(), findsOneWidget);
      await gesture.moveTo(centerOf(tester, Square.f3));
      await gesture.up();
      await tester.pump();
      expect(c.pieceAt(Square.f3), Piece.whiteKnight);
    });

    testWidgets('a flip mid-drag drops on the square under the finger in '
        'the new orientation', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final start = centerOf(tester, Square.e2);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await tester.pumpWidget(
        host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
      );
      // In black orientation, e2 sits where e7 was; move onto e4 there.
      await gesture.moveTo(centerOf(tester, Square.e4));
      await gesture.up();
      await tester.pump();
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
    });
  });

  group('drag edge cases', () {
    testWidgets('a mouse move of 5px is a click, 7px starts a drag', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      var gesture = await tester.startGesture(
        centerOf(tester, Square.e2),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump();
      expect(floatingPiece(), findsNothing);
      await gesture.up();
      await tester.pump();

      gesture = await tester.startGesture(
        centerOf(tester, Square.d2),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(7, 0));
      await tester.pump();
      expect(floatingPiece(), findsOneWidget);
      await gesture.up();
    });

    testWidgets('a capture by drag', (tester) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('d5');
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.e4, Square.d5);
      expect(c.lastMove!.isCapture, isTrue);
      expect(c.pieceAt(Square.d5), Piece.whitePawn);
    });

    testWidgets('castling by dragging the king two squares', (tester) async {
      final c = ChessBoardController(
        fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
      );
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.e1, Square.g1);
      expect(c.lastMove!.castle, CastleSide.kingside);
      expect(c.pieceAt(Square.f1), Piece.whiteRook);
    });

    testWidgets('no drag while viewing history or after game over', (
      tester,
    ) async {
      final history = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5')
        ..back();
      await pumpBoard(tester, ChessBoard(controller: history));
      await dragTo(tester, Square.d7, Square.d5, release: false);
      expect(floatingPiece(), findsNothing);

      final over = ChessBoardController();
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        over.moveSan(san);
      }
      await tester.pumpWidget(host(ChessBoard(controller: over)));
      await tester.pump();
      await dragTo(tester, Square.a2, Square.a3, release: false);
      expect(floatingPiece(), findsNothing);
    });

    testWidgets('a PageView swipe is blocked on a piece but works elsewhere', (
      tester,
    ) async {
      final c = ChessBoardController();
      final pages = PageController();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: PageView(
              controller: pages,
              children: [
                Center(
                  child: SizedBox.square(
                    dimension: 400,
                    child: ChessBoard(controller: c),
                  ),
                ),
                const Center(child: Text('page 2')),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => PieceSet.standard.precache(context));
      await tester.pump();

      // A horizontal drag starting on a movable piece drags the piece.
      await dragTo(tester, Square.b1, Square.c3);
      await tester.pumpAndSettle();
      expect(pages.page, 0);
      expect(c.pieceAt(Square.c3), Piece.whiteKnight);

      // From an empty square, the swipe turns the page.
      await tester.flingFrom(
        centerOf(tester, Square.d4),
        const Offset(-300, 0),
        2000,
      );
      await tester.pumpAndSettle();
      expect(pages.page, 1);
    });

    testWidgets('an ancestor onTap does not fire for presses on a piece', (
      tester,
    ) async {
      final c = ChessBoardController();
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: GestureDetector(
              onTap: () => tapped++,
              child: Center(
                child: SizedBox.square(
                  dimension: 400,
                  child: ChessBoard(controller: c),
                ),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => PieceSet.standard.precache(context));
      await tester.pump();
      await tester.tapAt(centerOf(tester, Square.e2));
      await tester.pump();
      expect(tapped, 0, reason: 'the board claims presses on movable pieces');
      await tester.tapAt(centerOf(tester, Square.e5));
      await tester.pump();
      expect(tapped, 1, reason: 'other presses reach the ancestor');
    });

    testWidgets('with a mouse, the piece is centered on the pointer', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await dragTo(
        tester,
        Square.e2,
        Square.e4,
        kind: PointerDeviceKind.mouse,
        release: false,
      );
      final pointer = centerOf(tester, Square.e4);
      expect(
        tester.getRect(floatingPiece()).center,
        offsetMoreOrLessEquals(pointer, epsilon: 0.5),
      );
      await gesture.up();
    });

    for (final side in [120.0, 400.0, 900.0]) {
      testWidgets('the floating piece grows at most 4px and 15% at $side px', (
        tester,
      ) async {
        final c = ChessBoardController();
        await pumpBoard(tester, ChessBoard(controller: c), side: side);
        final gesture = await dragTo(
          tester,
          Square.e2,
          Square.e4,
          kind: PointerDeviceKind.mouse,
          release: false,
        );
        final square = squareSize(tester);
        final size = tester.getSize(floatingPiece()).width;
        expect(size, greaterThan(square), reason: 'it is lifted');
        expect(size, lessThanOrEqualTo(square * 1.15 + 1e-9));
        expect((size - square) / 2, lessThanOrEqualTo(4 + 1e-9));
        await gesture.up();
      });
    }

    testWidgets('a code move during a drag cancels the drag', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await dragTo(
        tester,
        Square.e2,
        Square.e4,
        release: false,
      );
      c.move(Square.d2, Square.d4);
      await tester.pump();
      expect(floatingPiece(), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(c.pieceAt(Square.e4), isNull, reason: 'the stale drop is ignored');
    });

    testWidgets('a controller swap cancels an in-progress drag', (
      tester,
    ) async {
      final a = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: a));
      final gesture = await dragTo(
        tester,
        Square.e2,
        Square.e4,
        release: false,
      );
      final b = ChessBoardController();
      await tester.pumpWidget(host(ChessBoard(controller: b)));
      expect(floatingPiece(), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(a.fen, kInitialFen);
      expect(b.fen, kInitialFen);
    });

    testWidgets('turning on read-only cancels an in-progress drag', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await dragTo(
        tester,
        Square.e2,
        Square.e4,
        release: false,
      );
      await tester.pumpWidget(host(ChessBoard(controller: c, readOnly: true)));
      expect(floatingPiece(), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(c.fen, kInitialFen);
    });
  });

  group('cursors', () {
    MouseCursor cursorAt(WidgetTester tester, Offset position) {
      final result = HitTestResult();
      tester.binding.hitTestInView(result, position, tester.view.viewId);
      for (final entry in result.path) {
        final target = entry.target;
        if (target is RenderMouseRegion) return target.cursor;
      }
      return MouseCursor.defer;
    }

    testWidgets('grab over movable pieces, basic elsewhere', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      Future<MouseCursor> hover(Square s) async {
        await mouse.moveTo(centerOf(tester, s));
        await tester.pump();
        return cursorAt(tester, centerOf(tester, s));
      }

      expect(await hover(Square.e2), SystemMouseCursors.grab);
      expect(await hover(Square.e7), isNot(SystemMouseCursors.grab));
      expect(await hover(Square.e4), isNot(SystemMouseCursors.grab));
      // After a move by code the cursor follows the new position without
      // the mouse moving: white's pieces are no longer grabbable.
      expect(await hover(Square.d2), SystemMouseCursors.grab);
      c.move(Square.e2, Square.e4);
      await tester.pump();
      expect(
        cursorAt(tester, centerOf(tester, Square.d2)),
        isNot(SystemMouseCursors.grab),
      );
    });

    testWidgets('grabbing while dragging', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final gesture = await dragTo(
        tester,
        Square.e2,
        Square.e4,
        kind: PointerDeviceKind.mouse,
        release: false,
      );
      expect(
        cursorAt(tester, centerOf(tester, Square.e4)),
        SystemMouseCursors.grabbing,
      );
      await gesture.up();
      await tester.pump();
      expect(
        cursorAt(tester, centerOf(tester, Square.e4)),
        isNot(SystemMouseCursors.grabbing),
      );
    });

    testWidgets('no grab cursor on a read-only board', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, readOnly: true));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(centerOf(tester, Square.e2));
      await tester.pump();
      expect(
        cursorAt(tester, centerOf(tester, Square.e2)),
        isNot(SystemMouseCursors.grab),
      );
    });
  });

  group('inside a scroll view', () {
    testWidgets('dragging a piece does not scroll the page', (tester) async {
      final c = ChessBoardController();
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ListView(
              controller: scroll,
              children: [
                SizedBox(height: 400, child: ChessBoard(controller: c)),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => PieceSet.standard.precache(context));
      await tester.pump();
      // Drag a pawn straight up two squares: a vertical gesture a scroll
      // view would normally take.
      await dragTo(tester, Square.e2, Square.e4);
      expect(scroll.offset, 0);
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
    });

    testWidgets('dragging an empty square still scrolls the page', (
      tester,
    ) async {
      final c = ChessBoardController();
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ListView(
              controller: scroll,
              children: [
                SizedBox(height: 400, child: ChessBoard(controller: c)),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => PieceSet.standard.precache(context));
      await tester.pump();
      await tester.dragFrom(centerOf(tester, Square.e4), const Offset(0, -150));
      await tester.pump();
      expect(scroll.offset, greaterThan(0));
    });
  });
}
