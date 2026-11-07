import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../theme/chess_board_theme.dart';
import '../board_geometry.dart';

/// One coordinate label: its [text], the [box] it sits in, how it is
/// [alignment]ed within the box, and its [color].
@immutable
class BoardLabel {
  /// Creates a label.
  const BoardLabel({
    required this.text,
    required this.box,
    required this.alignment,
    required this.color,
  });

  /// A file letter (`a`-`h`) or rank digit (`1`-`8`).
  final String text;

  /// The area the label is placed in.
  final Rect box;

  /// Where in [box] the text goes.
  final Alignment alignment;

  /// Text color.
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is BoardLabel &&
      other.text == text &&
      other.box == box &&
      other.alignment == alignment &&
      other.color == color;

  @override
  int get hashCode => Object.hash(text, box, alignment, color);

  @override
  String toString() => 'BoardLabel($text)';
}

/// Lays out the 16 coordinate labels for [metrics] and [orientation].
///
/// Inside the board, file letters sit in the bottom-right corner of the
/// bottom row and rank digits in the top-left corner of the left column,
/// each colored to contrast with its square. Outside, files are centered
/// under each column and ranks beside each row, in the margin.
///
/// [ambientTextColor] is the app's text color, used for outside labels when
/// the theme sets neither a margin color nor a margin label color; it is
/// designed to be readable on whatever is behind the board.
List<BoardLabel> layoutBoardLabels({
  required BoardMetrics metrics,
  required BoardOrientation orientation,
  required ChessBoardTheme theme,
  Color? ambientTextColor,
}) {
  if (!metrics.showLabels) return const [];
  final g = metrics.geometry(orientation);
  final labels = <BoardLabel>[];

  if (metrics.coordinates == CoordinateMode.inside) {
    final pad = g.squareSize * 0.07;
    for (final square in g.bottomRow) {
      labels.add(
        BoardLabel(
          text: square.fileName,
          box: g.squareRect(square).deflate(pad),
          alignment: Alignment.bottomRight,
          color: theme.labelColorOn(lightSquare: square.isLight),
        ),
      );
    }
    for (final square in g.leftColumn) {
      labels.add(
        BoardLabel(
          text: square.rankName,
          box: g.squareRect(square).deflate(pad),
          alignment: Alignment.topLeft,
          color: theme.labelColorOn(lightSquare: square.isLight),
        ),
      );
    }
    return labels;
  }

  final color = marginLabelColor(theme, ambientTextColor);
  final m = metrics.margin;
  for (final square in g.bottomRow) {
    final r = g.squareRect(square);
    labels.add(
      BoardLabel(
        text: square.fileName,
        box: Rect.fromLTRB(
          r.left,
          g.boardRect.bottom,
          r.right,
          metrics.outerSize,
        ),
        alignment: Alignment.center,
        color: color,
      ),
    );
  }
  for (final square in g.leftColumn) {
    final r = g.squareRect(square);
    labels.add(
      BoardLabel(
        text: square.rankName,
        box: Rect.fromLTRB(0, r.top, m, r.bottom),
        alignment: Alignment.center,
        color: color,
      ),
    );
  }
  return labels;
}

/// The color for outside labels: the theme's margin label color, else a
/// color readable on the theme's margin color, else the app's text color,
/// else the dark square color made readable on white.
Color marginLabelColor(ChessBoardTheme theme, Color? ambientTextColor) {
  if (theme.marginLabelColor case final c?) return c;
  if (theme.marginColor case final bg?) {
    return theme.marginLabelColorOn(bg.withValues(alpha: 1));
  }
  if (ambientTextColor case final c?) return c.withValues(alpha: c.a * 0.72);
  return theme.marginLabelColorOn(const Color(0xFFFFFFFF));
}

/// Paints coordinate labels.
class BoardLabelsPainter extends CustomPainter {
  /// Creates a labels painter.
  BoardLabelsPainter({
    required this.labels,
    required this.style,
    this.marginColor,
    this.metrics,
  });

  /// The labels to paint.
  final List<BoardLabel> labels;

  /// Text style without color; each label supplies its own color.
  final TextStyle style;

  /// When set, the label margin is filled with this color first.
  final Color? marginColor;

  /// The metrics the labels were laid out for, used with [marginColor].
  final BoardMetrics? metrics;

  @override
  void paint(Canvas canvas, Size size) {
    final m = metrics;
    final fill = marginColor;
    if (fill != null && m != null && m.margin > 0) {
      final outer = Offset.zero & Size.square(m.outerSize);
      final inner = Rect.fromLTWH(m.margin, m.margin, m.boardSize, m.boardSize);
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(outer)
          ..addRect(inner),
        Paint()..color = fill,
      );
    }
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label.text,
          style: style.copyWith(color: label.color),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final rect = label.alignment.inscribe(painter.size, label.box);
      painter.paint(canvas, rect.topLeft);
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(BoardLabelsPainter old) =>
      !listEquals(old.labels, labels) ||
      old.style != style ||
      old.marginColor != marginColor ||
      old.metrics != metrics;
}
