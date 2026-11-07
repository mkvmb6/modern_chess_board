import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';
import 'package:modern_chess_board/src/widget/promotion/promotion_picker.dart';

/// White pawn on a7 ready to promote, black king out of the way.
const _whitePromo = '7k/P7/8/8/8/8/8/K7 w - - 0 1';

/// Black pawn on h2 ready to promote on h1.
const _blackPromo = 'k7/8/8/8/8/8/7p/K7 b - - 0 1';

/// A pawn that can promote by capturing on b8 as well as pushing to a8.
const _capturePromo = '1r5k/P7/8/8/8/8/8/K7 w - - 0 1';

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

BoardSquaresPainter squaresPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
              ),
            )
            .painter!
        as BoardSquaresPainter;

Offset boardOrigin(WidgetTester tester) => tester.getTopLeft(
  find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
  ),
);

Offset centerOf(WidgetTester tester, Square square) =>
    boardOrigin(tester) + squaresPainter(tester).geometry.squareCenter(square);

Future<void> tapSquare(WidgetTester tester, Square square) async {
  await tester.tapAt(centerOf(tester, square));
  // Let the picker finish appearing, so tests see its final layout.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> dragTo(WidgetTester tester, Square from, Square to) async {
  final start = centerOf(tester, from);
  final end = centerOf(tester, to);
  final gesture = await tester.startGesture(start);
  for (var i = 1; i <= 6; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / 6)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

Finder picker() => find.byType(PromotionPicker);

/// The choice button for [type] in the default picker.
Finder choice(PieceType type) => find.byKey(ValueKey('promotion-${type.name}'));

void main() {
  group('the picker appears', () {
    testWidgets('when a pawn is tapped onto the last rank', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      expect(picker(), findsOneWidget);
      expect(c.fen, _whitePromo, reason: 'nothing moves until a choice');
    });

    testWidgets('when a pawn is dragged onto the last rank', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.a7, Square.a8);
      expect(picker(), findsOneWidget);
      expect(c.fen, _whitePromo);
    });

    testWidgets('for a capture that promotes', (tester) async {
      final c = ChessBoardController(fen: _capturePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.b8);
      expect(picker(), findsOneWidget);
    });

    testWidgets('not for ordinary moves', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.e2);
      await tapSquare(tester, Square.e4);
      expect(picker(), findsNothing);
    });
  });

  group('choices', () {
    for (final type in [
      PieceType.queen,
      PieceType.rook,
      PieceType.bishop,
      PieceType.knight,
    ]) {
      testWidgets('choosing ${type.name} promotes to it', (tester) async {
        final c = ChessBoardController(fen: _whitePromo);
        await pumpBoard(tester, ChessBoard(controller: c));
        await tapSquare(tester, Square.a7);
        await tapSquare(tester, Square.a8);
        await tester.tap(choice(type));
        await tester.pump();
        expect(picker(), findsNothing);
        expect(c.pieceAt(Square.a8), Piece(PieceColor.white, type));
        expect(c.lastMove!.promotion, type);
        expect((c.lastChange as MoveApplied).source, MoveSource.user);
      });
    }

    testWidgets('the picker shows the promoting side in the board pieces', (
      tester,
    ) async {
      final c = ChessBoardController(fen: _blackPromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.h2);
      await tapSquare(tester, Square.h1);
      final pieces = tester
          .widgetList<ChessPieceView>(
            find.descendant(
              of: picker(),
              matching: find.byType(ChessPieceView),
            ),
          )
          .map((v) => v.piece)
          .toList();
      expect(pieces, [
        Piece.blackQueen,
        Piece.blackKnight,
        Piece.blackRook,
        Piece.blackBishop,
      ]);
    });
  });

  group('placement', () {
    // The four choices form a column starting on the promotion square and
    // running toward the board's center, so the queen sits where the pawn
    // lands.
    Future<List<Rect>> choiceRects(WidgetTester tester) async => [
      for (final t in [
        PieceType.queen,
        PieceType.knight,
        PieceType.rook,
        PieceType.bishop,
      ])
        tester.getRect(choice(t)).shift(-boardOrigin(tester)),
    ];

    testWidgets('white promoting on a8 with white at the bottom', (
      tester,
    ) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      final rects = await choiceRects(tester);
      final g = squaresPainter(tester).geometry;
      expect(
        rects[0].center,
        offsetMoreOrLessEquals(g.squareCenter(Square.a8), epsilon: 0.5),
      );
      expect(
        rects[1].center,
        offsetMoreOrLessEquals(g.squareCenter(Square.a7), epsilon: 0.5),
      );
      expect(
        rects[3].center,
        offsetMoreOrLessEquals(g.squareCenter(Square.a5), epsilon: 0.5),
      );
    });

    testWidgets('white promoting on a8 with black at the bottom', (
      tester,
    ) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(
        tester,
        ChessBoard(controller: c, orientation: BoardOrientation.black),
      );
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      final rects = await choiceRects(tester);
      final g = squaresPainter(tester).geometry;
      // a8 is at the bottom right; the column runs upward from it.
      expect(
        rects[0].center,
        offsetMoreOrLessEquals(g.squareCenter(Square.a8), epsilon: 0.5),
      );
      expect(
        rects[3].center,
        offsetMoreOrLessEquals(g.squareCenter(Square.a5), epsilon: 0.5),
      );
      expect(rects[3].top, lessThan(rects[0].top));
    });

    testWidgets('black promoting on h1', (tester) async {
      final c = ChessBoardController(fen: _blackPromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.h2);
      await tapSquare(tester, Square.h1);
      final rects = await choiceRects(tester);
      final g = squaresPainter(tester).geometry;
      expect(
        rects[0].center,
        offsetMoreOrLessEquals(g.squareCenter(Square.h1), epsilon: 0.5),
      );
      expect(
        rects[3].center,
        offsetMoreOrLessEquals(g.squareCenter(Square.h4), epsilon: 0.5),
      );
    });

    testWidgets('the pawn is hidden from its square while choosing', (
      tester,
    ) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      // a7 is empty on the board while the pawn waits on a8 under the
      // picker, like a real move in progress.
      final onBoard = tester
          .widgetList<ChessPieceView>(find.byType(ChessPieceView))
          .where(
            (v) => find
                .ancestor(of: find.byWidget(v), matching: picker())
                .evaluate()
                .isEmpty,
          )
          .toList();
      final pawnRects = onBoard
          .where((v) => v.piece == Piece.whitePawn)
          .map(
            (v) => tester.getRect(find.byWidget(v)).shift(-boardOrigin(tester)),
          )
          .toList();
      final g = squaresPainter(tester).geometry;
      expect(pawnRects, isEmpty, reason: 'hidden while the picker covers a8');
      expect(
        onBoard.where(
          (v) => g
              .squareRect(Square.a7)
              .contains(
                tester.getCenter(find.byWidget(v)) - boardOrigin(tester),
              ),
        ),
        isEmpty,
      );
    });
  });

  group('cancelling', () {
    testWidgets('tapping outside the picker cancels', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tapSquare(tester, Square.e4);
      expect(picker(), findsNothing);
      expect(c.fen, _whitePromo);
    });

    testWidgets('Escape cancels', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(picker(), findsNothing);
      expect(c.fen, _whitePromo);
    });

    testWidgets('Back cancels instead of leaving the page', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await tester.pumpWidget(
        MaterialApp(
          home: const Material(child: Text('home')),
          routes: {
            '/board': (_) => Material(
              child: Center(
                child: SizedBox.square(
                  dimension: 400,
                  child: ChessBoard(controller: c),
                ),
              ),
            ),
          },
        ),
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/board');
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => PieceSet.standard.precache(context));
      await tester.pump();
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      expect(picker(), findsOneWidget);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(picker(), findsNothing);
      expect(find.byType(ChessBoard), findsOneWidget, reason: 'still on page');
      expect(c.fen, _whitePromo);

      // With no picker open, Back leaves the page as usual.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChessBoard), findsNothing);
    });

    testWidgets('a code move closes the picker', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      c.move(Square.a1, Square.b1);
      await tester.pump();
      expect(picker(), findsNothing);
    });

    testWidgets('a controller swap closes a pending picker', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tester.pumpWidget(
        host(ChessBoard(controller: ChessBoardController())),
      );
      expect(picker(), findsNothing);
      expect(c.fen, _whitePromo);
    });

    testWidgets('turning on read-only closes the picker', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tester.pumpWidget(host(ChessBoard(controller: c, readOnly: true)));
      expect(picker(), findsNothing);
      expect(c.fen, _whitePromo);
    });
  });

  group('options', () {
    testWidgets('autoQueen skips the picker', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c, autoQueen: true));
      await dragTo(tester, Square.a7, Square.a8);
      expect(picker(), findsNothing);
      expect(c.pieceAt(Square.a8), Piece.whiteQueen);
    });

    testWidgets('a custom picker builder replaces the default', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      PieceColor? askedColor;
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          promotionPickerBuilder: (context, request) {
            askedColor = request.color;
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => request.choose(PieceType.knight),
                    child: const Text('Knight please'),
                  ),
                  TextButton(
                    onPressed: request.cancel,
                    child: const Text('Never mind'),
                  ),
                ],
              ),
            );
          },
        ),
      );
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      expect(find.byType(PromotionPicker), findsNothing);
      expect(askedColor, PieceColor.white);
      await tester.tap(find.text('Knight please'));
      await tester.pump();
      expect(c.pieceAt(Square.a8), Piece.whiteKnight);
      expect(find.text('Knight please'), findsNothing);
    });

    testWidgets('a custom picker can cancel', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          promotionPickerBuilder: (context, request) => Center(
            child: TextButton(
              onPressed: request.cancel,
              child: const Text('Never mind'),
            ),
          ),
        ),
      );
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tester.tap(find.text('Never mind'));
      await tester.pump();
      expect(find.text('Never mind'), findsNothing);
      expect(c.fen, _whitePromo);
    });

    testWidgets('the picker has screen-reader labels', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      expect(find.bySemanticsLabel('Promote to queen'), findsOneWidget);
      expect(find.bySemanticsLabel('Promote to knight'), findsOneWidget);
      expect(find.bySemanticsLabel('Promote to rook'), findsOneWidget);
      expect(find.bySemanticsLabel('Promote to bishop'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a screen reader can choose a piece', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      final rook = find.bySemanticsLabel('Promote to rook');
      expect(
        tester.getSemantics(rook),
        matchesSemantics(
          label: 'Promote to rook',
          isButton: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('Promote to rook'));
      await tester.pump();
      expect(c.pieceAt(Square.a8), Piece.whiteRook);
      handle.dispose();
    });

    testWidgets('a screen reader can cancel', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      tester.semantics.tap(find.semantics.byLabel('Cancel promotion'));
      await tester.pump();
      expect(picker(), findsNothing);
      expect(c.fen, _whitePromo);
      handle.dispose();
    });

    testWidgets('a custom picker gets the promotion square to place itself', (
      tester,
    ) async {
      final c = ChessBoardController(fen: _whitePromo);
      Rect? rect;
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          promotionPickerBuilder: (context, request) {
            rect = request.squareRect;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: request.squareRect,
                  child: GestureDetector(
                    onTap: () => request.choose(PieceType.queen),
                    child: const Text('Q'),
                  ),
                ),
              ],
            );
          },
        ),
      );
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      final g = squaresPainter(tester).geometry;
      expect(rect, g.squareRect(Square.a8));
      expect(
        tester.getCenter(find.text('Q')),
        offsetMoreOrLessEquals(centerOf(tester, Square.a8), epsilon: 6),
      );
    });

    testWidgets('a tap outside a custom picker cancels', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          promotionPickerBuilder: (context, request) =>
              const Center(child: Text('Choose')),
        ),
      );
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      expect(find.text('Choose'), findsOneWidget);
      await tapSquare(tester, Square.h1);
      expect(find.text('Choose'), findsNothing);
      expect(c.fen, _whitePromo);
    });
  });

  group('robustness', () {
    testWidgets('drag to the last rank, then choose', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await dragTo(tester, Square.a7, Square.a8);
      await tester.pumpAndSettle();
      await tester.tap(choice(PieceType.bishop));
      await tester.pump();
      expect(c.pieceAt(Square.a8), Piece.whiteBishop);
      expect(c.pieceAt(Square.a7), isNull);
    });

    testWidgets('a second tap on a choice does nothing more', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tester.pumpAndSettle();
      final at = tester.getCenter(choice(PieceType.queen));
      await tester.tapAt(at);
      await tester.tapAt(at);
      await tester.pump();
      expect(c.history, hasLength(1));
    });

    testWidgets('moving focus to a text field cancels the picker', (
      tester,
    ) async {
      final c = ChessBoardController(fen: _whitePromo);
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Column(
              children: [
                TextField(focusNode: field),
                SizedBox.square(
                  dimension: 400,
                  child: ChessBoard(controller: c),
                ),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => PieceSet.standard.precache(context));
      await tester.pump();
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      await tester.pump();
      expect(picker(), findsOneWidget);
      field.requestFocus();
      // Focus changes apply in a microtask; the cancel then needs a frame.
      await tester.pump();
      await tester.pump();
      expect(picker(), findsNothing);
      expect(c.fen, _whitePromo);
      expect(field.hasFocus, isTrue);
    });

    testWidgets('Escape works right after the picker opens', (tester) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tester.tapAt(centerOf(tester, Square.a8));
      // One frame only: Escape right after the press that opened it.
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(picker(), findsNothing);
    });

    testWidgets('the picker closes when a code move ends the game', (
      tester,
    ) async {
      final c = ChessBoardController(fen: _whitePromo);
      await pumpBoard(tester, ChessBoard(controller: c));
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      c.loadFen('7k/P7/8/8/8/8/8/K6q w - - 0 1');
      await tester.pump();
      expect(picker(), findsNothing);
    });

    testWidgets('with reduced motion the picker appears at once', (
      tester,
    ) async {
      final c = ChessBoardController(fen: _whitePromo);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(ChessBoard(controller: c)),
        ),
      );
      final context = tester.element(find.byType(ChessBoard));
      await tester.runAsync(() => PieceSet.standard.precache(context));
      await tester.pump();
      await tapSquare(tester, Square.a7);
      await tapSquare(tester, Square.a8);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'no animation');
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of: picker(),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value,
        1,
      );
    });
  });
}
