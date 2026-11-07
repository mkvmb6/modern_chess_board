import 'package:flutter/widgets.dart';

import '../../controller/chess_board_controller.dart';
import '../../pieces/piece_set.dart';
import '../board_geometry.dart';

/// Shows the pieces of [controller]'s current position.
///
/// Only this layer listens to the controller, so a move rebuilds the pieces
/// and nothing else. While [pieceSet] is null (still loading) no pieces are
/// shown, so they appear together instead of popping in one by one.
class PiecesLayer extends StatelessWidget {
  /// Creates the pieces layer.
  const PiecesLayer({
    super.key,
    required this.controller,
    required this.geometry,
    required this.pieceSet,
  });

  /// The game to show.
  final ChessBoardController controller;

  /// Where squares are.
  final BoardGeometry geometry;

  /// The artwork, or null while it is loading.
  final PieceSet? pieceSet;

  @override
  Widget build(BuildContext context) {
    final set = pieceSet;
    if (set == null) return const SizedBox.expand();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (final MapEntry(key: square, value: piece)
              in controller.pieces.entries)
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
