import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/board_geometry.dart';
import 'package:modern_chess_board/src/widget/layers/arrows_layer.dart';

const _g = BoardGeometry(size: 400, orientation: BoardOrientation.white);

/// Paints [painter] over white and returns the RGBA bytes.
Future<(ByteData, int)> _render(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 400, 400),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  painter.paint(canvas, const Size(400, 400));
  final image = await recorder.endRecording().toImage(400, 400);
  final bytes = (await image.toByteData())!;
  return (bytes, image.width);
}

List<int> _pixel(ByteData data, int width, Offset at) {
  final i = (at.dy.round() * width + at.dx.round()) * 4;
  return [for (var k = 0; k < 4; k++) data.getUint8(i + k)];
}

BoardArrowsPainter _painter({
  List<Arrow> arrows = const [],
  List<SquareMark> marks = const [],
  Arrow? hint,
}) => BoardArrowsPainter(
  geometry: _g,
  arrows: arrows,
  marks: marks,
  hint: hint,
  theme: ChessBoardTheme.green,
);

void main() {
  test('an arrow is drawn in its own color', () async {
    final (data, w) = await _render(
      _painter(arrows: const [Arrow('a2', 'a6', color: Color(0xFFFF0000))]),
    );
    expect(_pixel(data, w, _g.squareCenter(Square.a4)), [255, 0, 0, 255]);
  });

  test('a translucent arrow blends its color with the board', () async {
    final (data, w) = await _render(
      _painter(arrows: const [Arrow('a2', 'a6', color: Color(0x800000FF))]),
    );
    final [r, g, b, _] = _pixel(data, w, _g.squareCenter(Square.a4));
    // Half blue over white: blue stays full, red and green about half.
    expect(b, 255);
    expect(r, inInclusiveRange(120, 135));
    expect(g, inInclusiveRange(120, 135));
  });

  test('overlapping arrow parts do not darken', () async {
    // The knight arrow's corner is where both legs of the shaft overlap.
    final (data, w) = await _render(
      _painter(arrows: const [Arrow('b1', 'c3', color: Color(0x800000FF))]),
    );
    final corner = Offset(
      _g.squareCenter(Square.b1).dx,
      _g.squareCenter(Square.c3).dy,
    );
    final mid = Offset(
      corner.dx,
      (corner.dy + _g.squareCenter(Square.b1).dy) / 2,
    );
    expect(_pixel(data, w, corner), _pixel(data, w, mid));
  });

  test('the hint is dashed: its gaps show the board', () async {
    final (data, w) = await _render(
      _painter(hint: const Arrow('a1', 'a8', color: Color(0xFF00FF00))),
    );
    final x = _g.squareCenter(Square.a1).dx;
    var white = 0;
    var green = 0;
    for (var y = 380; y > 100; y--) {
      final p = _pixel(data, w, Offset(x, y.toDouble()));
      if (p[0] > 240 && p[1] > 240) white++;
      if (p[0] < 20 && p[1] > 240) green++;
    }
    expect(green, greaterThan(50));
    expect(white, greaterThan(50));
  });

  test('fill marks are left to the under-piece painter', () async {
    const mark = SquareMark(
      'e4',
      color: Color(0xFFFF0000),
      shape: MarkShape.fill,
    );
    final center = _g.squareCenter(Square.e4);
    final (over, w) = await _render(_painter(marks: const [mark]));
    expect(_pixel(over, w, center), [255, 255, 255, 255]);
    final (under, _) = await _render(
      BoardMarkFillsPainter(
        geometry: _g,
        marks: const [mark],
        theme: ChessBoardTheme.green,
      ),
    );
    expect(_pixel(under, w, center), [255, 0, 0, 255]);
  });

  test('a zero-size board lays out no arrows', () {
    const tiny = BoardGeometry(size: 0, orientation: BoardOrientation.white);
    expect(ArrowSpec.of(const Arrow('e2', 'e4'), tiny), isNull);
  });
}
