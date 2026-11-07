import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../model/annotations.dart';
import '../../theme/chess_board_theme.dart';
import '../board_geometry.dart';

/// The color an [arrow] is drawn in: its own, or the theme default.
Color resolveArrowColor(Arrow arrow, ChessBoardTheme theme) =>
    arrow.color ?? theme.arrowColor;

/// Where an arrow is drawn: from the center of its first square, optionally
/// through a [bend] (knight moves turn a corner, as on chess sites), to a
/// [tip] inside the target square.
@immutable
class ArrowSpec {
  const ArrowSpec._({
    required this.start,
    required this.tip,
    required this.bend,
    required this.squareSize,
  });

  /// Lays out [arrow] on [geometry], or returns null when either square name
  /// is invalid or the arrow has no length.
  static ArrowSpec? of(Arrow arrow, BoardGeometry geometry) {
    final from = arrow.fromSquare;
    final to = arrow.toSquare;
    final s = geometry.squareSize;
    if (from == null || to == null || from == to || !(s > 0)) return null;
    final start = geometry.squareCenter(from);
    final end = geometry.squareCenter(to);
    final df = (to.file - from.file).abs();
    final dr = (to.rank - from.rank).abs();
    // Knight moves: run the long leg first, then turn the corner.
    final knight = (df == 1 && dr == 2) || (df == 2 && dr == 1);
    Offset? bend;
    if (knight) {
      final verticalFirst =
          (geometry.rowOf(from) - geometry.rowOf(to)).abs() >
          (geometry.columnOf(from) - geometry.columnOf(to)).abs();
      bend = verticalFirst
          ? Offset(start.dx, end.dy)
          : Offset(end.dx, start.dy);
    }
    // Stop short of the target center, so the point stays inside the
    // square and covers less of the piece there.
    final last = bend ?? start;
    final dir = end - last;
    final length = dir.distance;
    final tip = end - dir / length * (s * 0.18);
    return ArrowSpec._(start: start, tip: tip, bend: bend, squareSize: s);
  }

  /// Center of the first square.
  final Offset start;

  /// Where the arrowhead's point is.
  final Offset tip;

  /// The corner of a knight-move arrow, or null for a straight arrow.
  final Offset? bend;

  /// Side of one square, which sets the arrow's thickness.
  final double squareSize;

  /// The direction the head points in.
  Offset get headDirection {
    final d = tip - (bend ?? start);
    return d / d.distance;
  }
}

/// Paints app arrows, square marks and the hint arrow over the board.
///
/// Annotation arrows are solid, rounded, with a filled triangular head, in
/// their own color or [ChessBoardTheme.arrowColor]. The hint arrow looks
/// clearly different: a dashed line with an open chevron head, in
/// [ChessBoardTheme.hintArrowColor]. Square marks are rings inside the
/// square or a flat fill, in [ChessBoardTheme.markColor] by default.
/// Entries with bad square names are skipped (and logged in debug builds).
class BoardArrowsPainter extends CustomPainter {
  /// Creates the painter.
  BoardArrowsPainter({
    required this.geometry,
    required this.arrows,
    required this.marks,
    required this.hint,
    required this.theme,
    this.userArrows = const [],
    this.userMarks = const [],
    this.preview,
  });

  /// Arrows the user drew, each in its own color.
  final List<Arrow> userArrows;

  /// Circles the user drew.
  final List<SquareMark> userMarks;

  /// The arrow being drawn right now, or null.
  final Arrow? preview;

  /// Where squares are.
  final BoardGeometry geometry;

  /// The app's annotation arrows.
  final List<Arrow> arrows;

  /// The app's square marks.
  final List<SquareMark> marks;

  /// The suggestion arrow, or null.
  final Arrow? hint;

