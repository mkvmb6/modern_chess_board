import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/piece.dart';
import '../model/square.dart';

/// Which side is shown at the bottom of the board.
enum BoardOrientation {
  /// White at the bottom, a1 in the bottom-left corner.
  white,

  /// Black at the bottom, h8 in the bottom-left corner.
  black;

  /// The orientation with [color] at the bottom.
  static BoardOrientation fromColor(PieceColor color) =>
      color == PieceColor.white ? white : black;

  /// The color shown at the bottom.
  PieceColor get bottomColor =>
      this == white ? PieceColor.white : PieceColor.black;

  /// The other orientation.
  BoardOrientation get flipped => this == white ? black : white;
}

/// Where coordinate labels are drawn.
enum CoordinateMode {
  /// Inside the edge squares, in their corners. The default.
  inside,

  /// In margins around the board. The playing area stays square, and board
  /// plus margins still fit the available space.
  outside,

  /// No labels and no margin.
  none,
}

/// The side length used when the board has no bounded constraint in either
/// direction, such as inside an `UnconstrainedBox`.
const double kDefaultBoardSize = 320;

/// The smallest label font size, so labels stay readable on small boards.
const double kMinLabelFontSize = 9;

/// Maps squares to pixel positions and back for one board size and
/// orientation.
///
/// This is the only place that knows how orientation affects layout. Every
/// layer (squares, pieces, highlights, labels, arrows, drag feedback and
/// animations) goes through it, which is how they all follow orientation.
///
/// Positions are exact logical pixels. Painters, not the geometry, take
/// care of device-pixel seams.
@immutable
class BoardGeometry {
  /// Creates the geometry for a board [size] logical pixels square whose
  /// top-left corner is at [origin].
  const BoardGeometry({
    required this.size,
    required this.orientation,
    this.origin = Offset.zero,
  });

  /// Side length of the playing area.
  final double size;

  /// Which color is at the bottom.
  final BoardOrientation orientation;

  /// Top-left corner of the playing area, for example inside a label
  /// margin.
  final Offset origin;

  /// Side length of one square.
  double get squareSize => size / 8;

  /// The playing area.
  Rect get boardRect => origin & Size.square(size);

  /// Center of the playing area.
  Offset get boardCenter => origin + Offset(size / 2, size / 2);

  /// Screen column (0 = left) of [square].
  int columnOf(Square square) =>
      orientation == BoardOrientation.white ? square.file : 7 - square.file;

  /// Screen row (0 = top) of [square].
  int rowOf(Square square) =>
      orientation == BoardOrientation.white ? 7 - square.rank : square.rank;

  /// The square at screen [column] and [row], both 0 to 7.
  Square squareAtCell(int column, int row) =>
      orientation == BoardOrientation.white
      ? Square.at(column, 7 - row)
      : Square.at(7 - column, row);

  /// Top-left corner of [square].
  Offset squareOrigin(Square square) => Offset(
    origin.dx + columnOf(square) * squareSize,
    origin.dy + rowOf(square) * squareSize,
  );

  /// The area covered by [square].
  Rect squareRect(Square square) =>
      squareOrigin(square) & Size.square(squareSize);

  /// Center of [square].
  Offset squareCenter(Square square) => squareRect(square).center;

  /// The square under [point], or null if it is outside the board.
  ///
  /// The left and top edges of each square belong to it; the right and
  /// bottom edges belong to the next square. A point exactly on a boundary
  /// may resolve to either neighbor within floating-point error.
  Square? squareAt(Offset point) {
    if (size <= 0) return null;
    final local = point - origin;
    if (local.dx < 0 || local.dy < 0 || local.dx >= size || local.dy >= size) {
      return null;
    }
    final column = (local.dx / squareSize).floor().clamp(0, 7);
    final row = (local.dy / squareSize).floor().clamp(0, 7);
    return squareAtCell(column, row);
  }

  /// The square reached from [square] by moving [right] columns and [up]
  /// rows on screen, or null if that leaves the board. Used for keyboard
  /// navigation, where arrow keys follow the screen, not the board.
  Square? step(Square square, {int right = 0, int up = 0}) {
    final column = columnOf(square) + right;
    final row = rowOf(square) - up;
    if (column < 0 || column > 7 || row < 0 || row > 7) return null;
    return squareAtCell(column, row);
  }

