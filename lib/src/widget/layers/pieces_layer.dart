import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../controller/chess_board_controller.dart';
import '../../model/square.dart';
import '../../pieces/piece_set.dart';
import '../board_geometry.dart';

/// Shows the pieces of [controller]'s current position.
///
/// Rebuilds when [positionChanges] notifies, which the board does once per
/// controller change. The board, not this layer, listens to the controller,
/// so it sees every change first (to clear a stale selection, and later to
/// plan animations) and the controller has a single listener per board.
///
/// While [pieceSet] is null (still loading) no pieces are shown, so they
/// appear together instead of popping in one by one.
class PiecesLayer extends StatelessWidget {
  /// Creates the pieces layer.
  const PiecesLayer({
    super.key,
    required this.controller,
    required this.positionChanges,
    required this.hiddenSquares,
    required this.geometry,
    required this.pieceSet,
    this.flip,
    this.flipClockwise = true,
  });

  /// The game to show.
  final ChessBoardController controller;

  /// Notifies when the position to show has changed.
  final Listenable positionChanges;

  /// Squares whose piece is not drawn here: the dragged piece's origin, a
  /// pawn waiting for its promotion choice, or squares an animation is
  /// drawing.
  final ValueListenable<Set<Square>> hiddenSquares;

  /// Where squares are.
  final BoardGeometry geometry;

  /// The artwork, or null while it is loading.
  final PieceSet? pieceSet;

  /// Progress of a board flip into [geometry]'s orientation, from 0 to 1,
  /// or null when not flipping. While it runs, pieces turn around the
  /// board's center to their new squares.
  final Animation<double>? flip;

  /// Which way the board turns during [flip].
  final bool flipClockwise;

  Rect _rectFor(Square square) {
    final t = flip?.value ?? 1;
    if (t >= 1) return geometry.squareRect(square);
    return geometry.flipOrigin(square, t, clockwise: flipClockwise) &
        Size.square(geometry.squareSize);
  }

  @override
  Widget build(BuildContext context) {
    final set = pieceSet;
    if (set == null) return const SizedBox.expand();
    return ListenableBuilder(
      // Built only when the board itself rebuilds, which interactions
      // never cause, so a fresh merge here is cheap.
      listenable: Listenable.merge([positionChanges, hiddenSquares, ?flip]),
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final MapEntry(key: square, value: piece)
              in controller.pieces.entries)
            if (!hiddenSquares.value.contains(square))
              Positioned.fromRect(
                key: ValueKey(square),
                rect: _rectFor(square),
                child: RepaintBoundary(
                  child: ChessPieceView(
                    piece: piece,
                    size: geometry.squareSize,
                    pieceSet: set,
                    // Each square's semantics label names its piece.
                    excludeFromSemantics: true,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
