import 'dart:async';

import '../model/game_status.dart';

/// Plays sounds for board events.
///
/// The package ships no audio and depends on no audio plugin. Implement
/// [play] with the player of your choice and give the pack to the board:
///
/// ```dart
/// // Using package:audioplayers, with files in assets/sounds/.
/// class MySounds extends ChessSoundPack {
///   final _player = AudioPlayer();
///
///   @override
///   Future<void> play(SoundEvent event) =>
///       _player.play(AssetSource('sounds/${event.name}.mp3'));
/// }
///
/// ChessBoard(controller: controller, soundPack: MySounds());
/// ```
///
/// The board sends exactly one event per successful move, picked in the
/// priority order documented on [SoundEvent], plus [SoundEvent.illegal]
/// for rejected moves. It sends nothing for undo, reset, loading a FEN or
/// PGN, history navigation, or changes made with `notify: false`.
///
/// Errors thrown by [play], right away or from the future it returns, are
/// caught and reported through `FlutterError.reportError`; they never break
/// the board.
abstract class ChessSoundPack {
  /// Const constructor for subclasses.
  const ChessSoundPack();

  /// A pack that calls [onEvent] for each event, for quick setups and tests.
  const factory ChessSoundPack.callback(
    FutureOr<void> Function(SoundEvent event) onEvent,
  ) = _CallbackSoundPack;

  /// Plays the sound for [event].
  ///
  /// May return a future; the board doesn't wait for it. Calls can overlap,
  /// for example during fast play or premoves, so [play] may be called
  /// again before the previous sound has finished. Keep it quick: it runs
  /// on the UI thread, so long synchronous work here delays the move.
  /// Errors in work [play] starts but doesn't return are the pack's to
  /// handle.
  FutureOr<void> play(SoundEvent event);
}

/// A pack that plays nothing. The board's default.
class SilentSoundPack extends ChessSoundPack {
  /// Creates a silent pack.
  const SilentSoundPack();

  @override
  void play(SoundEvent event) {}
}

class _CallbackSoundPack extends ChessSoundPack {
  const _CallbackSoundPack(this.onEvent);

  final FutureOr<void> Function(SoundEvent event) onEvent;

  @override
  FutureOr<void> play(SoundEvent event) => onEvent(event);
}