  /// Colors.
  final ChessBoardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(geometry.boardRect);
    for (final mark in [...marks, ...userMarks]) {
      _paintMark(canvas, mark);
    }
    for (final arrow in arrows) {
      final spec = ArrowSpec.of(arrow, geometry);
      if (spec == null) {
        _warnBad(arrow);
        continue;
      }
      _paintSolid(canvas, spec, resolveArrowColor(arrow, theme));
    }
    // User drawings come after the app's, and the one being drawn last.
    for (final arrow in [...userArrows, ?preview]) {
      final spec = ArrowSpec.of(arrow, geometry);
      if (spec != null) {
        _paintSolid(canvas, spec, resolveArrowColor(arrow, theme));
      }
    }
    if (hint case final Arrow h) {
      final spec = ArrowSpec.of(h, geometry);
      if (spec == null) {
        _warnBad(h);
      } else {
        _paintHint(canvas, spec, h.color ?? theme.hintArrowColor);
      }
    }
    canvas.restore();
  }

  void _paintMark(Canvas canvas, SquareMark mark) {
    final square = mark.markedSquare;
    if (square == null) {
      _warnBad(mark);
      return;
    }
    final rect = geometry.squareRect(square);
    final color = mark.color ?? theme.markColor;
    switch (mark.shape) {
      case MarkShape.fill:
        // Painted under the pieces by [BoardMarkFillsPainter].
        break;
      case MarkShape.circle:
        final width = geometry.squareSize * 0.075;
        canvas.drawCircle(
          rect.center,
          geometry.squareSize / 2 - width / 2 - geometry.squareSize * 0.02,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..isAntiAlias = true,
        );
    }
  }

  void _paintSolid(Canvas canvas, ArrowSpec spec, Color color) {
    final s = spec.squareSize;
    final width = s * 0.16;
    final headLength = s * 0.42;
    final headWidth = s * 0.44;
    final dir = spec.headDirection;
    final headBase = spec.tip - dir * headLength;
    final shaft = Path()..moveTo(spec.start.dx, spec.start.dy);
    if (spec.bend case final b?) shaft.lineTo(b.dx, b.dy);
    shaft.lineTo(headBase.dx, headBase.dy);
    final opaque = color.withAlpha(255);
    final normal = Offset(-dir.dy, dir.dx) * (headWidth / 2);
    final head = Path()
      ..moveTo(spec.tip.dx, spec.tip.dy)
      ..lineTo(headBase.dx + normal.dx, headBase.dy + normal.dy)
      ..lineTo(headBase.dx - normal.dx, headBase.dy - normal.dy)
      ..close();
    // One layer for shaft and head, so overlapping translucent parts don't
    // darken where they meet. The parts are drawn opaque and the layer
    // applies the arrow's alpha; a layer paint's RGB is ignored.
    canvas.saveLayer(
      shaft.getBounds().expandToInclude(head.getBounds()).inflate(width),
      Paint()..color = const Color(0xFF000000).withValues(alpha: color.a),
    );
    canvas.drawPath(
      shaft,
      Paint()
        ..color = opaque
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      head,
      Paint()
        ..color = opaque
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  void _paintHint(Canvas canvas, ArrowSpec spec, Color color) {
    final s = spec.squareSize;
    final width = s * 0.11;
    // Butt caps keep the gaps open; round caps would close them up.
    final dashPaint = Paint()
      ..color = color.withAlpha(255)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;
    final headPaint = Paint()
      ..color = color.withAlpha(255)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final dash = s * 0.22;
    final gap = s * 0.16;
    // As for solid arrows, one layer so the chevron and the last dash
    // don't darken where they overlap.
    canvas.saveLayer(
      Rect.fromPoints(spec.start, spec.tip)
          .expandToInclude(
            Rect.fromCircle(center: spec.bend ?? spec.tip, radius: 0),
          )
          .inflate(s * 0.5),
      Paint()..color = const Color(0xFF000000).withValues(alpha: color.a),
    );
    final points = [spec.start, ?spec.bend, spec.tip];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      final d = b - a;
      final length = d.distance;
      final unit = d / length;
      var at = 0.0;
      final path = Path();
      while (at < length) {
        final end = math.min(at + dash, length);
        final p = a + unit * at;
        final q = a + unit * end;
        path
          ..moveTo(p.dx, p.dy)
          ..lineTo(q.dx, q.dy);
        at = end + gap;
      }
      canvas.drawPath(path, dashPaint);
    }
    // Open chevron head.
    final dir = spec.headDirection;
    final back = spec.tip - dir * (s * 0.3);
    final normal = Offset(-dir.dy, dir.dx) * (s * 0.22);
    canvas.drawPath(
      Path()
        ..moveTo(back.dx + normal.dx, back.dy + normal.dy)
        ..lineTo(spec.tip.dx, spec.tip.dy)
        ..lineTo(back.dx - normal.dx, back.dy - normal.dy),
      headPaint,
    );
    canvas.restore();
  }

  void _warnBad(Object entry) {
    assert(() {
      debugPrint('modern_chess_board: ignoring $entry with a bad square name');
      return true;
    }());
  }

  @override
  bool shouldRepaint(BoardArrowsPainter old) =>
      old.geometry != geometry ||
      old.hint != hint ||
      old.theme != theme ||
      !listEquals(old.arrows, arrows) ||
      !listEquals(old.marks, marks) ||
      old.preview != preview ||
      !listEquals(old.userArrows, userArrows) ||
      !listEquals(old.userMarks, userMarks);
}

/// Paints the tinted ([MarkShape.fill]) square marks. It sits under the
/// pieces, so a tinted square never hides its piece; ringed marks are drawn
/// over the pieces by [BoardArrowsPainter].
class BoardMarkFillsPainter extends CustomPainter {
  /// Creates the painter.
  BoardMarkFillsPainter({
    required this.geometry,
    required this.marks,
    required this.theme,
  });

  /// Where squares are.
  final BoardGeometry geometry;

  /// The app's square marks; only fills are painted.
  final List<SquareMark> marks;

  /// Colors.
  final ChessBoardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    for (final mark in marks) {
      if (mark.shape != MarkShape.fill) continue;
      final square = mark.markedSquare;
      if (square == null) continue;
      canvas.drawRect(
        geometry.squareRect(square),
        Paint()..color = mark.color ?? theme.markColor,
      );
    }
  }

  @override
  bool shouldRepaint(BoardMarkFillsPainter old) =>
      old.geometry != geometry ||
      old.theme != theme ||
      !listEquals(old.marks, marks);
}
