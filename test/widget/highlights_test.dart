import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/highlight_layer.dart';
import 'package:modern_chess_board/src/widget/layers/highlight_model.dart';
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

/// What the tint painter was given.
BoardHighlights tints(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is BoardTintsPainter,
                  ),
                )
                .painter!
            as BoardTintsPainter)
        .highlights;

/// What the marker painter was given.
BoardHighlights markers(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is BoardMarkersPainter,
                  ),
                )
                .painter!
            as BoardMarkersPainter)
        .highlights;

const _theme = ChessBoardTheme.green;

void main() {
  testWidgets('selecting a piece tints it and marks its moves', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    expect(tints(tester).tints, isEmpty);
    await tapSquare(tester, Square.g1);
    expect(tints(tester).tints, {Square.g1: _theme.selectionColor});
    expect(markers(tester).markers, {
      Square.f3: LegalMarker.dot,
      Square.h3: LegalMarker.dot,
    });
    // Deselecting clears both.
    await tapSquare(tester, Square.g1);
    expect(tints(tester).tints, isEmpty);
    expect(markers(tester).markers, isEmpty);
  });

  testWidgets('after a move, the last move is tinted and markers clear', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e2);
    await tapSquare(tester, Square.e4);
    expect(tints(tester).tints, {
      Square.e2: _theme.lastMoveColor,
      Square.e4: _theme.lastMoveColor,
    });
    expect(markers(tester).markers, isEmpty);
  });

  testWidgets('a code move updates the last-move tint', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    c.moveSan('d4');
    await tester.pump();
    expect(tints(tester).tints.keys.toSet(), {Square.d2, Square.d4});
  });

  testWidgets('showLastMove: false hides the last move', (tester) async {
    final c = ChessBoardController()..moveSan('e4');
    await pumpBoard(tester, ChessBoard(controller: c, showLastMove: false));
    expect(tints(tester).tints, isEmpty);
  });

  testWidgets('checkmate tints the mated king; shortcut color applies', (
    tester,
  ) async {
    final c = ChessBoardController();
    for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
      c.moveSan(san);
    }
    const mate = Color(0xFFD50000);
    await pumpBoard(
      tester,
      ChessBoard(controller: c, checkmateColor: mate, showLastMove: false),
    );
    expect(tints(tester).tints, {Square.e1: mate});
  });

  testWidgets('check is shown only when the theme sets a color', (
    tester,
  ) async {
    final c = ChessBoardController(fen: '4k3/8/8/8/8/8/8/R3K3 w - - 0 1')
      ..moveSan('Ra8+');
    await pumpBoard(tester, ChessBoard(controller: c, showLastMove: false));
    expect(tints(tester).tints, isEmpty);
    const red = Color(0x99E53935);
    await tester.pumpWidget(
      host(
        ChessBoard(
          controller: c,
          showLastMove: false,
          theme: _theme.copyWith(checkColor: red),
        ),
      ),
    );
    expect(tints(tester).tints, {Square.e8: red});
  });

  testWidgets('a selected king shows a ring on its castling rook', (
    tester,
  ) async {
    final c = ChessBoardController(
      fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
    );
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e1);
    expect(markers(tester).markers[Square.h1], LegalMarker.ring);
    expect(markers(tester).markers[Square.a1], LegalMarker.ring);
  });

  testWidgets('hovering a legal destination with a mouse tints it', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.g1);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(centerOf(tester, Square.f3));
    await tester.pump();
    expect(tints(tester).hover, Square.f3);
    await mouse.moveTo(centerOf(tester, Square.e4));
    await tester.pump();
    expect(tints(tester).hover, isNull, reason: 'not a legal destination');
  });

  testWidgets('highlight layers repaint without rebuilding the board', (
    tester,
  ) async {
    final c = ChessBoardController();
    await pumpBoard(tester, ChessBoard(controller: c));
    final squaresBefore = tester.widget<CustomPaint>(_squares()).painter;
    await tapSquare(tester, Square.g1);
    expect(
      identical(tester.widget<CustomPaint>(_squares()).painter, squaresBefore),
      isTrue,
      reason: 'selecting a piece does not touch the squares layer',
    );
  });

  testWidgets('highlights follow orientation', (tester) async {
    final c = ChessBoardController();
    await pumpBoard(
      tester,
      ChessBoard(controller: c, orientation: BoardOrientation.black),
    );
    await tapSquare(tester, Square.b1);
    expect(markers(tester).markers.keys.toSet(), {Square.a3, Square.c3});
  });

  testWidgets('read-only boards still show the last move', (tester) async {
    final c = ChessBoardController()..moveSan('e4');
    await pumpBoard(tester, ChessBoard(controller: c, readOnly: true));
    expect(tints(tester).tints.keys.toSet(), {Square.e2, Square.e4});
    await tapSquare(tester, Square.e7);
    expect(markers(tester).markers, isEmpty);
  });

  group('hover', () {
    testWidgets('no hover tint without a selection', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(centerOf(tester, Square.e4));
      await tester.pump();
      expect(tints(tester).hover, isNull);
    });

    testWidgets('the hover tint clears when the mouse leaves the board', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.g1);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(centerOf(tester, Square.f3));
      await tester.pump();
      expect(tints(tester).hover, Square.f3);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(tints(tester).hover, isNull);
    });

    testWidgets('flipping the board under a resting mouse updates hover '
        'without errors', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.g1);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      final at = centerOf(tester, Square.f3);
      await mouse.moveTo(at);
      await tester.pump();
      expect(tints(tester).hover, Square.f3);
      // After the flip the same screen point is over c6, not a legal
      // destination of the knight on g1.
      await tester.pumpWidget(
        host(ChessBoard(controller: c, orientation: BoardOrientation.black)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tints(tester).hover, isNull);
    });
  });

  testWidgets('legal markers paint above the pieces', (tester) async {
    final c = ChessBoardController()
      ..moveSan('e4')
      ..moveSan('d5');
    await pumpBoard(tester, ChessBoard(controller: c));
    await tapSquare(tester, Square.e4);
    final stack = find
        .ancestor(
          of: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is BoardMarkersPainter,
          ),
          matching: find.byType(Stack),
        )
        .first;
    final children = tester.widget<Stack>(stack).children;
    int indexOf(bool Function(Widget) test) => children.indexWhere(
      (child) => find
          .descendant(
            of: find.byWidget(child),
            matching: find.byWidgetPredicate(test),
          )
          .evaluate()
          .isNotEmpty,
    );
    final piecesAt = indexOf((w) => w is ChessPieceView);
    final markersAt = indexOf(
      (w) => w is CustomPaint && w.painter is BoardMarkersPainter,
    );
    expect(markersAt, greaterThan(piecesAt));
  });

  testWidgets('no tint on the pawn while its promotion is pending', (
    tester,
  ) async {
    final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
    await pumpBoard(tester, ChessBoard(controller: c, showLastMove: false));
    await tapSquare(tester, Square.a7);
    await tapSquare(tester, Square.a8);
    expect(tints(tester).tints, isEmpty);
    expect(markers(tester).markers, isEmpty);
  });
}
