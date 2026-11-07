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
    required this.hiddenSquare,
    required this.geometry,
    required this.pieceSet,
  });

  /// The game to show.
  final ChessBoardController controller;

  /// Notifies when the position to show has changed.
  final Listenable positionChanges;

  /// A square whose piece is not drawn, because it is being dragged.
  final ValueListenable<Square?> hiddenSquare;

  /// Where squares are.
  final BoardGeometry geometry;

  /// The artwork, or null while it is loading.
  final PieceSet? pieceSet;

  @override
  Widget build(BuildContext context) {
    final set = pieceSet;
    if (set == null) return const SizedBox.expand();
    return ListenableBuilder(
      listenable: Listenable.merge([positionChanges, hiddenSquare]),
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final MapEntry(key: square, value: piece)
              in controller.pieces.entries)
            if (square != hiddenSquare.value)
              Positioned.fromRect(
                key: ValueKey(square),
                rect: geometry.squareRect(square),
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
