import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
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

Future<void> tap(WidgetTester tester, Square square) async {
  await tester.tapAt(centerOf(tester, square));
  await tester.pump();
}

Future<void> drag(WidgetTester tester, Square from, Square to) async {
  final g = await tester.startGesture(centerOf(tester, from));
  await g.moveTo(centerOf(tester, from) + const Offset(0, -20));
  await tester.pump();
  await g.moveTo(centerOf(tester, to));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

/// Records every event it is asked to play.
class RecordingPack extends ChessSoundPack {
  final List<SoundEvent> events = [];

  @override
  void play(SoundEvent event) => events.add(event);
}

void main() {
  group('sound', () {
    testWidgets('a scripted game sends one event per move, by priority', (
      tester,
    ) async {
      final pack = RecordingPack();
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      // User move by tap.
      await tap(tester, Square.e2);
      await tap(tester, Square.e4);
      await tester.pumpAndSettle();
      // App moves through the controller.
      c.moveSan('d5');
      await tester.pumpAndSettle();
      // User capture by drag.
      await drag(tester, Square.e4, Square.d5);
      c.moveSan('Qxd5');
      await tester.pumpAndSettle();
      c.moveSan('Nc3');
      c.moveSan('Qe5+');
      await tester.pumpAndSettle();
      expect(pack.events, [
        SoundEvent.move,
        SoundEvent.move,
        SoundEvent.capture,
        SoundEvent.capture,
        // Two moves before one pump are two notifications, two sounds.
        SoundEvent.move,
        SoundEvent.check,
      ]);
    });

    testWidgets('castling, promotion and game end', (tester) async {
      final pack = RecordingPack();
      final c = ChessBoardController(fen: '4k3/P7/8/8/8/8/8/R3K2R w KQ - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      c.moveSan('O-O');
      await tester.pumpAndSettle();
      c.moveSan('Kd7');
      await tester.pumpAndSettle();
      c.moveSan('a8=Q');
      await tester.pumpAndSettle();
      expect(pack.events, [
        SoundEvent.castle,
        SoundEvent.move,
        SoundEvent.promotion,
      ]);
      pack.events.clear();
      final mate = ChessBoardController();
      await tester.pumpWidget(
        host(ChessBoard(controller: mate, soundPack: pack)),
      );
      for (final san in ['f3', 'e5', 'g4']) {
        mate.moveSan(san);
        await tester.pump();
      }
      mate.moveSan('Qh4#');
      await tester.pumpAndSettle();
      expect(pack.events.last, SoundEvent.gameEnd);
    });

    testWidgets('no sound for undo, reset, load, navigation or silent', (
      tester,
    ) async {
      final pack = RecordingPack();
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5');
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      c.back();
      await tester.pumpAndSettle();
      c.forward();
      await tester.pumpAndSettle();
      c.undo();
      await tester.pumpAndSettle();
      c.move(Square.e7, Square.e5, notify: false);
      await tester.pumpAndSettle();
      c.reset();
      await tester.pumpAndSettle();
      c.loadFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1');
      await tester.pumpAndSettle();
      expect(pack.events, isEmpty);
    });

    testWidgets('illegal drops sound illegal; cancels are silent', (
      tester,
    ) async {
      final pack = RecordingPack();
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      await drag(tester, Square.g1, Square.g3);
      expect(pack.events, [SoundEvent.illegal]);
      pack.events.clear();
      // Tapping away to deselect, on an empty or an opponent square.
      await tap(tester, Square.e2);
      await tap(tester, Square.e5);
      await tap(tester, Square.g1);
      await tap(tester, Square.e7);
      // Tapping an empty square with nothing selected.
      await tap(tester, Square.d5);
      // A drag dropped back where it started.
      await drag(tester, Square.b1, Square.b1);
      expect(pack.events, isEmpty);
    });

    testWidgets('a reply from an app listener still sounds', (tester) async {
      final pack = RecordingPack();
      final c = ChessBoardController();
      // The app's listener is added before the board's, as a bot would be.
      c.addListener(() {
        if (c.turn == PieceColor.black && !c.isViewingHistory) {
          c.moveSan('e5');
        }
      });
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      await tap(tester, Square.e2);
      await tap(tester, Square.e4);
      await tester.pumpAndSettle();
      expect(c.lastMove?.san, 'e5');
      expect(pack.events, [SoundEvent.move]);
    });

    testWidgets('a notified move after a silent one sounds', (tester) async {
      final pack = RecordingPack();
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      c.move(Square.e2, Square.e4, notify: false);
      c.moveSan('e5');
      await tester.pumpAndSettle();
      expect(pack.events, [SoundEvent.move]);
    });

    testWidgets('promotion sounds after the choice, not before', (
      tester,
    ) async {
      final pack = RecordingPack();
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      await tap(tester, Square.a7);
      await tap(tester, Square.a8);
      await tester.pumpAndSettle();
      expect(pack.events, isEmpty);
      await tester.tap(find.byKey(const ValueKey('promotion-queen')));
      await tester.pumpAndSettle();
      expect(pack.events, [SoundEvent.promotion]);
    });

    testWidgets('a cancelled promotion is silent', (tester) async {
      final pack = RecordingPack();
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      await tap(tester, Square.a7);
      await tap(tester, Square.a8);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(pack.events, isEmpty);
    });

    testWidgets('autoQueen sounds promotion once', (tester) async {
      final pack = RecordingPack();
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(
        tester,
        ChessBoard(controller: c, soundPack: pack, autoQueen: true),
      );
      await tap(tester, Square.a7);
      await tap(tester, Square.a8);
      await tester.pumpAndSettle();
      expect(pack.events, [SoundEvent.promotion]);
    });

    testWidgets('typed moves: one sound when played, illegal when not', (
      tester,
    ) async {
      final pack = RecordingPack();
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: pack));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (final (key, ch) in [
        (LogicalKeyboardKey.keyE, 'e'),
        (LogicalKeyboardKey.digit5, '5'),
      ]) {
        await tester.sendKeyEvent(key, character: ch);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pack.events, [SoundEvent.illegal]);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4, character: '4');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(pack.events, [SoundEvent.illegal, SoundEvent.move]);
    });

    testWidgets('an app reply inside onMove sounds after the move', (
      tester,
    ) async {
      final pack = RecordingPack();
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          soundPack: pack,
          onMove: (_) => c.moveSan('Nf6'),
        ),
      );
      await tap(tester, Square.e2);
      await tap(tester, Square.e4);
      await tester.pumpAndSettle();
      expect(pack.events, [SoundEvent.move, SoundEvent.move]);
    });

    testWidgets('a premove sounds when played, not when queued', (
      tester,
    ) async {
      final pack = RecordingPack();
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          soundPack: pack,
          interactiveSide: InteractiveSide.black,
          enablePremoves: true,
        ),
      );
      await tap(tester, Square.e7);
      await tap(tester, Square.e5);
      expect(pack.events, isEmpty);
      c.moveSan('e4');
      await tester.pumpAndSettle();
      expect(pack.events, [SoundEvent.move, SoundEvent.move]);
    });

    testWidgets('a throwing pack never breaks play', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          soundPack: ChessSoundPack.callback((e) => throw StateError('boom')),
        ),
      );
      await tap(tester, Square.e2);
      await tap(tester, Square.e4);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
      expect(errors, hasLength(1));
      expect(errors.single.library, 'modern_chess_board');
    });

    testWidgets('an async failure is reported, not thrown', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          soundPack: ChessSoundPack.callback(
            (e) => Future<void>.error(StateError('later')),
          ),
        ),
      );
      c.moveSan('e4');
      await tester.pumpAndSettle();
      expect(errors, hasLength(1));
    });

    testWidgets('swapping the pack takes effect at once', (tester) async {
      final a = RecordingPack();
      final b = RecordingPack();
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, soundPack: a));
      c.moveSan('e4');
      await tester.pump();
      await tester.pumpWidget(host(ChessBoard(controller: c, soundPack: b)));
      c.moveSan('e5');
      await tester.pumpAndSettle();
      expect(a.events, [SoundEvent.move]);
      expect(b.events, [SoundEvent.move]);
    });
  });

  group('haptics', () {
    late List<String> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              calls.add(call.arguments as String);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('pickup and drop on a phone', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final c = ChessBoardController();
        await pumpBoard(tester, ChessBoard(controller: c, enableHaptics: true));
        await drag(tester, Square.e2, Square.e4);
        expect(calls, [
          'HapticFeedbackType.selectionClick',
          'HapticFeedbackType.lightImpact',
        ]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('no drop haptic when the drop is illegal', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final c = ChessBoardController();
        await pumpBoard(tester, ChessBoard(controller: c, enableHaptics: true));
        await drag(tester, Square.e2, Square.e5);
        expect(calls, ['HapticFeedbackType.selectionClick']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('off by default', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final c = ChessBoardController();
        await pumpBoard(tester, ChessBoard(controller: c));
        await drag(tester, Square.e2, Square.e4);
        expect(calls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('nothing on desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final c = ChessBoardController();
        await pumpBoard(tester, ChessBoard(controller: c, enableHaptics: true));
        await drag(tester, Square.e2, Square.e4);
        expect(calls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
