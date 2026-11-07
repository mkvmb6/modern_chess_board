import 'package:flutter/foundation.dart';

import '../../controller/chess_board_controller.dart';
import '../../model/board_move.dart';
import '../../model/piece.dart';
import '../../model/square.dart';
import 'premove.dart';

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

  /// A premove was queued from the selected piece to the pressed square.
  premoved,

  /// The pressed square was not a legal destination; the selection was
  /// cleared and nothing moved.
  illegal,
}

/// Requests a user move from [from] to [to]. Returns whether it was made.
typedef MoveRequest = bool Function(Square from, Square to);

/// Queues a premove from [from] to [to]. Returns whether it was queued.
typedef PremoveRequest = bool Function(Square from, Square to);

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
    this.onPremove,
    this.readOnly = false,
    this.interactiveSide = InteractiveSide.both,
    this.enablePremoves = false,
  });

  /// The game being played.
  ChessBoardController controller;

  /// Carries out a move the user asked for.
  MoveRequest onMove;

  /// When true, the user can't select or move anything.
  bool readOnly;

  /// Which colors the user may move.
  InteractiveSide interactiveSide;

  /// Whether the user may queue a move on the opponent's turn. Only takes
  /// effect when [interactiveSide] is a single color.
  bool enablePremoves;

  /// Queues a premove the user asked for.
  PremoveRequest? onPremove;

  /// The selected square, or null. Listen to this to paint the selection;
  /// it only notifies when the selection actually changes.
  final ValueNotifier<Square?> selection = ValueNotifier(null);

  /// Set when a press starts on the already-selected piece, so its end can
  /// deselect it.
  bool _pressedSelected = false;

  /// Whether the user may move pieces of [color] right now: the board is
  /// interactive, it is that side's turn, and the game is live.
  bool canMove(PieceColor color) => _canPlay(color) && color == controller.turn;

  /// Whether the user may queue a premove for pieces of [color]: premoves
  /// are on, the user plays exactly one side, and it is the other side's
  /// turn.
  bool canPremove(PieceColor color) =>
      enablePremoves &&
      onPremove != null &&
      _canPlay(color) &&
      interactiveSide != InteractiveSide.both &&
      color != controller.turn;

  /// Whether the user may select (and drag) pieces of [color]: to move them
  /// now or to premove them.
  bool canSelect(PieceColor color) => canMove(color) || canPremove(color);

  bool _canPlay(PieceColor color) =>
      !readOnly &&
      interactiveSide.allows(color) &&
      !controller.isGameOver &&
      // Premoves wait for the opponent's next move, so they only make sense
      // at the end of the game; moving from history needs branching.
      (!controller.isViewingHistory ||
          (controller.allowBranching && color == controller.turn));

  bool _canSelect(Square square) {
    final piece = controller.pieceAt(square);
    return piece != null && canSelect(piece.color);
  }

  /// Squares the piece on [from] can go to now (its legal moves) or, on the
  /// opponent's turn, be premoved to. Empty for pieces the user can't
  /// select.
  Set<Square> targetsFrom(Square from) {
    final piece = controller.pieceAt(from);
    if (piece == null) return const {};
    if (canMove(piece.color)) {
      return {for (final m in controller.legalMovesFrom(from)) m.to};
    }
    if (canPremove(piece.color)) return _premoveTargets(from);
    return const {};
  }

  /// [premoveDestinations], worked out once per position and square, since
  /// hover and drag ask for it on every pointer move.
  (ChessBoardController, int, Square, Set<Square>)? _premoveCache;

  Set<Square> _premoveTargets(Square from) {
    final cached = _premoveCache;
    if (cached != null &&
        identical(cached.$1, controller) &&
        cached.$2 == controller.changeId &&
        cached.$3 == from) {
      return cached.$4;
    }
    final targets = premoveDestinations(controller, from);
    _premoveCache = (controller, controller.changeId, from, targets);
    return targets;
  }

  /// The square the user means when moving the piece on [from] to [to]:
  /// the legal destination on the user's turn ([resolveTarget]), or a
  /// premove destination on the opponent's. Null if neither.
  Square? resolveAny(Square from, Square to) {
    final piece = controller.pieceAt(from);
    if (piece == null) return null;
    if (canMove(piece.color)) return resolveTarget(from, to);
    if (canPremove(piece.color) && _premoveTargets(from).contains(to)) {
      return to;
    }
    return null;
  }

  TapOutcome _act(Square from, Square to) {
    final piece = controller.pieceAt(from);
    if (piece != null && canMove(piece.color)) {
      return onMove(from, to) ? TapOutcome.moved : TapOutcome.illegal;
    }
    return (onPremove?.call(from, to) ?? false)
        ? TapOutcome.premoved
        : TapOutcome.illegal;
  }

  /// The legal destination meant by the user moving the piece on [from] to
  /// [to], or null if there is none.
  ///
  /// Usually that is [to] itself. Moving the king onto one of its own rooks
  /// means castling on that side, as on chess sites and in Chess960, so it
  /// maps to the king's castling destination when castling there is legal.
  Square? resolveTarget(Square from, Square to) {
    final moves = controller.legalMovesFrom(from);
    if (moves.any((m) => m.to == to)) return to;
    final mover = controller.pieceAt(from);
    final onto = controller.pieceAt(to);
    if (mover?.type != PieceType.king ||
        onto != Piece(mover!.color, PieceType.rook) ||
        to.rank != from.rank) {
      return null;
    }
    final side = to.file > from.file
        ? CastleSide.kingside
        : CastleSide.queenside;
    for (final m in moves) {
      if (m.castle == side) return m.to;
    }
    return null;
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
    // A legal destination wins over switching, so captures and castling by
    // moving the king onto its own rook work.
    final target = resolveAny(selected, square);
    if (target != null) {
      selection.value = null;
      return _act(selected, target);
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
    if (piece == null || !canSelect(piece.color)) return TapOutcome.ignored;
    final target = resolveAny(from, to);
    if (target == null) return TapOutcome.illegal;
    return _act(from, target);
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
