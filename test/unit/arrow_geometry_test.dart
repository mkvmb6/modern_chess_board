import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/board_geometry.dart';
import 'package:modern_chess_board/src/widget/layers/arrows_layer.dart';

void main() {
  const g = BoardGeometry(size: 400, orientation: BoardOrientation.white);

  group('arrow paths', () {
    test('a straight arrow runs from square center to square center, '
        'stopping short of the target so the head lands inside it', () {
      final spec = ArrowSpec.of(const Arrow('e2', 'e4'), g)!;
      expect(spec.start, g.squareCenter(Square.e2));
      // The tip is inside e4, short of its center by the head length.
      final e4 = g.squareRect(Square.e4);
      expect(e4.contains(spec.tip), isTrue);
      expect(spec.tip.dy, greaterThan(g.squareCenter(Square.e4).dy));
      expect(spec.bend, isNull);
    });

    test('a knight move bends at a right angle, long leg first', () {
      final spec = ArrowSpec.of(const Arrow('g1', 'f3'), g)!;
      // Long leg vertical (two ranks), then one file across.
      expect(spec.bend, isNotNull);
      expect(spec.bend!.dx, closeTo(g.squareCenter(Square.g1).dx, 1e-9));
      expect(spec.bend!.dy, closeTo(g.squareCenter(Square.f3).dy, 1e-9));
    });

    test('arrows follow orientation', () {
      const black = BoardGeometry(
        size: 400,
        orientation: BoardOrientation.black,
      );
      final w = ArrowSpec.of(const Arrow('e2', 'e4'), g)!;
      final b = ArrowSpec.of(const Arrow('e2', 'e4'), black)!;
      expect(b.start, black.squareCenter(Square.e2));
      expect(w.start, isNot(b.start));
    });

    test('bad square names and zero-length arrows are skipped', () {
      expect(ArrowSpec.of(const Arrow('z9', 'e4'), g), isNull);
      expect(ArrowSpec.of(const Arrow('e4', ''), g), isNull);
      expect(ArrowSpec.of(const Arrow('e4', 'e4'), g), isNull);
    });
  });

  group('default colors', () {
    test('arrows without a color use the theme arrow color', () {
      expect(
        resolveArrowColor(const Arrow('e2', 'e4'), ChessBoardTheme.green),
        ChessBoardTheme.green.arrowColor,
      );
      const red = Color(0xFFFF0000);
      expect(
        resolveArrowColor(
          const Arrow('e2', 'e4', color: red),
          ChessBoardTheme.green,
        ),
        red,
      );
    });
  });
}
