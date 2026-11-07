import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/board_geometry.dart';

void main() {
  const white = BoardGeometry(size: 400, orientation: BoardOrientation.white);
  const black = BoardGeometry(size: 400, orientation: BoardOrientation.black);

  group('orientation basics', () {
    test('white at the bottom puts a1 bottom-left and h8 top-right', () {
      expect(white.squareRect(Square.a1), const Rect.fromLTWH(0, 350, 50, 50));
      expect(white.squareRect(Square.h8), const Rect.fromLTWH(350, 0, 50, 50));
      expect(
        white.squareRect(Square.e4),
        const Rect.fromLTWH(200, 200, 50, 50),
      );
    });

    test('black at the bottom puts h8 bottom-left and a1 top-right', () {
      expect(black.squareRect(Square.h8), const Rect.fromLTWH(0, 350, 50, 50));
      expect(black.squareRect(Square.a1), const Rect.fromLTWH(350, 0, 50, 50));
      expect(
        black.squareRect(Square.e4),
        const Rect.fromLTWH(150, 150, 50, 50),
      );
    });

    test('orientation helpers', () {
      expect(BoardOrientation.white.bottomColor, PieceColor.white);
      expect(BoardOrientation.black.bottomColor, PieceColor.black);
      expect(BoardOrientation.white.flipped, BoardOrientation.black);
      expect(BoardOrientation.black.flipped, BoardOrientation.white);
      expect(
        BoardOrientation.fromColor(PieceColor.black),
        BoardOrientation.black,
      );
    });

    test('bottom row and left column follow orientation', () {
      expect(white.bottomRow.first, Square.a1);
      expect(white.bottomRow.last, Square.h1);
      expect(white.leftColumn.first, Square.a8);
      expect(white.leftColumn.last, Square.a1);
      expect(black.bottomRow.first, Square.h8);
      expect(black.bottomRow.last, Square.a8);
      expect(black.leftColumn.first, Square.h1);
      expect(black.leftColumn.last, Square.h8);
    });
  });

  group('round trips', () {
    for (final g in [
      white,
      black,
      const BoardGeometry(
        size: 123.4,
        orientation: BoardOrientation.white,
        origin: Offset(17, 9),
      ),
      const BoardGeometry(
        size: 801,
        orientation: BoardOrientation.black,
        origin: Offset(0.5, 30),
      ),
    ]) {
      test('every square round-trips for $g', () {
        for (final s in Square.values) {
          final rect = g.squareRect(s);
          expect(g.squareAt(rect.center), s, reason: '$s center');
          // Just inside each corner still hits the same square.
          const e = 1e-6;
          expect(g.squareAt(rect.topLeft + const Offset(e, e)), s);
          expect(g.squareAt(rect.bottomRight - const Offset(e, e)), s);
          expect(g.squareCenter(s), rect.center);
          expect(g.squareOrigin(s), rect.topLeft);
        }
      });

      test('squares tile the board exactly for $g', () {
        final rects = Square.values.map(g.squareRect).toList();
        final union = rects.reduce((a, b) => a.expandToInclude(b));
        expect(union.left, closeTo(g.boardRect.left, 1e-9));
        expect(union.top, closeTo(g.boardRect.top, 1e-9));
        expect(union.right, closeTo(g.boardRect.right, 1e-9));
        expect(union.bottom, closeTo(g.boardRect.bottom, 1e-9));
        expect(rects.toSet(), hasLength(64));
      });
    }
  });

  group('hit testing', () {
    test('points outside the board hit nothing', () {
      const g = BoardGeometry(
        size: 400,
        orientation: BoardOrientation.white,
        origin: Offset(20, 20),
      );
      for (final p in const [
        Offset(19.9, 100),
        Offset(100, 19.9),
        Offset(420, 100),
        Offset(100, 420),
        Offset(-5, -5),
        Offset(1000, 1000),
      ]) {
        expect(g.squareAt(p), isNull, reason: '$p');
      }
      expect(g.squareAt(const Offset(20, 20)), Square.a8);
      expect(g.squareAt(const Offset(419.99, 419.99)), Square.h1);
    });

    test('an empty board hits nothing', () {
      const g = BoardGeometry(size: 0, orientation: BoardOrientation.white);
      expect(g.squareAt(Offset.zero), isNull);
      expect(g.squareSize, 0);
    });
  });

  group('screen-space stepping', () {
    test('right and up follow the screen in both orientations', () {
      expect(white.step(Square.e4, right: 1), Square.f4);
      expect(white.step(Square.e4, up: 1), Square.e5);
      expect(black.step(Square.e4, right: 1), Square.d4);
      expect(black.step(Square.e4, up: 1), Square.e3);
    });

    test('stepping off the board returns null', () {
      expect(white.step(Square.h1, right: 1), isNull);
      expect(white.step(Square.a1, up: -1), isNull);
      expect(black.step(Square.a1, right: 1), isNull);
      expect(black.step(Square.h8, up: -1), isNull);
    });
  });

  group('flip animation path', () {
    void expectNear(Offset a, Offset b) {
      expect(a.dx, closeTo(b.dx, 1e-9));
      expect(a.dy, closeTo(b.dy, 1e-9));
    }

    for (final g in [
      white,
      black,
      const BoardGeometry(
        size: 300,
        orientation: BoardOrientation.white,
        origin: Offset(12, 12),
      ),
    ]) {
      test('ends match the opposite orientation and this one for $g', () {
        final opposite = g.copyWith(orientation: g.orientation.flipped);
        for (final s in Square.values) {
          expectNear(g.flipOrigin(s, 0), opposite.squareOrigin(s));
          expectNear(g.flipOrigin(s, 1), g.squareOrigin(s));
        }
      });

      test('pieces keep their distance from the center for $g', () {
        final half = Offset(g.squareSize / 2, g.squareSize / 2);
        for (final s in Square.values) {
          final r = (g.squareCenter(s) - g.boardCenter).distance;
          for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            final center = g.flipOrigin(s, t) + half;
            expect((center - g.boardCenter).distance, closeTo(r, 1e-9));
          }
        }
      });
    }

    test('midway, pieces stay spread out instead of piling up', () {
      final half = Offset(white.squareSize / 2, white.squareSize / 2);
      final mids = [
        for (final s in Square.values) white.flipOrigin(s, 0.5) + half,
      ];
      // No two pieces meet: the closest pair is still a square apart.
      var closest = double.infinity;
      for (var i = 0; i < mids.length; i++) {
        for (var j = i + 1; j < mids.length; j++) {
          closest = math.min(closest, (mids[i] - mids[j]).distance);
        }
      }
      expect(closest, closeTo(white.squareSize, 1e-6));
    });
  });

  test('value equality', () {
    expect(
      const BoardGeometry(size: 400, orientation: BoardOrientation.white),
      white,
    );
    expect(white.hashCode, white.copyWith().hashCode);
    expect(white, isNot(black));
    expect(white.copyWith(origin: const Offset(1, 1)), isNot(white));
  });

  group('metrics', () {
    test('inside and none modes use the whole side for the board', () {
      for (final mode in [CoordinateMode.inside, CoordinateMode.none]) {
        final m = BoardMetrics.forSide(400, mode);
        expect(m.outerSize, 400);
        expect(m.margin, 0);
        expect(m.boardSize, 400);
        expect(m.squareSize, 50);
      }
    });

    test('outside mode adds an even margin and keeps the board square', () {
      final m = BoardMetrics.forSide(400, CoordinateMode.outside);
      expect(m.margin, greaterThan(0));
      expect(m.boardSize + 2 * m.margin, closeTo(400, 1e-9));
      final g = m.geometry(BoardOrientation.white);
      expect(g.origin, Offset(m.margin, m.margin));
      expect(g.size, m.boardSize);
    });

    test('shown labels are never below 9 pixels', () {
      for (final side in [40.0, 80.0, 120.0, 200.0, 400.0, 1200.0]) {
        for (final mode in CoordinateMode.values) {
          final m = BoardMetrics.forSide(side, mode);
          expect(m.boardSize, greaterThan(0), reason: '$side $mode');
          if (m.showLabels) {
            expect(m.labelFontSize, greaterThanOrEqualTo(9), reason: '$side');
          }
        }
      }
    });

    test('inside labels fit their squares and hide on tiny boards', () {
      for (final side in [160.0, 200.0, 400.0, 1200.0]) {
        final m = BoardMetrics.forSide(side, CoordinateMode.inside);
        expect(m.showLabels, isTrue, reason: '$side');
        expect(m.labelFontSize, lessThanOrEqualTo(m.squareSize / 1.5));
      }
      for (final side in [40.0, 80.0, 120.0, 140.0]) {
        expect(
          BoardMetrics.forSide(side, CoordinateMode.inside).showLabels,
          isFalse,
          reason: '$side',
        );
      }
    });

    test('the outside margin fits its labels, or is dropped', () {
      for (final side in [120.0, 300.0, 600.0, 1000.0]) {
        final m = BoardMetrics.forSide(side, CoordinateMode.outside);
        expect(m.showLabels, isTrue, reason: '$side');
        expect(m.margin, greaterThanOrEqualTo(m.labelFontSize * 1.2));
      }
      final tiny = BoardMetrics.forSide(40, CoordinateMode.outside);
      expect(tiny.showLabels, isFalse);
      expect(tiny.margin, 0);
      expect(tiny.boardSize, 40);
    });

    test('none mode shows no labels', () {
      final m = BoardMetrics.forSide(400, CoordinateMode.none);
      expect(m.showLabels, isFalse);
      expect(m.margin, 0);
    });

    test('labels follow the text scale but stay within bounds', () {
      const big = TextScaler.linear(2);
      final plain = BoardMetrics.forSide(400, CoordinateMode.inside);
      final scaled = BoardMetrics.forSide(
        400,
        CoordinateMode.inside,
        textScaler: big,
      );
      expect(scaled.labelFontSize, greaterThan(plain.labelFontSize));
      expect(scaled.labelFontSize, lessThanOrEqualTo(scaled.squareSize / 3));

      final outPlain = BoardMetrics.forSide(400, CoordinateMode.outside);
      final outScaled = BoardMetrics.forSide(
        400,
        CoordinateMode.outside,
        textScaler: big,
      );
      expect(outScaled.labelFontSize, greaterThan(outPlain.labelFontSize));
      expect(outScaled.margin, greaterThan(outPlain.margin));
      expect(outScaled.boardSize + 2 * outScaled.margin, closeTo(400, 1e-9));
      expect(outScaled.labelFontSize, lessThanOrEqualTo(400 * 0.04 + 1e-9));
    });

    test('hit testing at exact cell boundaries', () {
      // Left and top edges belong to the square.
      expect(white.squareAt(const Offset(50, 350)), Square.b1);
      expect(white.squareAt(const Offset(0, 300)), Square.a2);
      expect(white.squareAt(const Offset(200, 200)), Square.e4);
    });

    test('resolveSide picks the smaller bounded side', () {
      double side(BoxConstraints c) => BoardMetrics.resolveSide(c);
      expect(side(const BoxConstraints(maxWidth: 400, maxHeight: 300)), 300);
      expect(side(const BoxConstraints(maxWidth: 250, maxHeight: 900)), 250);
      expect(side(const BoxConstraints(maxWidth: 400)), 400);
      expect(side(const BoxConstraints(maxHeight: 280)), 280);
      expect(side(const BoxConstraints()), kDefaultBoardSize);
      expect(
        BoardMetrics.resolveSide(const BoxConstraints(), fallback: 200),
        200,
      );
    });
  });
}
