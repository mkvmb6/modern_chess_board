import 'package:flutter/widgets.dart';

import '../../model/square.dart';
import '../board_geometry.dart';

/// Paints the 64 squares.
///
/// The whole board is filled with the light color first and dark squares
/// are painted on top, with edges snapped to device pixels. Neighboring
/// squares share exact pixel edges, so no background shows through seams at
/// fractional sizes.
class BoardSquaresPainter extends CustomPainter {
  /// Creates a squares painter.
  const BoardSquaresPainter({
    required this.geometry,
    required this.lightColor,
    required this.darkColor,
    required this.devicePixelRatio,
  });

  /// Where the squares go.
  final BoardGeometry geometry;

  /// Light square color.
  final Color lightColor;

  /// Dark square color.
  final Color darkColor;

  /// Used to snap square edges to physical pixels.
  final double devicePixelRatio;

  double _snap(double v) =>
      (v * devicePixelRatio).roundToDouble() / devicePixelRatio;

  Rect _snapRect(Rect r) => Rect.fromLTRB(
    _snap(r.left),
    _snap(r.top),
    _snap(r.right),
    _snap(r.bottom),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.size <= 0) return;
    canvas.drawRect(_snapRect(geometry.boardRect), Paint()..color = lightColor);
    final dark = Paint()..color = darkColor;
    for (final square in Square.values) {
      if (!square.isLight) {
        canvas.drawRect(_snapRect(geometry.squareRect(square)), dark);
      }
    }
  }

  @override
  bool shouldRepaint(BoardSquaresPainter old) =>
      old.geometry != geometry ||
      old.lightColor != lightColor ||
      old.darkColor != darkColor ||
      old.devicePixelRatio != devicePixelRatio;
}
