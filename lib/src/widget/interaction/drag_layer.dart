import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../model/piece.dart';
import '../../model/square.dart';
import '../../pieces/piece_set.dart';
import '../board_geometry.dart';

/// A piece being dragged: where it came from and where the pointer is.
@immutable
class DragInfo {
  /// Creates drag info.
  const DragInfo({
    required this.from,
    required this.piece,
    required this.position,
    required this.kind,
  });

  /// The square the piece was picked up from.
  final Square from;

  /// The piece being dragged.
  final Piece piece;

  /// The pointer position, in the board's coordinates.
  final Offset position;

  /// What kind of pointer is dragging.
  final PointerDeviceKind kind;

  /// A copy with the pointer at [position].
  DragInfo moveTo(Offset position) =>
      DragInfo(from: from, piece: piece, position: position, kind: kind);
}

/// How much bigger a dragged piece is drawn than a square: 15% at most,
/// and never more than 4 pixels past each edge, so it stays close to its
/// square size on small boards.
double dragPieceSize(double squareSize) =>
    squareSize + 2 * math.min(squareSize * 0.075, 4.0);

/// Where the center of the dragged piece is drawn for a pointer at
/// [position].
///
/// With a finger, the piece floats half a square above the fingertip so it
/// stays visible, while its lower edge still overlaps the square under the
/// finger, which is where it will land. With a mouse or stylus it is
/// centered on the pointer.
Offset dragPieceCenter(DragInfo drag, double squareSize) {
  if (drag.kind != PointerDeviceKind.touch) return drag.position;
  return drag.position - Offset(0, squareSize * 0.5);
}

/// Draws the floating piece of a drag on top of the board.
///
/// Rebuilds only itself as the pointer moves. It never takes input; the
/// gesture layer below handles the pointer.
class DragLayer extends StatelessWidget {
  /// Creates the drag layer.
  const DragLayer({
    super.key,
    required this.drag,
    required this.geometry,
    required this.pieceSet,
  });

  /// The current drag, or null.
  final ValueListenable<DragInfo?> drag;

  /// Where squares are.
  final BoardGeometry geometry;

  /// The artwork, or null while it is loading.
  final PieceSet? pieceSet;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<DragInfo?>(
      valueListenable: drag,
      builder: (context, info, _) {
        final set = pieceSet;
        if (info == null || set == null) return const SizedBox.expand();
        final size = dragPieceSize(geometry.squareSize);
        final center = dragPieceCenter(info, geometry.squareSize);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: center.dx - size / 2,
              top: center.dy - size / 2,
              width: size,
              height: size,
              child: ChessPieceView(
                piece: info.piece,
                size: size,
                pieceSet: set,
                excludeFromSemantics: true,
              ),
            ),
          ],
        );
      },
    ),
  );
}
