import 'package:flutter/foundation.dart';

import '../../controller/chess_board_controller.dart';
import '../../model/piece.dart';
import '../../model/square.dart';

/// Which colors the user may move on the board.
enum InteractiveSide {
  /// Both colors, for local two-player games and analysis. The default.
  both,

  /// White only, for example when the app plays black.
  white,

  /// Black only, for example when the app plays white.
  black,

  /// Neither color. Like a read-only board, but keeps other interaction
  /// such as drawing arrows.
  none;

  /// Whether the user may move pieces of [color].
  bool allows(PieceColor color) => switch (this) {
    both => true,
    white => color == PieceColor.white,
    black => color == PieceColor.black,
    none => false,
  };
}

/// What pressing on a square did.
enum TapOutcome {
  /// Nothing: an empty square or a piece the user can't move, with nothing
  /// selected. The selection did not change.
  ignored,

  /// A piece was selected, or the selection switched to another piece.
  selected,

  /// The selected piece was pressed again. It is deselected when the press
  /// ends, unless the press turns into a drag.
  pressedSelected,

  /// The selected piece was tapped again and deselected.
  deselected,

  /// The selected piece moved to the pressed square.
  moved,

  /// The pressed square was not a legal destination; the selection was
  /// cleared and nothing moved.
  illegal,
}

/// Requests a user move from [from] to [to]. Returns whether it was made.
typedef MoveRequest = bool Function(Square from, Square to);

/// The press-to-move rules and the current selection.
///
/// The board acts when a press starts, as chess sites do, so the selection
/// appears and moves happen without waiting for the finger to lift:
///
/// * Pressing a piece the user may move selects it.
/// * Pressing a legal destination of the selected piece makes the move.
/// * Pressing another movable piece switches the selection.
/// * Pressing anything else clears the selection.
/// * Pressing the selected piece again deselects it when the press ends,
///   unless the press became a drag.
///
/// Kept apart from the widget so the rules can be tested directly. The
/// board feeds it presses and reads [selection]; the board decides how a
/// move request is carried out (for example, asking which piece to promote
/// to).
class BoardInteraction {
  /// Creates the interaction for [controller].
  BoardInteraction({
    required this.controller,
    required this.onMove,
    this.readOnly = false,
    this.interactiveSide = InteractiveSide.both,
  });

  /// The game being played.
  ChessBoardController controller;

  /// Carries out a move the user asked for.
  MoveRequest onMove;

  /// When true, the user can't select or move anything.
  bool readOnly;

  /// Which colors the user may move.
  InteractiveSide interactiveSide;

  /// The selected square, or null. Listen to this to paint the selection;
  /// it only notifies when the selection actually changes.
  final ValueNotifier<Square?> selection = ValueNotifier(null);

  /// Set when a press starts on the already-selected piece, so its end can
  /// deselect it.
  bool _pressedSelected = false;

  /// Whether the user may move pieces of [color] right now.
  bool canMove(PieceColor color) =>
      !readOnly &&
      interactiveSide.allows(color) &&
      color == controller.turn &&
      !controller.isGameOver &&
      (!controller.isViewingHistory || controller.allowBranching);

  bool _canSelect(Square square) {
    final piece = controller.pieceAt(square);
    return piece != null && canMove(piece.color);
  }

  /// Applies the rules for a press starting on [square].
  TapOutcome pressDown(Square square) {
    _pressedSelected = false;
    final selected = selection.value;
    if (selected == null) {
      if (!_canSelect(square)) return TapOutcome.ignored;
      selection.value = square;
      return TapOutcome.selected;
    }
    if (selected == square) {
      _pressedSelected = true;
      return TapOutcome.pressedSelected;
    }
    // A legal destination wins over switching, so captures and (later)
    // castling by moving the king onto its rook work.
    final legal = controller
        .legalMovesFrom(selected)
        .any((m) => m.to == square);
    if (legal) {
      selection.value = null;
      return onMove(selected, square) ? TapOutcome.moved : TapOutcome.illegal;
    }
    if (_canSelect(square)) {
      selection.value = square;
      return TapOutcome.selected;
    }
    selection.value = null;
    return TapOutcome.illegal;
  }

  /// Ends the current press. Deselects the piece if the press started on it
  /// while it was already selected and [dragged] is false. Returns whether
  /// it deselected.
  bool pressUp({required bool dragged}) {
    final deselect = _pressedSelected && !dragged;
    _pressedSelected = false;
    if (deselect) selection.value = null;
    return deselect;
  }

  /// Ends the current press without acting on it, for example when the
  /// pointer is cancelled or a second finger lands.
  void pressCancel() => _pressedSelected = false;

  /// Drops a dragged piece from [from] on [to]. Makes the move if it is
  /// legal; either way the selection is cleared, so an illegal drop snaps
  /// back and a legal one leaves nothing selected. Returns what happened.
  TapOutcome drop(Square from, Square to) {
    clear();
    final piece = controller.pieceAt(from);
    if (piece == null || !canMove(piece.color)) return TapOutcome.ignored;
    final legal = controller.legalMovesFrom(from).any((m) => m.to == to);
    if (!legal) return TapOutcome.illegal;
    return onMove(from, to) ? TapOutcome.moved : TapOutcome.illegal;
  }

  /// A whole tap: a press that ends without dragging. Used by tests and by
  /// inputs without separate down and up events, such as screen readers.
  TapOutcome tap(Square square) {
    final outcome = pressDown(square);
    if (pressUp(dragged: false)) return TapOutcome.deselected;
    return outcome;
  }

  /// Clears the selection.
  void clear() {
    _pressedSelected = false;
    selection.value = null;
  }

  /// Drops the selection if its piece can no longer be moved, for example
  /// after the board became read-only or the position changed.
  void revalidate() {
    final selected = selection.value;
    if (selected != null && !_canSelect(selected)) clear();
  }

  /// Releases the selection notifier.
  void dispose() => selection.dispose();
}
