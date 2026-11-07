import 'package:flutter/foundation.dart';

import '../model/game_status.dart';
import 'chess_sound_pack.dart';

/// Sends sound events to a [ChessSoundPack] without letting its errors
/// escape.
///
/// Errors thrown by [ChessSoundPack.play] right away, and errors from the
/// future it returns, are reported once through [FlutterError.reportError]
/// and never rethrown. The board never waits for the pack.
///
/// [ChessSoundPack.play] runs in the caller's zone, not a private one, so a
/// pack can freely await futures it created earlier (such as a player it
/// set up in its constructor). Work a pack starts without returning it is
/// the pack's own responsibility; unhandled errors there reach the app's
/// `PlatformDispatcher.onError` as usual.
class SafeSoundDispatcher {
  /// Creates a dispatcher for [pack].
  SafeSoundDispatcher(this.pack);

  /// The pack events are sent to. Can be changed at any time; errors from
  /// a sound still playing on the old pack are attributed to the old pack.
  ChessSoundPack pack;

  /// Plays [event] on [pack]. Never throws and never waits.
  void dispatch(SoundEvent event) {
    final target = pack;
    void report(Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'modern_chess_board',
          context: ErrorDescription(
            'while playing the ${event.name} sound in ${target.runtimeType}',
          ),
        ),
      );
    }

    try {
      final result = target.play(event);
      if (result is Future<void>) {
        result.then<void>((_) {}, onError: report);
      }
    } catch (error, stack) {
      report(error, stack);
    }
  }
}
