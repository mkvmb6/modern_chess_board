import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../model/square.dart';
import '../../theme/chess_board_theme.dart';
import '../board_geometry.dart';

/// The square under a dragged piece, and whether dropping there is legal.
@immutable
class DropTarget {
  /// Creates a drag target.
  const DropTarget(this.square, {required this.legal});

  /// The square under the pointer.
  final Square square;

  /// Whether the dragged piece may move there.
  final bool legal;

  @override
  bool operator ==(Object other) =>
      other is DropTarget && other.square == square && other.legal == legal;

  @override
  int get hashCode => Object.hash(square, legal);

  @override
  String toString() => 'DropTarget($square, legal: $legal)';
}

/// Shows where a dragged piece would land.
///
/// A legal square gets a frame inside its edges in
/// [ChessBoardTheme.dragLegalColor], plus a soft halo that spills a little
/// past the square, so the target stays visible around a fingertip. An
/// illegal square gets a flat [ChessBoardTheme.dragIllegalColor] tint. The
/// source square and squares off the board show nothing.
class DragFeedbackPainter extends CustomPainter {
  /// Creates the painter.
  const DragFeedbackPainter({
    required this.geometry,
    required this.target,
    required this.theme,
  });

  /// Where squares are.
  final BoardGeometry geometry;

  /// The current target, or null for nothing.
  final DropTarget? target;

  /// The indicator colors.
  final ChessBoardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final t = target;
    if (t == null) return;
    final rect = geometry.squareRect(t.square);
    final s = geometry.squareSize;
    if (!t.legal) {
      canvas.drawRect(rect, Paint()..color = theme.dragIllegalColor);
      return;
    }
    // Halo: a translucent disc larger than the square, clipped to the
    // board so it never spills over the labels or the page.
    canvas.save();
    canvas.clipRect(geometry.boardRect);
    canvas.drawCircle(
      rect.center,
      s * 0.95,
      Paint()
        ..color = theme.dragLegalColor.withValues(
          alpha: theme.dragLegalColor.a * 0.35,
        ),
    );
    canvas.restore();
    // Frame inside the square's edges.
    final width = (s * 0.07).clamp(2.0, 6.0);
    canvas.drawRect(
      rect.deflate(width / 2),
      Paint()
        ..color = theme.dragLegalColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(DragFeedbackPainter old) =>
      old.geometry != geometry || old.target != target || old.theme != theme;
}

/// Paints [DragFeedbackPainter] for the current [target].
///
/// Repaints only when the target square or its legality changes, not on
/// every pointer move.
class DragFeedbackLayer extends StatelessWidget {
  /// Creates the layer.
  const DragFeedbackLayer({
    super.key,
    required this.target,
    required this.geometry,
    required this.theme,
  });

  /// The current target, or null.
  final ValueListenable<DropTarget?> target;

  /// Where squares are.
  final BoardGeometry geometry;

  /// The indicator colors.
  final ChessBoardTheme theme;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: ValueListenableBuilder<DropTarget?>(
        valueListenable: target,
        builder: (context, t, _) => t == null
            ? const SizedBox.expand()
            : CustomPaint(
                painter: DragFeedbackPainter(
                  geometry: geometry,
                  target: t,
                  theme: theme,
                ),
              ),
      ),
    ),
  );
}
