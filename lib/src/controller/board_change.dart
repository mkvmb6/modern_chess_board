import 'package:flutter/foundation.dart';

import '../model/board_move.dart';

/// Who made a move.
enum MoveSource {
  /// The user, by tapping, dragging or keyboard on the board.
  user,

  /// The app, through the controller.
  code,
}

/// Describes the most recent change to a controller's game state.
///
/// The board reads this to decide whether to animate a change and whether
/// to send a sound event. Apps can read it too, for example to react only
/// to moves made by the user.
@immutable
sealed class BoardChange {
  const BoardChange({required this.silent});

  /// Whether the change was made with `notify: false`.
  ///
  /// Silent changes never animate and never play sounds, even after the app
  /// calls `notifyListeners()` itself.
  final bool silent;
}

/// A move was played.
final class MoveApplied extends BoardChange {
  /// Creates a move change.
  const MoveApplied(this.move, {required this.source, required super.silent});

  /// The move that was played, with SAN and flags filled in.
  final BoardMove move;

  /// Who played it.
  final MoveSource source;

  @override
  String toString() => 'MoveApplied($move, $source, silent: $silent)';
}

/// The position changed in a way that is not a single forward move: undo,
/// reset, or loading a FEN or PGN.
final class PositionReplaced extends BoardChange {
  /// Creates a position-replaced change.
  const PositionReplaced({required super.silent});

  @override
  String toString() => 'PositionReplaced(silent: $silent)';
}
