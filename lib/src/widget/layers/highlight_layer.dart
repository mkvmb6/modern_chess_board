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
    _paintFocus(canvas);
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

  /// The keyboard cursor: a square outline just inside the square, with a
  /// thin light edge inside it so it reads on both square colors.
  void _paintFocus(Canvas canvas) {
    final square = highlights.focus;
    if (square == null) return;
    final s = geometry.squareSize;
    final width = (s * 0.06).clamp(2.0, 4.0);
    final rect = geometry.squareRect(square).deflate(width / 2);
    canvas.drawRect(
      rect,
      Paint()
        ..color = highlights.focusColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
    canvas.drawRect(
      rect.deflate(width / 2 + 0.5),
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(BoardMarkersPainter old) =>
      old.geometry != geometry || old.highlights != highlights;
}
