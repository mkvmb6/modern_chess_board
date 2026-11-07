import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/sound/safe_sound_dispatcher.dart';

/// Records every event it is asked to play.
class RecordingPack extends ChessSoundPack {
  final events = <SoundEvent>[];

  @override
  void play(SoundEvent event) => events.add(event);
}

/// Throws in the way chosen by [mode].
class FailingPack extends ChessSoundPack {
  FailingPack(this.mode);

  final String mode;

  @override
  FutureOr<void> play(SoundEvent event) {
    switch (mode) {
      case 'sync':
        throw StateError('sync failure');
      case 'future':
        return Future<void>.error(StateError('future failure'));
      case 'async':
        return () async {
          await Future<void>.delayed(Duration.zero);
          throw StateError('async failure');
        }();
    }
  }
}

/// The common real-world shape: one long-lived player created up front,
/// awaited inside [play], with the pack handling its own errors.
class LongLivedPlayerPack extends ChessSoundPack {
  LongLivedPlayerPack(this._ready);

  final Future<void> _ready;
  final caught = <SoundEvent>[];
  final played = <SoundEvent>[];

  @override
  Future<void> play(SoundEvent event) async {
    try {
      await _ready;
      played.add(event);
    } catch (_) {
      caught.add(event);
    }
  }
}

/// Lets pending microtasks and zero-length timers run.
Future<void> settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<FlutterErrorDetails> reported;
  late FlutterExceptionHandler? previous;

  setUp(() {
    reported = [];
    previous = FlutterError.onError;
    FlutterError.onError = reported.add;
  });

  tearDown(() => FlutterError.onError = previous);

  test('the silent pack plays nothing and reports nothing', () async {
    const pack = SilentSoundPack();
    expect(() => pack.play(SoundEvent.move), returnsNormally);
    SafeSoundDispatcher(pack).dispatch(SoundEvent.capture);
    await settle();
    expect(reported, isEmpty);
  });

  test('events reach the pack in order', () async {
    final pack = RecordingPack();
    final dispatcher = SafeSoundDispatcher(pack);
    dispatcher.dispatch(SoundEvent.move);
    dispatcher.dispatch(SoundEvent.check);
    await settle();
    expect(pack.events, [SoundEvent.move, SoundEvent.check]);
    expect(reported, isEmpty);
  });

  test('a callback pack forwards events', () async {
    final heard = <SoundEvent>[];
    SafeSoundDispatcher(
      ChessSoundPack.callback(heard.add),
    ).dispatch(SoundEvent.castle);
    await settle();
    expect(heard, [SoundEvent.castle]);
  });

  test('the pack can be swapped', () async {
    final a = RecordingPack();
    final b = RecordingPack();
    final dispatcher = SafeSoundDispatcher(a)..dispatch(SoundEvent.move);
    dispatcher.pack = b;
    dispatcher.dispatch(SoundEvent.gameEnd);
    await settle();
    expect(a.events, [SoundEvent.move]);
    expect(b.events, [SoundEvent.gameEnd]);
  });

  for (final mode in ['sync', 'future', 'async']) {
    test('a $mode error is caught, reported once and not rethrown', () async {
      final dispatcher = SafeSoundDispatcher(FailingPack(mode));
      expect(() => dispatcher.dispatch(SoundEvent.capture), returnsNormally);
      await settle();
      expect(reported, hasLength(1));
      final details = reported.single;
      expect(details.exception, isA<StateError>());
      expect('${details.exception}', contains('$mode failure'));
      expect(details.library, 'modern_chess_board');
      expect('${details.context}', contains('capture'));
      expect('${details.context}', contains('FailingPack'));
      expect(details.stack, isNotNull);
    });
  }

  test('a failing pack keeps working for later events', () async {
    final dispatcher = SafeSoundDispatcher(FailingPack('sync'));
    for (var i = 0; i < 3; i++) {
      dispatcher.dispatch(SoundEvent.move);
    }
    await settle();
    expect(reported, hasLength(3));
  });

  test('a pack awaiting a future made before dispatch keeps its own '
      'error handling', () async {
    // A player set up in the constructor that later fails. Each play
    // awaits it and must reach its own catch, not hang or leak the error.
    final ready = Completer<void>();
    final pack = LongLivedPlayerPack(ready.future);
    final dispatcher = SafeSoundDispatcher(pack);
    dispatcher.dispatch(SoundEvent.move);
    dispatcher.dispatch(SoundEvent.capture);
    ready.completeError(StateError('player failed to start'));
    await settle();
    expect(pack.caught, [SoundEvent.move, SoundEvent.capture]);
    expect(reported, isEmpty, reason: 'the pack handled its own error');
  });

  test('a pack sharing one setup future plays every event', () async {
    final ready = Completer<void>();
    final pack = LongLivedPlayerPack(ready.future);
    final dispatcher = SafeSoundDispatcher(pack);
    dispatcher.dispatch(SoundEvent.move);
    dispatcher.dispatch(SoundEvent.check);
    ready.complete();
    await settle();
    expect(pack.played, [SoundEvent.move, SoundEvent.check]);
  });

  test('an error from a swapped-out pack is attributed to that pack', () async {
    final slow = Completer<void>();
    final old = ChessSoundPack.callback((_) => slow.future);
    final dispatcher = SafeSoundDispatcher(old)..dispatch(SoundEvent.move);
    dispatcher.pack = RecordingPack();
    slow.completeError(StateError('late failure'));
    await settle();
    expect(reported, hasLength(1));
    expect('${reported.single.context}', contains('_CallbackSoundPack'));
    expect('${reported.single.context}', isNot(contains('RecordingPack')));
  });
}
