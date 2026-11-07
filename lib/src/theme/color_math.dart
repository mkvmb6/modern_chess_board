import 'dart:math' as math;
import 'dart:ui' show Color;

/// Relative luminance of [c] per WCAG 2.x, from 0 (black) to 1 (white).
/// Alpha is ignored; composite translucent colors with [over] first.
double relativeLuminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

double _linear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

/// WCAG contrast ratio between two opaque colors, from 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [fg] painted over an opaque [bg] (source-over compositing).
Color over(Color fg, Color bg) {
  final a = fg.a;
  double mix(double f, double b) => f * a + b * (1 - a);
  return Color.from(
    alpha: 1,
    red: mix(fg.r, bg.r),
    green: mix(fg.g, bg.g),
    blue: mix(fg.b, bg.b),
  );
}

/// Perceptual difference between two opaque colors: CIE76 delta E in the
/// CIELAB color space. About 2 is barely noticeable, 10 is clear, and 50 or
/// more means clearly different colors.
///
/// Used to judge whether a tint over a square is noticeable. Luminance
/// contrast alone misses hue shifts, such as yellow over cream.
double deltaE(Color a, Color b) {
  final (l1, a1, b1) = _lab(a);
  final (l2, a2, b2) = _lab(b);
  final dl = l1 - l2;
  final da = a1 - a2;
  final db = b1 - b2;
  return math.sqrt(dl * dl + da * da + db * db);
}

(double, double, double) _lab(Color c) {
  final r = _linear(c.r);
  final g = _linear(c.g);
  final b = _linear(c.b);
  // sRGB to XYZ (D65), normalized by the reference white.
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = f(x);
  final fy = f(y);
  final fz = f(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

/// Returns [preferred] if it reaches [minContrast] against [background].
///
/// Otherwise it nudges [preferred] in the direction it already sits from
/// [background], lighter towards white or darker towards black, keeping its
/// hue as far as possible. If that direction can't reach [minContrast], it
/// tries the other one. The result is always opaque.
Color readableOn(Color background, Color preferred, {double minContrast = 3}) {
  final opaque = preferred.withValues(alpha: 1);
  if (contrastRatio(opaque, background) >= minContrast) return opaque;
  final lighter = relativeLuminance(opaque) > relativeLuminance(background);
  for (final target in lighter ? [_white, _black] : [_black, _white]) {
    for (var i = 1; i <= 20; i++) {
      final candidate = Color.lerp(opaque, target, i / 20)!;
      if (contrastRatio(candidate, background) >= minContrast) {
        return candidate;
      }
    }
  }
  // Unreachable for minContrast <= 4.58: black or white always gets there.
  return contrastRatio(_black, background) >= contrastRatio(_white, background)
      ? _black
      : _white;
}