  /// The bottom row of squares, left to right. File labels go here.
  List<Square> get bottomRow => [
    for (var c = 0; c < 8; c++) squareAtCell(c, 7),
  ];

  /// The left column of squares, top to bottom. Rank labels go here.
  List<Square> get leftColumn => [
    for (var r = 0; r < 8; r++) squareAtCell(0, r),
  ];

  /// Top-left corner of a piece on [square] part way through a flip
  /// animation into this orientation.
  ///
  /// The board turns half a circle around its center while pieces stay
  /// upright: at [t] = 0 the piece is where the opposite orientation puts
  /// it, at [t] = 1 where this orientation puts it, and in between it moves
  /// along an arc, keeping its distance from the center. Pieces never pile
  /// up in the middle.
  Offset flipOrigin(Square square, double t) {
    final center = boardCenter;
    final v = squareCenter(square) - center;
    // Turn from the opposite side (angle pi) to here (angle 0).
    final angle = math.pi * (1 - t);
    final c = math.cos(angle);
    final s = math.sin(angle);
    final rotated = Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
    final half = squareSize / 2;
    return center + rotated - Offset(half, half);
  }

  /// Returns a copy with the given fields replaced.
  BoardGeometry copyWith({
    double? size,
    BoardOrientation? orientation,
    Offset? origin,
  }) => BoardGeometry(
    size: size ?? this.size,
    orientation: orientation ?? this.orientation,
    origin: origin ?? this.origin,
  );

  @override
  bool operator ==(Object other) =>
      other is BoardGeometry &&
      other.size == size &&
      other.orientation == orientation &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(size, orientation, origin);

  @override
  String toString() =>
      'BoardGeometry(${size.toStringAsFixed(1)}, ${orientation.name}, '
      'origin: (${origin.dx}, ${origin.dy}))';
}

/// Sizes for a board laid out in a square of [outerSize]: the playing area,
/// the label margin, the label font size, and whether labels fit at all.
@immutable
class BoardMetrics {
  const BoardMetrics._({
    required this.outerSize,
    required this.margin,
    required this.labelFontSize,
    required this.coordinates,
    required this.showLabels,
  });

  /// Metrics for a square of [side] logical pixels with [coordinates].
  ///
  /// Label text follows [textScaler], but never grows beyond what fits: a
  /// third of a square inside the board, or 4% of the side in the margin.
  /// Labels are hidden when even the 9px minimum doesn't fit without
  /// crowding the pieces: inside labels below about 160px, outside labels
  /// on boards around 100px or smaller.
  factory BoardMetrics.forSide(
    double side,
    CoordinateMode coordinates, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final s = math.max(0.0, side);
    switch (coordinates) {
      case CoordinateMode.none:
        return BoardMetrics._(
          outerSize: s,
          margin: 0,
          labelFontSize: 0,
          coordinates: coordinates,
          showLabels: false,
        );
      case CoordinateMode.inside:
        final square = s / 8;
        final base = math.max(kMinLabelFontSize, square * 0.18);
        final font = math.max(
          kMinLabelFontSize,
          math.min(textScaler.scale(base), square / 3),
        );
        return BoardMetrics._(
          outerSize: s,
          margin: 0,
          labelFontSize: font,
          coordinates: coordinates,
          // Below about 2.2 font sizes per square, corner labels crowd the
          // pieces; hide them rather than overlap.
          showLabels: square >= font * 2.2,
        );
      case CoordinateMode.outside:
        final base = math.max(kMinLabelFontSize, s * 0.022);
        final font = math.max(
          kMinLabelFontSize,
          math.min(textScaler.scale(base), s * 0.04),
        );
        // The margin fits one line of text with a little air, capped so the
        // board always keeps most of the space.
        final margin = math.min(font * 1.6, s * 0.2);
        final fits = margin >= font * 1.2;
        return BoardMetrics._(
          outerSize: s,
          margin: fits ? margin : 0,
          labelFontSize: font,
          coordinates: coordinates,
          showLabels: fits,
        );
    }
  }

