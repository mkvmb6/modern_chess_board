import 'package:flutter/foundation.dart';

import '../../model/board_move.dart';
import '../../model/piece.dart';
import '../../model/square.dart';

/// A piece sliding from one square to another during a move animation.
@immutable
class PieceSlide {
  /// Creates a slide.
  const PieceSlide(
    this.piece, {
    required this.from,
    required this.to,
    Piece? landsAs,
  }) : landsAs = landsAs ?? piece;

  /// The piece drawn while it moves.
  final Piece piece;

  /// Where it starts.
  final Square from;

  /// Where it ends.
  final Square to;

  /// The piece it becomes on arrival: the promotion piece for a pawn that
  /// promotes, otherwise [piece].
  final Piece landsAs;

  @override
  bool operator ==(Object other) =>
      other is PieceSlide &&
      other.piece == piece &&
      other.from == from &&
      other.to == to &&
      other.landsAs == landsAs;

  @override
  int get hashCode => Object.hash(piece, from, to, landsAs);

  @override
  String toString() => 'PieceSlide($piece $from->$to)';
}

/// A captured piece fading out where it stood.
@immutable
class PieceFade {
  /// Creates a fade.
  const PieceFade(this.piece, this.square);

  /// The captured piece.
  final Piece piece;

  /// Where it stood. For en passant, beside the capturing pawn's target.
  final Square square;

  @override
  bool operator ==(Object other) =>
      other is PieceFade && other.piece == piece && other.square == square;

  @override
  int get hashCode => Object.hash(piece, square);

  @override
  String toString() => 'PieceFade($piece on $square)';
}

/// What a move animation shows: pieces sliding and captured pieces fading.
@immutable
class MovePlan {
  /// Creates a plan.
  const MovePlan({
    required this.moving,
    required this.fading,
    this.appearing = const [],
  });

  /// The plan for [move], an applied move with flags filled in, given the
  /// pieces on the board just [before] it.
  factory MovePlan.forMove(
    BoardMove move, {
    required Map<Square, Piece> before,
  }) {
    final mover = before[move.from] ?? move.piece;
    if (mover == null) return const MovePlan(moving: [], fading: []);
    final landsAs = move.promotion == null
        ? mover
        : Piece(mover.color, move.promotion!);
    final moving = <PieceSlide>[];
    if (move.castle case final CastleSide side) {
      final rank = move.from.rank;
      final kingside = side == CastleSide.kingside;
      final rookFrom = Square.at(kingside ? 7 : 0, rank);
      final rookTo = Square.at(kingside ? 5 : 3, rank);
      final rook = before[rookFrom];
      if (rook != null) {
        moving.add(PieceSlide(rook, from: rookFrom, to: rookTo));
      }
    }
    // The mover last, so it is drawn on top: the king passes over the
    // rook when castling.
    moving.add(
      PieceSlide(mover, from: move.from, to: move.to, landsAs: landsAs),
    );
    final fading = <PieceFade>[];
    if (move.isCapture) {
      final square = move.isEnPassant
          ? Square.at(move.to.file, move.from.rank)
          : move.to;
      final captured = before[square];
      if (captured != null) fading.add(PieceFade(captured, square));
    }
    return MovePlan(
      moving: List.unmodifiable(moving),
      fading: List.unmodifiable(fading),
    );
  }

  /// The plan for taking [move] back, given the pieces [after] it was
  /// played: the mover slides home (a promoted piece travels back as the
  /// pawn), a castling rook slides home too, and a captured piece fades
  /// back in where it stood.
  factory MovePlan.forUndo(
    BoardMove move, {
    required Map<Square, Piece> after,
  }) {
    final landed = after[move.to];
    if (landed == null) return const MovePlan(moving: [], fading: []);
    final pawn = Piece(landed.color, PieceType.pawn);
    final mover = move.promotion == null ? landed : pawn;
    final moving = <PieceSlide>[];
    if (move.castle case final CastleSide side) {
      final rank = move.from.rank;
      final kingside = side == CastleSide.kingside;
      final rookHome = Square.at(kingside ? 7 : 0, rank);
      final rookNow = Square.at(kingside ? 5 : 3, rank);
      final rook = after[rookNow];
      if (rook != null) {
        moving.add(PieceSlide(rook, from: rookNow, to: rookHome));
      }
    }
    moving.add(PieceSlide(mover, from: move.to, to: move.from));
    final appearing = <PieceFade>[];
    if (move.captured case final Piece captured) {
      final square = move.isEnPassant
          ? Square.at(move.to.file, move.from.rank)
          : move.to;
      appearing.add(PieceFade(captured, square));
    }
    return MovePlan(
      moving: List.unmodifiable(moving),
      fading: const [],
      appearing: List.unmodifiable(appearing),
    );
  }

  /// Pieces sliding into place.
  final List<PieceSlide> moving;

  /// Pieces fading back in, such as a capture being taken back.
  final List<PieceFade> appearing;

  /// Captured pieces fading out.
  final List<PieceFade> fading;

  /// Squares whose final piece is drawn by the animation, so the pieces
  /// layer leaves them empty until it ends. A piece never shows twice.
  Set<Square> get animatedSquares => {
    for (final s in moving) s.to,
    for (final a in appearing) a.square,
  };

  /// Whether there is nothing to animate.
  bool get isEmpty => moving.isEmpty && fading.isEmpty && appearing.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is MovePlan &&
      listEquals(other.moving, moving) &&
      listEquals(other.fading, fading) &&
      listEquals(other.appearing, appearing);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(moving),
    Object.hashAll(fading),
    Object.hashAll(appearing),
  );
}
