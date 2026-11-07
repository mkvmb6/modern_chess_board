import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'square.dart';

/// An arrow drawn on the board from one square to another.
///
/// Squares are given as names such as `e2`. Names that don't parse are
/// tolerated: the arrow resolves them to null and the board skips it.
///
/// Equality compares the names as given, so `Arrow('E2', 'e4')` and
/// `Arrow('e2', 'e4')` are different values even though they draw the same
/// arrow. Use lower-case names for consistent comparisons.
@immutable
class Arrow {
  /// Creates an arrow from [from] to [to], with an optional [color].
  ///
  /// When [color] is null, the board uses the theme's arrow color.
  const Arrow(this.from, this.to, {this.color});

  /// Creates an arrow from two [Square] values.
  Arrow.fromSquares(Square from, Square to, {Color? color})
    : this(from.name, to.name, color: color);

  /// Name of the starting square.
  final String from;

  /// Name of the ending square.
  final String to;

  /// Arrow color, or null to use the theme default.
  final Color? color;

  /// The starting square, or null if [from] is not a valid name.
  Square? get fromSquare => Square.tryParse(from);

  /// The ending square, or null if [to] is not a valid name.
  Square? get toSquare => Square.tryParse(to);

  /// Whether both ends are valid, distinct squares.
  bool get isValid {
    final a = fromSquare;
    final b = toSquare;
    return a != null && b != null && a != b;
  }

  @override
  bool operator ==(Object other) =>
      other is Arrow &&
      other.from == from &&
      other.to == to &&
      other.color == color;

  @override
  int get hashCode => Object.hash(from, to, color);

  @override
  String toString() => 'Arrow($from -> $to)';
}

/// How a [SquareMark] is drawn.
enum MarkShape {
  /// A ring inside the square.
  circle,

  /// A translucent fill over the whole square.
  fill,
}

/// A highlight on a single square, such as a circle drawn by the app.
@immutable
class SquareMark {
  /// Creates a mark on [square] with an optional [color] and [shape].
  const SquareMark(this.square, {this.color, this.shape = MarkShape.circle});

  /// Name of the marked square.
  final String square;

  /// Mark color, or null to use the theme default.
  final Color? color;

  /// How the mark is drawn.
  final MarkShape shape;

  /// The marked square, or null if [square] is not a valid name.
  Square? get markedSquare => Square.tryParse(square);

  @override
  bool operator ==(Object other) =>
      other is SquareMark &&
      other.square == square &&
      other.color == color &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(square, color, shape);

  @override
  String toString() => 'SquareMark($square, $shape)';
}
