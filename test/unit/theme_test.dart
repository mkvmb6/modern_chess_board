import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/theme/color_math.dart';

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);

/// Legibility thresholds. Small marks (dots, rings, frames, focus) are
/// judged by luminance contrast. Whole-square tints and arrows are judged by
/// perceptual distance (CIE76 delta E), because a hue shift such as yellow
/// over cream is easy to see even at low luminance contrast. For delta E,
/// about 2 is barely noticeable and 10 is clear.
const _markContrast = 1.6;
const _tintDeltaE = 15.0;
const _hoverDeltaE = 4.0;
const _arrowDeltaE = 25.0;
const _tintPairDeltaE = 12.0;
const _labelContrast = 3.0;

void main() {
  group('presets', () {
    test('there are five presets and green is the default', () {
      expect(ChessBoardTheme.presets, [
        ChessBoardTheme.green,
        ChessBoardTheme.brown,
        ChessBoardTheme.blue,
        ChessBoardTheme.purple,
        ChessBoardTheme.monochrome,
      ]);
      expect(ChessBoardTheme.defaultTheme, ChessBoardTheme.green);
    });

    test('presets have distinct square colors', () {
      final squares = ChessBoardTheme.presets
          .map((t) => (t.lightSquareColor, t.darkSquareColor))
          .toSet();
      expect(squares, hasLength(ChessBoardTheme.presets.length));
    });

    test('presets leave optional colors unset', () {
      for (final t in ChessBoardTheme.presets) {
        expect(t.labelColor, isNull);
        expect(t.checkColor, isNull);
        expect(t.marginColor, isNull);
        expect(t.marginLabelColor, isNull);
      }
    });

    test('a theme from just square colors uses the default accents', () {
      const t = ChessBoardTheme(lightSquareColor: _red, darkSquareColor: _blue);
      expect(t.lastMoveColor, ChessBoardTheme.green.lastMoveColor);
      expect(t.annotationColors, ChessBoardTheme.green.annotationColors);
    });
  });

  // A recommended check tint, as documented on checkColor, is checked
  // alongside the preset colors.
  const recommendedCheck = Color(0x99E53935);

  for (final (i, t) in ChessBoardTheme.presets.indexed) {
    final name = ['Green', 'Brown', 'Blue', 'Purple', 'Monochrome'][i];
    group('$name preset is legible', () {
      for (final light in [true, false]) {
        final which = light ? 'light' : 'dark';
        final square = light ? t.lightSquareColor : t.darkSquareColor;

        test('small marks on $which squares', () {
          for (final (label, color) in [
            ('legal move', t.legalMoveColor),
            ('drag frame', t.dragLegalColor),
            ('focus ring', t.focusColor),
          ]) {
            expect(
              contrastRatio(over(color, square), square),
              greaterThanOrEqualTo(_markContrast),
              reason: label,
            );
          }
        });

        test('square tints on $which squares', () {
          for (final (label, color) in [
            ('selection', t.selectionColor),
            ('last move', t.lastMoveColor),
            ('checkmate', t.checkmateColor),
            ('check', recommendedCheck),
            ('premove', t.premoveColor),
            ('drag illegal', t.dragIllegalColor),
          ]) {
            expect(
              deltaE(over(color, square), square),
              greaterThanOrEqualTo(_tintDeltaE),
              reason: label,
            );
          }
          expect(
            deltaE(over(t.hoverColor, square), square),
            greaterThanOrEqualTo(_hoverDeltaE),
            reason: 'hover is subtle but visible',
          );
        });

        test('highlight tints are distinguishable on $which squares', () {
          final tints = {
            'selection': t.selectionColor,
            'last move': t.lastMoveColor,
            'premove': t.premoveColor,
            'check': recommendedCheck,
          };
          final names = tints.keys.toList();
          for (var a = 0; a < names.length; a++) {
            for (var b = a + 1; b < names.length; b++) {
              expect(
                deltaE(
                  over(tints[names[a]]!, square),
                  over(tints[names[b]]!, square),
                ),
                greaterThanOrEqualTo(_tintPairDeltaE),
                reason: '${names[a]} vs ${names[b]}',
              );
            }
          }
        });

        test('arrows and marks on $which squares', () {
          for (final color in [
            t.arrowColor,
            t.markColor,
            t.hintArrowColor,
            ...t.annotationColors.all,
          ]) {
            expect(
              deltaE(over(color, square), square),
              greaterThanOrEqualTo(_arrowDeltaE),
              reason: '$color',
            );
          }
        });

        test('hint arrow differs from app and user arrows on $which', () {
          final hint = over(t.hintArrowColor, square);
          expect(
            deltaE(hint, over(t.arrowColor, square)),
            greaterThanOrEqualTo(_arrowDeltaE),
          );
          expect(
            deltaE(hint, over(t.annotationColors.plain, square)),
            greaterThanOrEqualTo(_tintPairDeltaE),
          );
        });

        test('drag legal and illegal differ on $which squares', () {
          expect(
            deltaE(
              over(t.dragLegalColor, square),
              over(t.dragIllegalColor, square),
            ),
            greaterThanOrEqualTo(_arrowDeltaE),
          );
        });

        test('automatic labels on $which squares', () {
          final label = t.labelColorOn(lightSquare: light);
          expect(label.a, 1.0);
          expect(
            contrastRatio(label, square),
            greaterThanOrEqualTo(_labelContrast),
          );
          // Labels keep the opposite square's tone (lighter on dark squares,
          // darker on light squares) whenever that tone can be readable.
          // Mid-tone dark squares, where even white falls short, fall back
          // to a dark label.
          final toneCanWork =
              light ||
              contrastRatio(const Color(0xFFFFFFFF), square) >= _labelContrast;
          if (toneCanWork) {
            final lighter =
                relativeLuminance(label) > relativeLuminance(square);
            expect(lighter, !light, reason: 'label tone on $which');
          }
        });
      }

      test('the default app arrow and the yellow user arrow differ', () {
        expect(
          deltaE(t.arrowColor, t.annotationColors.shiftAlt),
          greaterThanOrEqualTo(_tintPairDeltaE),
        );
      });
    });
  }

  group('value semantics', () {
    test('equal when every color matches', () {
      final a = ChessBoardTheme.brown.copyWith();
      expect(a, ChessBoardTheme.brown);
      expect(a.hashCode, ChessBoardTheme.brown.hashCode);
    });

    test('each color takes part in equality', () {
      const base = ChessBoardTheme.green;
      final ann = base.annotationColors;
      final variants = [
        base.copyWith(lightSquareColor: _red),
        base.copyWith(darkSquareColor: _red),
        base.copyWith(selectionColor: _red),
        base.copyWith(lastMoveColor: _red),
        base.copyWith(legalMoveColor: _red),
        base.copyWith(hoverColor: _red),
        base.copyWith(labelColor: _red),
        base.copyWith(checkmateColor: _red),
        base.copyWith(checkColor: _red),
        base.copyWith(arrowColor: _red),
        base.copyWith(markColor: _red),
        base.copyWith(hintArrowColor: _red),
        base.copyWith(dragLegalColor: _red),
        base.copyWith(dragIllegalColor: _red),
        base.copyWith(premoveColor: _red),
        base.copyWith(focusColor: _red),
        base.copyWith(marginColor: _red),
        base.copyWith(marginLabelColor: _red),
        base.copyWith(promotionBackgroundColor: _red),
        base.copyWith(promotionScrimColor: _red),
        base.copyWith(annotationColors: ann.copyWith(plain: _red)),
        base.copyWith(annotationColors: ann.copyWith(shift: _red)),
        base.copyWith(annotationColors: ann.copyWith(alt: _red)),
        base.copyWith(annotationColors: ann.copyWith(shiftAlt: _red)),
      ];
      for (final (i, v) in variants.indexed) {
        expect(v, isNot(base), reason: 'variant $i');
      }
      expect(variants.toSet(), hasLength(variants.length));
    });

    test('copyWith changes only what is given', () {
      final t = ChessBoardTheme.blue.copyWith(selectionColor: _red);
      expect(t.selectionColor, _red);
      expect(t.lightSquareColor, ChessBoardTheme.blue.lightSquareColor);
      expect(
        t.copyWith(selectionColor: ChessBoardTheme.blue.selectionColor),
        ChessBoardTheme.blue,
      );
    });

    test('optional colors can be set and cleared again', () {
      final set = ChessBoardTheme.green.copyWith(
        checkColor: _red,
        labelColor: _blue,
        marginColor: _red,
        marginLabelColor: _blue,
      );
      expect(set.checkColor, _red);
      expect(set.labelColor, _blue);
      expect(set.marginColor, _red);
      expect(set.marginLabelColor, _blue);

      final cleared = set.copyWith(
        clearCheckColor: true,
        clearLabelColor: true,
        clearMarginColor: true,
        clearMarginLabelColor: true,
      );
      expect(cleared, ChessBoardTheme.green);
    });

    test('clearing wins over a value given in the same call', () {
      final t = ChessBoardTheme.green.copyWith(
        checkColor: _red,
        clearCheckColor: true,
      );
      expect(t.checkColor, isNull);
    });

    test('annotation colors expose four distinct colors', () {
      final ann = ChessBoardTheme.green.annotationColors;
      expect(ann.all, hasLength(4));
      expect(ann.all.toSet(), hasLength(4));
      expect(ann, ann.copyWith());
      expect(ann.hashCode, ann.copyWith().hashCode);
    });
  });

  group('lerp', () {
    test('ends match the inputs', () {
      const a = ChessBoardTheme.green;
      const b = ChessBoardTheme.purple;
      expect(ChessBoardTheme.lerp(a, b, 0), a);
      expect(ChessBoardTheme.lerp(a, b, 1), b);
      expect(identical(ChessBoardTheme.lerp(a, a, 0.5), a), isTrue);
    });

    test('blends square colors and fades optional colors', () {
      final mid = ChessBoardTheme.lerp(
        ChessBoardTheme.green,
        ChessBoardTheme.green.copyWith(checkColor: _red),
        0.5,
      );
      expect(mid.checkColor!.a, closeTo(0.5, 0.01));
      final squares = ChessBoardTheme.lerp(
        const ChessBoardTheme(lightSquareColor: _red, darkSquareColor: _red),
        const ChessBoardTheme(lightSquareColor: _blue, darkSquareColor: _blue),
        0.5,
      );
      expect(squares.lightSquareColor.r, closeTo(0.5, 0.01));
      expect(squares.lightSquareColor.b, closeTo(0.5, 0.01));
    });
  });

  group('labels', () {
    test('an explicit label color is used on both squares', () {
      final t = ChessBoardTheme.green.copyWith(labelColor: _red);
      expect(t.labelColorOn(lightSquare: true), _red);
      expect(t.labelColorOn(lightSquare: false), _red);
    });

    test('automatic labels use the opposite square color when readable', () {
      const t = ChessBoardTheme(
        lightSquareColor: Color(0xFFFFFFFF),
        darkSquareColor: Color(0xFF202020),
      );
      expect(t.labelColorOn(lightSquare: true), const Color(0xFF202020));
      expect(t.labelColorOn(lightSquare: false), const Color(0xFFFFFFFF));
    });

    test('the green preset keeps a cream label on dark squares', () {
      final label = ChessBoardTheme.green.labelColorOn(lightSquare: false);
      expect(relativeLuminance(label), greaterThan(0.8), reason: '$label');
    });

    test('automatic labels are adjusted when the squares are too similar', () {
      const t = ChessBoardTheme(
        lightSquareColor: Color(0xFF9E9E9E),
        darkSquareColor: Color(0xFF8A8A8A),
      );
      for (final light in [true, false]) {
        final square = light ? t.lightSquareColor : t.darkSquareColor;
        expect(
          contrastRatio(t.labelColorOn(lightSquare: light), square),
          greaterThanOrEqualTo(_labelContrast),
        );
      }
    });

    test('margin labels contrast with the margin background', () {
      const behind = Color(0xFFFFFFFF);
      for (final t in ChessBoardTheme.presets) {
        expect(
          contrastRatio(t.marginLabelColorOn(behind), behind),
          greaterThanOrEqualTo(_labelContrast),
        );
        const darkApp = Color(0xFF121212);
        expect(
          contrastRatio(t.marginLabelColorOn(darkApp), darkApp),
          greaterThanOrEqualTo(_labelContrast),
        );
      }
      final custom = ChessBoardTheme.green.copyWith(
        marginColor: const Color(0xFF303030),
      );
      final label = custom.marginLabelColorOn(const Color(0xFFFFFFFF));
      expect(
        contrastRatio(label, const Color(0xFF303030)),
        greaterThanOrEqualTo(_labelContrast),
      );
      expect(
        ChessBoardTheme.green
            .copyWith(marginLabelColor: _red)
            .marginLabelColorOn(behind),
        _red,
      );
    });
  });

  group('color math', () {
    test('contrast ratio matches the WCAG definition', () {
      expect(
        contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF000000)),
        closeTo(21, 0.01),
      );
      expect(contrastRatio(_red, _red), closeTo(1, 0.0001));
      expect(
        contrastRatio(const Color(0xFF777777), const Color(0xFFFFFFFF)),
        closeTo(4.48, 0.02),
      );
    });

    test('over composites translucent colors', () {
      expect(
        over(const Color(0x80FFFF00), const Color(0xFFEEEED2)),
        isSameColorAs(const Color(0xFFF7F769)),
      );
      expect(over(const Color(0x00123456), _red), isSameColorAs(_red));
    });

    test('deltaE is zero for equal colors and large for opposites', () {
      expect(deltaE(_red, _red), closeTo(0, 1e-9));
      expect(
        deltaE(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(100, 0.5),
      );
      // A known reference value: sRGB red vs blue is about 176 in CIE76.
      expect(deltaE(_red, _blue), closeTo(176.3, 1));
    });

    test('readableOn keeps a readable color', () {
      expect(
        readableOn(const Color(0xFFFFFFFF), const Color(0xFF000000)),
        const Color(0xFF000000),
      );
    });

    test('readableOn moves darker colors darker', () {
      const bg = Color(0xFF888888);
      final fixed = readableOn(bg, const Color(0xFF808080));
      expect(contrastRatio(fixed, bg), greaterThanOrEqualTo(3));
      expect(relativeLuminance(fixed), lessThan(relativeLuminance(bg)));
    });

    test('readableOn moves lighter colors lighter', () {
      const bg = Color(0xFF606060);
      final fixed = readableOn(bg, const Color(0xFF707070));
      expect(contrastRatio(fixed, bg), greaterThanOrEqualTo(3));
      expect(relativeLuminance(fixed), greaterThan(relativeLuminance(bg)));
    });

    test('readableOn falls back to the other direction', () {
      // Near-white background: going lighter cannot reach contrast 3.
      const bg = Color(0xFFF0F0F0);
      final fixed = readableOn(bg, const Color(0xFFFAFAFA));
      expect(contrastRatio(fixed, bg), greaterThanOrEqualTo(3));
      expect(relativeLuminance(fixed), lessThan(relativeLuminance(bg)));
    });

    test('readableOn returns an opaque color', () {
      final c = readableOn(const Color(0xFFFFFFFF), const Color(0x40000000));
      expect(c.a, 1.0);
    });
  });
}
