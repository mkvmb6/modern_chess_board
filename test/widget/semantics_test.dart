import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/labels_layer.dart';

Widget host(ChessBoard board, {double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Material(
      child: Center(child: SizedBox.square(dimension: 400, child: board)),
    ),
  ),
);

Future<void> pumpBoard(
  WidgetTester tester,
  ChessBoard board, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(host(board, textScale: textScale));
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => board.pieceSet.precache(context));
  await tester.pump();
}

/// Announcements sent to the platform.
List<String> captureAnnouncements() {
  final out = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
        message,
      ) async {
        final map = message! as Map<Object?, Object?>;
        if (map['type'] == 'announce') {
          final data = map['data']! as Map<Object?, Object?>;
          out.add(data['message']! as String);
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return out;
}

void main() {
  group('square labels', () {
    testWidgets('every square names its contents', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      expect(find.bySemanticsLabel('e2, white pawn'), findsOneWidget);
      expect(find.bySemanticsLabel('e8, black king'), findsOneWidget);
      expect(find.bySemanticsLabel('e4, empty'), findsOneWidget);
      // 64 squares, each once.
      expect(
        find.bySemanticsLabel(RegExp(r'^[a-h][1-8], ')),
        findsNWidgets(64),
      );
      handle.dispose();
    });

    testWidgets('labels follow the position', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      c.moveSan('e4');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('e4, white pawn'), findsOneWidget);
      expect(find.bySemanticsLabel('e2, empty'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('selection and legal moves are exposed', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      tester.semantics.tap(find.semantics.byLabel('e2, white pawn'));
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('e2, white pawn')),
        matchesSemantics(
          label: 'e2, white pawn',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      final e4 = tester.getSemantics(find.bySemanticsLabel('e4, empty'));
      expect(e4.hint, 'legal move');
      final e5 = tester.getSemantics(find.bySemanticsLabel('e5, empty'));
      expect(e5.hint, isEmpty);
      handle.dispose();
    });

    testWidgets('squares follow the orientation in reading order', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: ChessBoardController(),
          orientation: BoardOrientation.black,
        ),
      );
      final a1 = tester.getRect(find.bySemanticsLabel('a1, white rook'));
      final h8 = tester.getRect(find.bySemanticsLabel('h8, black rook'));
      // Black at the bottom: h8 is at the bottom left, a1 at the top right.
      expect(h8.top, greaterThan(a1.top));
      expect(h8.left, lessThan(a1.left));
      handle.dispose();
    });

    testWidgets('pieces are not read twice', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      expect(find.bySemanticsLabel('white pawn'), findsNothing);
      handle.dispose();
    });
  });

  group('activating', () {
    testWidgets('activating two squares plays the move', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController();
      final moves = <BoardMove>[];
      await pumpBoard(tester, ChessBoard(controller: c, onMove: moves.add));
      tester.semantics.tap(find.semantics.byLabel('g1, white knight'));
      await tester.pump();
      tester.semantics.tap(find.semantics.byLabel('f3, empty'));
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.f3), Piece.whiteKnight);
      expect(moves.single.san, 'Nf3');
      handle.dispose();
    });

    testWidgets('activation follows the same rules: castling onto the rook', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController(
        fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
      );
      await pumpBoard(tester, ChessBoard(controller: c));
      tester.semantics.tap(find.semantics.byLabel('e1, white king'));
      await tester.pump();
      tester.semantics.tap(find.semantics.byLabel('h1, white rook'));
      await tester.pumpAndSettle();
      expect(c.lastMove?.castle, CastleSide.kingside);
      handle.dispose();
    });

    testWidgets('squares are hidden while the promotion picker is open', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c));
      tester.semantics.tap(find.semantics.byLabel('a7, white pawn'));
      await tester.pump();
      tester.semantics.tap(find.semantics.byLabel('a8, empty'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Promote to queen'), findsOneWidget);
      // Not in the semantics tree a screen reader walks.
      expect(find.semantics.byLabel('h1, empty'), findsNothing);
      tester.semantics.tap(find.semantics.byLabel('Promote to queen'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('a8, white queen'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('premove targets read as premoves', (tester) async {
      final handle = tester.ensureSemantics();
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          interactiveSide: InteractiveSide.black,
          enablePremoves: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('g8, black knight'));
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('f6, empty')).hint,
        'premove',
      );
      tester.semantics.tap(find.semantics.byLabel('f6, empty'));
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('f6, empty')).hint,
        'premove queued',
      );
      handle.dispose();
    });

    testWidgets('the board itself has a name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      expect(find.bySemanticsLabel('Chess board'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a read-only board offers no tap action', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBoard(
        tester,
        ChessBoard(controller: ChessBoardController(), readOnly: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('e2, white pawn')),
        isNot(isSemantics(hasTapAction: true)),
      );
      handle.dispose();
    });
  });

  group('announcements', () {
    testWidgets('each move is announced in words', (tester) async {
      final announced = captureAnnouncements();
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      c.moveSan('Nf3');
      await tester.pumpAndSettle();
      expect(announced, ['White knight to f3']);
    });

    testWidgets('no announcement for navigation or silent changes', (
      tester,
    ) async {
      final announced = captureAnnouncements();
      final c = ChessBoardController()..moveSan('e4');
      await pumpBoard(tester, ChessBoard(controller: c));
      c.back();
      await tester.pumpAndSettle();
      c.forward();
      await tester.pumpAndSettle();
      c.move(Square.e7, Square.e5, notify: false);
      await tester.pumpAndSettle();
      expect(announced, isEmpty);
    });

    testWidgets('apps can word announcements themselves', (tester) async {
      final announced = captureAnnouncements();
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          moveAnnouncer: (move, drawReason) => 'Zug ${move.san}',
        ),
      );
      c.moveSan('e4');
      await tester.pumpAndSettle();
      expect(announced, ['Zug e4']);
    });
  });

  group('text scale', () {
    for (final mode in [CoordinateMode.inside, CoordinateMode.outside]) {
      testWidgets('labels stay inside their space at 2x ($mode)', (
        tester,
      ) async {
        await pumpBoard(
          tester,
          ChessBoard(controller: ChessBoardController(), coordinates: mode),
          textScale: 2,
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
        final metrics = painter.metrics!;
        final square = metrics.geometry(BoardOrientation.white).squareSize;
        if (mode == CoordinateMode.inside) {
          expect(metrics.labelFontSize, lessThanOrEqualTo(square / 3));
        } else {
          expect(metrics.labelFontSize, lessThanOrEqualTo(metrics.margin));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