  /// The board's side length for [constraints]: the smaller bounded side,
  /// the only bounded side, or [fallback] when neither is bounded.
  static double resolveSide(
    BoxConstraints constraints, {
    double fallback = kDefaultBoardSize,
  }) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final double side;
    if (w.isFinite && h.isFinite) {
      side = math.min(w, h);
    } else if (w.isFinite) {
      side = w;
    } else if (h.isFinite) {
      side = h;
    } else {
      side = fallback;
    }
    return math.max(0, side);
  }

  /// Side of the whole widget: playing area plus margins.
  final double outerSize;

  /// Width of the label margin on each side; zero unless labels are
  /// outside and fit.
  final double margin;

  /// Font size for coordinate labels, never below [kMinLabelFontSize].
  /// Zero in [CoordinateMode.none].
  final double labelFontSize;

  /// Where labels go.
  final CoordinateMode coordinates;

  /// Whether labels are drawn: false in [CoordinateMode.none] and on boards
  /// too small for readable labels.
  final bool showLabels;

  /// Side of the playing area.
  double get boardSize => outerSize - 2 * margin;

  /// Side of one square.
  double get squareSize => boardSize / 8;

  /// Geometry for the playing area in [orientation], offset by the margin.
  BoardGeometry geometry(BoardOrientation orientation) => BoardGeometry(
    size: boardSize,
    orientation: orientation,
    origin: Offset(margin, margin),
  );

  @override
  bool operator ==(Object other) =>
      other is BoardMetrics &&
      other.outerSize == outerSize &&
      other.margin == margin &&
      other.labelFontSize == labelFontSize &&
      other.coordinates == coordinates &&
      other.showLabels == showLabels;

  @override
  int get hashCode =>
      Object.hash(outerSize, margin, labelFontSize, coordinates, showLabels);
}

/// Keeps the board square, sized to the smaller of the available width and
/// height.
///
/// * Under loose constraints the widget is exactly the square, so it never
///   takes space from its siblings.
/// * Under tight non-square constraints it fills them and centers the
///   square.
/// * Under unbounded constraints it uses the bounded side: the width in a
///   `Column` or vertical scroll view, the height in a `Row`. With no bounds
///   at all it uses [fallbackSize]. In a vertical scroll view on a wide,
///   short screen the board can be taller than the viewport.
///
/// It answers intrinsic size queries itself, so it works inside
/// `IntrinsicHeight` and similar widgets.
class BoardLayout extends StatelessWidget {
  /// Creates a square board layout.
  const BoardLayout({
    super.key,
    required this.coordinates,
    required this.builder,
    this.fallbackSize = kDefaultBoardSize,
  });

  /// Where labels go, which decides the margin.
  final CoordinateMode coordinates;

  /// Builds the board, which fills a square of `metrics.outerSize`.
  final Widget Function(BuildContext context, BoardMetrics metrics) builder;

  /// Side length when neither width nor height is bounded.
  final double fallbackSize;

  @override
  Widget build(BuildContext context) {
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    return _SquareBox(
      fallbackSize: fallbackSize,
      // The square box gives its child tight square constraints, so the
      // LayoutBuilder below only ever sees the final side length. Intrinsic
      // queries stop at the square box and never reach the LayoutBuilder.
      child: LayoutBuilder(
        builder: (context, constraints) => builder(
          context,
          BoardMetrics.forSide(
            constraints.maxWidth,
            coordinates,
            textScaler: textScaler,
          ),
        ),
      ),
    );
  }
}

/// Sizes itself as described on [BoardLayout] and centers a square child.
class _SquareBox extends SingleChildRenderObjectWidget {
  const _SquareBox({required this.fallbackSize, super.child});

  final double fallbackSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSquareBox(fallbackSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSquareBox renderObject) {
    renderObject.fallbackSize = fallbackSize;
  }
}

class _RenderSquareBox extends RenderShiftedBox {
  _RenderSquareBox(this._fallbackSize) : super(null);

  double _fallbackSize;
  set fallbackSize(double value) {
    if (value == _fallbackSize) return;
    _fallbackSize = value;
    markNeedsLayout();
  }

  // A square answers every intrinsic query with the extent it is given, or
  // the fallback when that extent is unbounded.
  double _intrinsic(double extent) => extent.isFinite ? extent : _fallbackSize;

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsic(height);

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsic(height);

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsic(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsic(width);

  Size _sizeFor(BoxConstraints constraints) {
    final side = BoardMetrics.resolveSide(constraints, fallback: _fallbackSize);
    return constraints.constrain(Size.square(side));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
    final child = this.child;
    if (child == null) return;
    final square = math.min(size.width, size.height);
    child.layout(BoxConstraints.tight(Size.square(square)));
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - square) / 2,
      (size.height - square) / 2,
    );
  }
}
