import 'package:flutter/widgets.dart';

import '../board_geometry.dart';
import 'highlight_model.dart';

/// Paints square tints: last move, selection, check and checkmate, and the
/// hover tint. Drawn under the pieces.
class BoardTintsPainter extends CustomPainter {
  /// Creates a tints painter.
  const BoardTintsPainter({required this.geometry, required this.highlights});

  /// Where squares are.
  final BoardGeometry geometry;

  /// What to paint.
  final BoardHighlights highlights;

  @override
  void paint(Canvas canvas, Size size) {
    for (final MapEntry(key: square, value: color)
        in highlights.tints.entries) {
      canvas.drawRect(geometry.squareRect(square), Paint()..color = color);
    }
    if (highlights.hover case final square?) {
      canvas.drawRect(
        geometry.squareRect(square),
        Paint()..color = highlights.hoverColor,
      );
    }
  }

  @override
  bool shouldRepaint(BoardTintsPainter old) =>
      old.geometry != geometry || old.highlights != highlights;
}

/// Paints legal-destination markers: a small dot on an empty square, a ring
/// hugging the edges of a square that can be captured on. Drawn over the
/// pieces, so rings frame the piece that would be taken.
class BoardMarkersPainter extends CustomPainter {
  /// Creates a markers painter.
  const BoardMarkersPainter({required this.geometry, required this.highlights});

  /// Where squares are.
  final BoardGeometry geometry;

  /// What to paint.
  final BoardHighlights highlights;

  @override
  void paint(Canvas canvas, Size size) {
    if (highlights.markers.isEmpty) return;
    final s = geometry.squareSize;
    final fill = Paint()
      ..color = highlights.markerColor
      ..isAntiAlias = true;
    for (final MapEntry(key: square, value: marker)
        in highlights.markers.entries) {
      final rect = geometry.squareRect(square);
      switch (marker) {
        case LegalMarker.dot:
          canvas.drawCircle(rect.center, s * 0.16, fill);
        case LegalMarker.ring:
          // A ring just inside the square's edge, framing the piece that
          // would be taken without covering it.
          final width = s * 0.105;
          canvas.drawCircle(
            rect.center,
            s * 0.5 - width / 2,
            Paint()
              ..color = highlights.markerColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..isAntiAlias = true,
          );
      }
    }
  }

  @override
  bool shouldRepaint(BoardMarkersPainter old) =>
      old.geometry != geometry || old.highlights != highlights;
}
