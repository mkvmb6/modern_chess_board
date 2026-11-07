import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/pieces/piece_set.dart'
    show debugClearPieceCache, debugIsPrecached;

/// A 1x1 transparent PNG, for image piece sets.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Map<Piece, ImageProvider> _allImages() => {
  for (final p in Piece.values) p: MemoryImage(_png),
};

/// Pumps [child] inside a minimal app and lets asset loads finish.
Future<void> pumpPieces(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

void main() {
  setUp(debugClearPieceCache);

  group('standard set', () {
    testWidgets('precaches all 12 SVGs from the package', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      expect(debugIsPrecached(PieceSet.standard), isFalse);
      await tester.runAsync(() => PieceSet.standard.precache(context));
      expect(debugIsPrecached(PieceSet.standard), isTrue);

      // A second call finishes synchronously.
      final second = PieceSet.standard.precache(context);
      expect(second, isA<SynchronousFuture<void>>());
    });

    testWidgets('renders every piece at the requested size', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      await tester.runAsync(() => PieceSet.standard.precache(context));

      await pumpPieces(
        tester,
        Wrap(
          children: [
            for (final p in Piece.values)
              ChessPieceView(key: ValueKey(p), piece: p, size: 40),
          ],
        ),
      );
      for (final p in Piece.values) {
        expect(tester.getSize(find.byKey(ValueKey(p))), const Size(40, 40));
      }
      expect(tester.takeException(), isNull);
      // Once precached, pieces are drawn from the decoded pictures rather
      // than loaded again through SvgPicture.
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('renders before precaching by loading on demand', (
      tester,
    ) async {
      await pumpPieces(
        tester,
        const ChessPieceView(piece: Piece.whiteKnight, size: 32),
      );
      expect(find.byType(ChessPieceView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('semantics', () {
    testWidgets('pieces expose descriptive labels', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPieces(
        tester,
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChessPieceView(piece: Piece.whiteKing, size: 30),
            ChessPieceView(piece: Piece.blackKnight, size: 30),
            ChessPieceView(
              piece: Piece.blackPawn,
              size: 30,
              semanticsLabel: 'captured pawn',
            ),
          ],
        ),
      );
      expect(find.bySemanticsLabel('white king'), findsOneWidget);
      expect(find.bySemanticsLabel('black knight'), findsOneWidget);
      expect(find.bySemanticsLabel('captured pawn'), findsOneWidget);
      handle.dispose();
    });
  });

  group('custom sets', () {
    test('an incomplete image map fails with a clear error', () {
      final images = _allImages()
        ..remove(Piece.whiteQueen)
        ..remove(Piece.blackKnight);
      expect(
        () => PieceSet.images(images),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('missing'), contains('wQ'), contains('bN')),
          ),
        ),
      );
      expect(() => PieceSet.images(const {}), throwsArgumentError);
    });

    testWidgets('image sets render and precache', (tester) async {
      final set = PieceSet.images(_allImages());
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      await tester.runAsync(() => set.precache(context));
      await pumpPieces(
        tester,
        ChessPieceView(piece: Piece.blackQueen, size: 24, pieceSet: set),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(tester.getSize(find.byType(ChessPieceView)), const Size(24, 24));
    });

    testWidgets('builder sets call the builder with piece and size', (
      tester,
    ) async {
      final calls = <(Piece, double)>[];
      final set = PieceSet.builder((context, piece, size) {
        calls.add((piece, size));
        return Text(piece.code);
      });
      await pumpPieces(
        tester,
        ChessPieceView(piece: Piece.whiteRook, size: 50, pieceSet: set),
      );
      expect(calls, [(Piece.whiteRook, 50.0)]);
      expect(find.text('wR'), findsOneWidget);
    });

    testWidgets('builder sets run their precache hook', (tester) async {
      var precached = 0;
      final set = PieceSet.builder(
        (context, piece, size) => const SizedBox(),
        precache: (context) async => precached++,
      );
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      await set.precache(context);
      expect(precached, 1);
    });

    testWidgets('a failed SVG precache can be retried', (tester) async {
      const set = PieceSet.svgAssets('does/not/exist');
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      Object? error;
      await tester.runAsync(() async {
        try {
          await set.precache(context);
        } catch (e) {
          error = e;
        }
      });
      expect(error, isNotNull);
      expect(debugIsPrecached(set), isFalse);
      // Retrying starts a fresh load rather than returning the failed one.
      Object? again;
      await tester.runAsync(() async {
        try {
          await set.precache(context);
        } catch (e) {
          again = e;
        }
      });
      expect(again, isNotNull);
    });
  });

  group('layout', () {
    Future<void> precacheStandard(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      await tester.runAsync(() => PieceSet.standard.precache(context));
    }

    testWidgets('precached pieces honor size in an unbounded parent', (
      tester,
    ) async {
      await precacheStandard(tester);
      await pumpPieces(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) => KeyedSubtree(
                key: const Key('raw'),
                child: PieceSet.standard.build(context, Piece.whiteKing, 36),
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const Key('raw'))), const Size(36, 36));
    });

    testWidgets('precached pieces keep their aspect ratio in a wide box', (
      tester,
    ) async {
      await precacheStandard(tester);
      // A tight 120x40 box forces the piece's box to that size; the
      // picture inside must still be drawn square and centered.
      await pumpPieces(
        tester,
        SizedBox(
          width: 120,
          height: 40,
          child: Builder(
            builder: (context) =>
                PieceSet.standard.build(context, Piece.blackQueen, 40),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final picture = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_PictureView',
      );
      expect(picture, findsOneWidget);
      // The 100x100 view box is scaled uniformly by 0.4 (the smaller of
      // 120/100 and 40/100) and offset by (120 - 40) / 2 = 40 to center it.
      expect(
        tester.renderObject(picture),
        paints
          ..save()
          ..translate(x: 40, y: 0)
          ..scale(x: 0.4, y: 0.4)
          ..restore(),
      );
    });
  });

  group('semantics opt-out', () {
    testWidgets('excludeFromSemantics leaves exactly one label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPieces(
        tester,
        Semantics(
          label: 'e4, white pawn',
          container: true,
          child: const ChessPieceView(
            piece: Piece.whitePawn,
            size: 40,
            excludeFromSemantics: true,
          ),
        ),
      );
      expect(find.bySemanticsLabel('e4, white pawn'), findsOneWidget);
      expect(find.bySemanticsLabel('white pawn'), findsNothing);
      handle.dispose();
    });
  });

  group('failures', () {
    testWidgets('a failing image precache reports the error', (tester) async {
      final set = PieceSet.images({
        for (final p in Piece.values)
          p: MemoryImage(Uint8List.fromList(const [1, 2, 3])),
      });
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      await tester.runAsync(() => set.precache(context));
      FlutterError.onError = previous;
      // precacheImage reports decode failures instead of throwing.
      expect(errors, isNotEmpty);
    });
  });

  group('equality', () {
    test('a trailing slash on the directory does not matter', () {
      expect(const PieceSet.svgAssets('a/'), const PieceSet.svgAssets('a'));
      expect(
        const PieceSet.svgAssets('a/').hashCode,
        const PieceSet.svgAssets('a').hashCode,
      );
    });

    test('SVG sets compare by directory and package', () {
      expect(
        const PieceSet.svgAssets('a', package: 'p'),
        const PieceSet.svgAssets('a', package: 'p'),
      );
      expect(
        const PieceSet.svgAssets('a', package: 'p').hashCode,
        const PieceSet.svgAssets('a', package: 'p').hashCode,
      );
      expect(
        const PieceSet.svgAssets('a'),
        isNot(const PieceSet.svgAssets('b')),
      );
      expect(
        const PieceSet.svgAssets('a'),
        isNot(const PieceSet.svgAssets('a', package: 'p')),
      );
      expect(
        PieceSet.standard,
        const PieceSet.svgAssets(
          'assets/pieces/default',
          package: 'modern_chess_board',
        ),
      );
    });

    test('image sets compare by their providers', () {
      Map<Piece, ImageProvider> assets(String dir) => {
        for (final p in Piece.values) p: AssetImage('$dir/${p.code}.png'),
      };
      expect(PieceSet.images(assets('x')), PieceSet.images(assets('x')));
      expect(
        PieceSet.images(assets('x')).hashCode,
        PieceSet.images(assets('x')).hashCode,
      );
      expect(PieceSet.images(assets('x')), isNot(PieceSet.images(assets('y'))));
    });

    test('builder sets compare by id, otherwise by identity', () {
      Widget b(BuildContext c, Piece p, double s) => const SizedBox();
      final anon = PieceSet.builder(b);
      expect(anon, anon);
      expect(PieceSet.builder(b), isNot(PieceSet.builder(b)));
      expect(PieceSet.builder(b, id: 'x'), PieceSet.builder(b, id: 'x'));
      expect(
        PieceSet.builder(b, id: 'x').hashCode,
        PieceSet.builder(b, id: 'x').hashCode,
      );
      expect(PieceSet.builder(b, id: 'x'), isNot(PieceSet.builder(b, id: 'y')));
    });

    test('different kinds of sets are never equal', () {
      Widget b(BuildContext c, Piece p, double s) => const SizedBox();
      expect(PieceSet.standard, isNot(PieceSet.builder(b, id: 'standard')));
    });
  });

  test('the bundled asset files load through the root bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final p in Piece.values) {
      final data = await rootBundle.load('assets/pieces/default/${p.code}.svg');
      expect(data.lengthInBytes, greaterThan(1000));
    }
  });
}
