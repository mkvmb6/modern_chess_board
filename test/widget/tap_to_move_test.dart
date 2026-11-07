import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/chess_board.dart'
    show BoardStateDebug, debugBoardBuildCount;
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

/// Global center of [square] on the board under test.
Offset centerOf(WidgetTester tester, Square square) {
  final painter =
      tester
              .widget<CustomPaint>(
                find.byWidgetPredicate(
                  (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
                ),
              )
              .painter!
          as BoardSquaresPainter;
  return tester.getTopLeft(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
        ),
      ) +
      painter.geometry.squareCenter(square);
}

Future<void> tapSquare(WidgetTester tester, Square square) async {
  await tester.tapAt(centerOf(tester, square));
  await tester.pump();
}

Square? selected(WidgetTester tester) =>
    (tester.state(find.byType(ChessBoard)) as BoardStateDebug).debugSelection;

void main() {
  testWidgets('tap a piece, then a destination, to move', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.g1);
    expect(selected(tester), Square.g1);
    await tapSquare(tester, Square.f3);
    expect(c.pieceAt(Square.f3), Piece.whiteKnight);
    expect(selected(tester), isNull);
    expect(c.lastChange, isA<MoveApplied>());
    expect((c.lastChange as MoveApplied).source, MoveSource.user);
  });

  testWidgets('taps follow orientation', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(
      tester,
      ChessBoard(controller: c, orientation: BoardOrientation.black),
    );
    await tapSquare(tester, Square.e2);
    await tapSquare(tester, Square.e4);
    expect(c.pieceAt(Square.e4), Piece.whitePawn);
  });

  testWidgets('taps work in outside label mode', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(
      tester,
      ChessBoard(controller: c, coordinates: CoordinateMode.outside),
    );
    await tapSquare(tester, Square.d2);
    await tapSquare(tester, Square.d4);
    expect(c.pieceAt(Square.d4), Piece.whitePawn);
  });

  testWidgets('a tap in the label margin does nothing', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(
      tester,
      ChessBoard(controller: c, coordinates: CoordinateMode.outside),
    );
    await tapSquare(tester, Square.e2);
    await tester.tapAt(
      tester.getBottomLeft(find.byType(ChessBoard)) + const Offset(2, -2),
    );
    await tester.pump();
    expect(selected(tester), Square.e2, reason: 'margin taps are ignored');
  });

  testWidgets('tapping an empty square with nothing selected does not '
      'rebuild the board', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final before = debugBoardBuildCount;
    for (final square in [Square.e4, Square.d5]) {
      final gesture = await tester.startGesture(centerOf(tester, square));
      await gesture.up();
      // Nothing changed, so no frame is even scheduled: nothing anywhere
      // rebuilds or repaints, not just the board's own build.
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    await tester.pump();
    expect(debugBoardBuildCount, before);
    expect(selected(tester), isNull);
  });

  testWidgets('pressing a piece selects it before the finger lifts', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final gesture = await tester.startGesture(centerOf(tester, Square.e2));
    await tester.pump();
    expect(selected(tester), Square.e2);
    await gesture.up();
    await tester.pump();
    expect(selected(tester), Square.e2);
  });

  testWidgets('pressing a legal destination moves before the finger lifts', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e2);
    final gesture = await tester.startGesture(centerOf(tester, Square.e4));
    await tester.pump();
    expect(c.pieceAt(Square.e4), Piece.whitePawn);
    await gesture.up();
  });

  testWidgets('tapping the selected piece deselects it on release', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e2);
    final gesture = await tester.startGesture(centerOf(tester, Square.e2));
    await tester.pump();
    expect(selected(tester), Square.e2, reason: 'still selected while held');
    await gesture.up();
    await tester.pump();
    expect(selected(tester), isNull);
  });

  testWidgets('a press on the selected piece that slides and comes back '
      'keeps it selected', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e2);
    final start = centerOf(tester, Square.e2);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(start);
    await gesture.up();
    await tester.pump();
    expect(selected(tester), Square.e2, reason: 'a drag is not a tap');
    expect(c.fen, kInitialFen);
  });

  testWidgets('a cancelled press on the selected piece keeps it selected', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e2);
    final gesture = await tester.startGesture(centerOf(tester, Square.e2));
    await gesture.cancel();
    await tester.pump();
    expect(selected(tester), Square.e2);
  });

  testWidgets('a mouse click that jitters a few pixels still deselects', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e2);
    final gesture = await tester.startGesture(
      centerOf(tester, Square.e2),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(3, 2));
    await gesture.up();
    await tester.pump();
    expect(selected(tester), isNull);
  });

  testWidgets('a secondary mouse click does not select', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final gesture = await tester.startGesture(
      centerOf(tester, Square.e2),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pump();
    expect(selected(tester), isNull);
  });

  testWidgets('a second finger cancels the press but not the selection', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e2);
    // A pinch starting on the selected piece must not deselect it.
    final first = await tester.startGesture(centerOf(tester, Square.e2));
    final second = await tester.startGesture(
      centerOf(tester, Square.d2),
      pointer: 7,
    );
    await second.up();
    await first.up();
    await tester.pump();
    expect(selected(tester), Square.e2);
    expect(c.fen, kInitialFen, reason: 'the second finger moved nothing');
  });

  group('blocked moves', () {
    testWidgets('read-only boards ignore taps but code moves still work', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, readOnly: true));
      await tapSquare(tester, Square.e2);
      await tapSquare(tester, Square.e4);
      expect(c.fen, kInitialFen);
      expect(selected(tester), isNull);
      expect(c.move(Square.e2, Square.e4), isTrue);
      await tester.pump();
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
    });

    testWidgets('interactive side blocks the other color', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, interactiveSide: InteractiveSide.black),
      );
      await tapSquare(tester, Square.e2);
      expect(selected(tester), isNull);
      // The app plays white's move; then the user can move black.
      c.move(Square.e2, Square.e4);
      await tester.pump();
      await tapSquare(tester, Square.e7);
      await tapSquare(tester, Square.e5);
      expect(c.pieceAt(Square.e5), Piece.blackPawn);
    });

    testWidgets('game over blocks taps', (tester) async {
      final c = ChessBoardController();
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        c.moveSan(san);
      }
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a2);
      expect(selected(tester), isNull);
    });

    testWidgets('viewing history blocks taps until back at the end', (
      tester,
    ) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5')
        ..back();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.d7);
      expect(selected(tester), isNull);
      c.goToEnd();
      await tester.pump();
      await tapSquare(tester, Square.g1);
      expect(selected(tester), Square.g1);
    });

    testWidgets('turning on read-only drops the selection', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.e2);
      expect(selected(tester), Square.e2);
      await tester.pumpWidget(host(ChessBoard(controller: c, readOnly: true)));
      expect(selected(tester), isNull);
    });
  });

  group('selection lifecycle', () {
    testWidgets('a move made by code clears the selection', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.e2);
      c.move(Square.d2, Square.d4);
      await tester.pump();
      expect(selected(tester), isNull);
    });

    testWidgets('a controller swap clears the selection', (tester) async {
      final a = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: a));
      await tapSquare(tester, Square.e2);
      expect(selected(tester), Square.e2);
      await tester.pumpWidget(
        host(ChessBoard(controller: ChessBoardController())),
      );
      expect(selected(tester), isNull);
    });
  });
}
