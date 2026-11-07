import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/pieces/piece_set.dart'
    show debugClearPieceCache;
import 'package:modern_chess_board/src/widget/layers/labels_layer.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

/// Loads the standard piece set, then shows [board] in a [side]-pixel box.
Future<void> pumpBoard(
  WidgetTester tester,
  Widget board, {
  double side = 400,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.square(dimension: side, child: board),
        ),
      ),
    ),
  );
  // Let the asset loads that precache the pieces finish.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

/// The squares that currently show a piece, keyed by square. Uses the
/// board's own geometry, so it works in every label mode.
Map<Square, Piece> shownPieces(WidgetTester tester) {
  final squares =
      tester
              .widget<CustomPaint>(
                find.byWidgetPredicate(
                  (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
                ),
              )
              .painter!
          as BoardSquaresPainter;
  final geometry = squares.geometry;
  final origin = tester.getTopLeft(find.byType(ChessBoard));
  final result = <Square, Piece>{};
  for (final view in tester.widgetList<ChessPieceView>(
    find.byType(ChessPieceView),
  )) {
    final center = tester.getCenter(find.byWidget(view)) - origin;
    result[geometry.squareAt(center)!] = view.piece;
  }
  return result;
}

void main() {
  setUp(debugClearPieceCache);

  group('initial render', () {
    testWidgets('shows the 32 starting pieces on the right squares', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      expect(tester.takeException(), isNull);
      expect(shownPieces(tester), c.pieces);
      expect(find.byType(ChessPieceView), findsNWidgets(32));
    });

    testWidgets('with black at the bottom the pieces are flipped', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, orientation: BoardOrientation.black),
      );
      expect(shownPieces(tester), c.pieces);
      // a1's rook is at the top right on screen.
      final board = tester.getRect(find.byType(ChessBoard));
      final views = tester.widgetList<ChessPieceView>(
        find.byType(ChessPieceView),
      );
      final topRight = views.firstWhere((v) {
        final r = tester.getRect(find.byWidget(v));
        return (r.right - board.right).abs() < 1 &&
            (r.top - board.top).abs() < 1;
      });
      expect(topRight.piece, Piece.whiteRook);
    });

    testWidgets('pieces fill their squares', (tester) async {
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      for (final element in find.byType(ChessPieceView).evaluate()) {
        expect(element.size, const Size(50, 50));
      }
    });

    testWidgets('pieces have no semantics of their own on the board', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      expect(find.bySemanticsLabel('white king'), findsNothing);
      handle.dispose();
    });
  });

  group('initialFen', () {
    testWidgets('is applied when the board first appears', (tester) async {
      const fen = '4k3/8/8/8/8/8/8/4K2R w K - 0 1';
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, initialFen: fen));
      expect(c.fen, fen);
      expect(find.byType(ChessPieceView), findsNWidgets(3));
    });

    testWidgets('changing it later has no effect', (tester) async {
      const fen = '4k3/8/8/8/8/8/8/4K2R w K - 0 1';
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, initialFen: fen));
      await pumpBoard(
        tester,
        ChessBoard(controller: c, initialFen: kInitialFen),
      );
      expect(c.fen, fen);
    });

    testWidgets('an invalid FEN fails with a clear error', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ChessBoard(
            controller: ChessBoardController(),
            initialFen: 'not a fen',
          ),
        ),
      );
      final error = tester.takeException();
      expect(error, isA<ArgumentError>());
      expect('$error', contains('initialFen'));
    });

    testWidgets('remounting the board keeps the game in progress', (
      tester,
    ) async {
      const fen = '4k3/8/8/8/8/8/8/4K2R w K - 0 1';
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, initialFen: fen));
      c.move(Square.h1, Square.h5);
      final afterMove = c.fen;
      // Remove the board, then mount a new one with the same controller.
      await tester.pumpWidget(const SizedBox());
      await pumpBoard(tester, ChessBoard(controller: c, initialFen: fen));
      expect(c.fen, afterMove);
      expect(c.history, hasLength(1));
    });

    testWidgets('a second board sharing the controller does not reset it', (
      tester,
    ) async {
      final c = ChessBoardController()..moveSan('e4');
      await pumpBoard(
        tester,
        ChessBoard(controller: c, initialFen: '4k3/8/8/8/8/8/8/4K3 w - - 0 1'),
      );
      expect(c.history, hasLength(1));
    });

    testWidgets('an invalid FEN fails even on a used controller', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ChessBoard(
            controller: ChessBoardController()..moveSan('e4'),
            initialFen: 'not a fen',
          ),
        ),
      );
      expect(tester.takeException(), isA<ArgumentError>());
    });

    testWidgets('loading it does not notify listeners', (tester) async {
      final c = ChessBoardController();
      var notified = 0;
      c.addListener(() => notified++);
      await pumpBoard(
        tester,
        ChessBoard(controller: c, initialFen: '4k3/8/8/8/8/8/8/4K2R w K - 0 1'),
      );
      expect(notified, 0);
    });
  });

  group('updates', () {
    testWidgets('a controller move updates the board with no app wiring', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      c.move(Square.e2, Square.e4);
      await tester.pump();
      expect(shownPieces(tester), c.pieces);
      expect(shownPieces(tester)[Square.e4], Piece.whitePawn);
      expect(shownPieces(tester)[Square.e2], isNull);
    });

    testWidgets('a move does not repaint the squares', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final before = tester
          .widget<CustomPaint>(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
            ),
          )
          .painter;
      c.move(Square.e2, Square.e4);
      await tester.pump();
      final after = tester
          .widget<CustomPaint>(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
            ),
          )
          .painter;
      expect(identical(before, after), isTrue, reason: 'no rebuild');
    });
  });

  group('labels', () {
    List<BoardLabel> labelsOf(WidgetTester tester) {
      final paint = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BoardLabelsPainter,
      );
      if (paint.evaluate().isEmpty) return const [];
      return (tester.widget<CustomPaint>(paint).painter! as BoardLabelsPainter)
          .labels;
    }

    double fontOf(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.byWidgetPredicate(
                        (w) =>
                            w is CustomPaint && w.painter is BoardLabelsPainter,
                      ),
                    )
                    .painter!
                as BoardLabelsPainter)
            .style
            .fontSize!;

    testWidgets('inside labels name files and ranks in edge squares', (
      tester,
    ) async {
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      final labels = labelsOf(tester);
      expect(labels.map((l) => l.text), [
        ...'abcdefgh'.split(''),
        ...'87654321'.split(''),
      ]);
      // a sits in a1's square, at the bottom left of the board.
      final a = labels.first;
      expect(a.box.bottom, closeTo(400, 4));
      expect(a.box.left, closeTo(0, 4));
      expect(a.alignment, Alignment.bottomRight);
    });

    testWidgets('inside labels follow orientation', (tester) async {
      await pumpBoard(
        tester,
        ChessBoard(
          controller: ChessBoardController(),
          orientation: BoardOrientation.black,
        ),
      );
      expect(labelsOf(tester).map((l) => l.text), [
        ...'hgfedcba'.split(''),
        ...'12345678'.split(''),
      ]);
    });

    testWidgets('inside labels contrast with the square they sit on', (
      tester,
    ) async {
      const theme = ChessBoardTheme.green;
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      for (final l in labelsOf(tester)) {
        expect([
          theme.labelColorOn(lightSquare: true),
          theme.labelColorOn(lightSquare: false),
        ], contains(l.color));
      }
      // a1 is dark, so the "a" and "1" labels use the dark-square color.
      final a = labelsOf(tester).firstWhere((l) => l.text == 'a');
      expect(a.color, theme.labelColorOn(lightSquare: false));
    });

    testWidgets('outside labels sit in margins and the board stays square', (
      tester,
    ) async {
      await pumpBoard(
        tester,
        ChessBoard(
          controller: ChessBoardController(),
          coordinates: CoordinateMode.outside,
        ),
      );
      expect(tester.getSize(find.byType(ChessBoard)), const Size(400, 400));
      final labels = labelsOf(tester);
      expect(labels, hasLength(16));
      final squares =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is CustomPaint && w.painter is BoardSquaresPainter,
                    ),
                  )
                  .painter!
              as BoardSquaresPainter;
      final board = squares.geometry.boardRect;
      expect(board.width, board.height);
      expect(board.left, greaterThan(0));
      for (final l in labels) {
        expect(board.overlaps(l.box.deflate(0.01)), isFalse, reason: l.text);
      }
      // Pieces are inside the playing area, not the margin. Geometry is in
      // the board's local coordinates; piece rects are global.
      final origin = tester.getTopLeft(find.byType(ChessBoard));
      for (final e in find.byType(ChessPieceView).evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget)).shift(-origin);
        expect(board.inflate(0.01).contains(r.topLeft), isTrue, reason: '$r');
        expect(board.inflate(0.01).contains(r.bottomRight), isTrue);
      }
    });

    testWidgets('pieces map to the right squares in outside mode', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          coordinates: CoordinateMode.outside,
          orientation: BoardOrientation.black,
        ),
      );
      expect(shownPieces(tester), c.pieces);
    });

    testWidgets('labels ignore the red missing-Material text style', (
      tester,
    ) async {
      // A bare MaterialApp without Material gives children Flutter's red
      // debug text style; the board must not copy it.
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 400,
              child: ChessBoard(
                controller: ChessBoardController(),
                coordinates: CoordinateMode.outside,
              ),
            ),
          ),
        ),
      );
      for (final l in labelsOf(tester)) {
        expect(l.color, isNot(const Color(0xD0FF0000)));
        expect(l.color.r, lessThan(0.9), reason: 'not red: ${l.color}');
      }
      final style =
          (tester
                      .widget<CustomPaint>(
                        find.byWidgetPredicate(
                          (w) =>
                              w is CustomPaint &&
                              w.painter is BoardLabelsPainter,
                        ),
                      )
                      .painter!
                  as BoardLabelsPainter)
              .style;
      expect(style.decoration, TextDecoration.none);
    });

    testWidgets('labels use the app font family', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Material(
            child: Center(
              child: SizedBox.square(
                dimension: 400,
                child: ChessBoard(controller: ChessBoardController()),
              ),
            ),
          ),
        ),
      );
      final style =
          (tester
                      .widget<CustomPaint>(
                        find.byWidgetPredicate(
                          (w) =>
                              w is CustomPaint &&
                              w.painter is BoardLabelsPainter,
                        ),
                      )
                      .painter!
                  as BoardLabelsPainter)
              .style;
      expect(style.fontFamily, 'Roboto');
      expect(style.fontWeight, FontWeight.w600);
    });

    testWidgets('no labels in none mode', (tester) async {
      await pumpBoard(
        tester,
        ChessBoard(
          controller: ChessBoardController(),
          coordinates: CoordinateMode.none,
        ),
      );
      expect(labelsOf(tester), isEmpty);
    });

    for (final (mode, side) in [
      (CoordinateMode.inside, 160.0),
      (CoordinateMode.outside, 120.0),
    ]) {
      testWidgets(
        'labels stay readable on a narrow board in ${mode.name} ($side px)',
        (tester) async {
          await pumpBoard(
            tester,
            ChessBoard(controller: ChessBoardController(), coordinates: mode),
            side: side,
          );
          expect(tester.takeException(), isNull);
          expect(labelsOf(tester), hasLength(16));
          expect(fontOf(tester), greaterThanOrEqualTo(9));
        },
      );
    }

    testWidgets('inside labels hide rather than crowd a tiny board', (
      tester,
    ) async {
      await pumpBoard(
        tester,
        ChessBoard(controller: ChessBoardController()),
        side: 120,
      );
      expect(tester.takeException(), isNull);
      expect(labelsOf(tester), isEmpty);
      expect(find.byType(ChessPieceView), findsNWidgets(32));
    });

    testWidgets('outside labels can use a margin color', (tester) async {
      await pumpBoard(
        tester,
        ChessBoard(
          controller: ChessBoardController(),
          coordinates: CoordinateMode.outside,
          theme: ChessBoardTheme.brown.copyWith(
            marginColor: const Color(0xFF3B2A1E),
          ),
        ),
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is CustomPaint && w.painter is BoardLabelsPainter,
                    ),
                  )
                  .painter!
              as BoardLabelsPainter;
      expect(painter.marginColor, const Color(0xFF3B2A1E));
      expect(
        ChessBoardTheme.brown
            .copyWith(marginColor: const Color(0xFF3B2A1E))
            .marginLabelColorOn(const Color(0xFF3B2A1E)),
        labelsOf(tester).first.color,
      );
    });
  });

  group('theme', () {
    BoardSquaresPainter squares(WidgetTester tester) =>
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
                  ),
                )
                .painter!
            as BoardSquaresPainter;

    testWidgets('squares use the theme colors', (tester) async {
      await pumpBoard(
        tester,
        ChessBoard(
          controller: ChessBoardController(),
          theme: ChessBoardTheme.blue,
        ),
      );
      expect(squares(tester).lightColor, ChessBoardTheme.blue.lightSquareColor);
      expect(squares(tester).darkColor, ChessBoardTheme.blue.darkSquareColor);
    });

    testWidgets('shortcut colors override the theme', (tester) async {
      const light = Color(0xFFFFF8E1);
      const dark = Color(0xFF795548);
      const mate = Color(0xFFD50000);
      final board = ChessBoard(
        controller: ChessBoardController(),
        theme: ChessBoardTheme.blue,
        lightSquareColor: light,
        darkSquareColor: dark,
        checkmateColor: mate,
      );
      await pumpBoard(tester, board);
      expect(squares(tester).lightColor, light);
      expect(squares(tester).darkColor, dark);
      expect(board.effectiveTheme.checkmateColor, mate);
      expect(
        board.effectiveTheme.selectionColor,
        ChessBoardTheme.blue.selectionColor,
      );
    });

    testWidgets('squares paint without seams at fractional sizes', (
      tester,
    ) async {
      await pumpBoard(
        tester,
        ChessBoard(controller: ChessBoardController()),
        side: 333.3,
      );
      // The light color fills the board before dark squares are painted.
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
        ),
        paints
          ..rect(color: ChessBoardTheme.green.lightSquareColor)
          ..rect(color: ChessBoardTheme.green.darkSquareColor),
      );
    });
  });

  group('piece sets', () {
    testWidgets('a custom builder set is used', (tester) async {
      final set = PieceSet.builder(
        (context, piece, size) => Text(piece.code),
        id: 'letters',
      );
      await pumpBoard(
        tester,
        ChessBoard(controller: ChessBoardController(), pieceSet: set),
      );
      expect(find.text('wK'), findsOneWidget);
      expect(find.text('bP'), findsNWidgets(8));
    });

    testWidgets('switching sets keeps showing pieces without a gap', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      final letters = PieceSet.builder(
        (context, piece, size) => Text(piece.code),
        id: 'letters',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 400,
              child: ChessBoard(controller: c, pieceSet: letters),
            ),
          ),
        ),
      );
      // Builder sets precache synchronously, so the switch is immediate
      // and pieces never disappear.
      expect(find.byType(ChessPieceView), findsNWidgets(32));
      expect(find.text('wQ'), findsOneWidget);
    });

    testWidgets('pieces stay hidden until the first set has loaded', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 400,
              child: ChessBoard(controller: ChessBoardController()),
            ),
          ),
        ),
      );
      // First frame, before asset loading finishes: no half-loaded pieces.
      expect(find.byType(ChessPieceView), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.byType(ChessPieceView), findsNWidgets(32));
    });
  });
}
