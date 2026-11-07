import 'package:flutter/foundation.dart';

import 'piece.dart';
import 'square.dart';

/// Which side a castling move goes to.
enum CastleSide {
  /// Short castling (O-O).
  kingside,

  /// Long castling (O-O-O).
  queenside,
}

/// A chess move.
///
/// A move requested by the app only needs [from], [to] and, for pawns
/// reaching the last rank, [promotion]. Moves reported by the controller
/// after being applied also carry the moved [piece], [san], [captured]
/// piece and the flags describing what happened.
///
/// Equality compares every field, so a bare request such as
/// `BoardMove(from: Square.e2, to: Square.e4)` does not equal the applied
/// move the controller reports. Compare [uci] to match moves by squares and
/// promotion only.
@immutable
class BoardMove {
  /// Creates a move.
  const BoardMove({
    required this.from,
    required this.to,
    this.promotion,
    this.piece,
    this.san,
    this.captured,
    this.castle,
    this.isEnPassant = false,
    this.isCheck = false,
    this.isCheckmate = false,
  }) : assert(!isCheckmate || isCheck, 'A checkmate is also a check');

  /// The square the piece moves from.
  final Square from;

  /// The square the piece moves to. For castling this is the king's
  /// destination.
  final Square to;

  /// The piece a pawn promotes to, if any.
  final PieceType? promotion;

  /// The piece that moved, when known.
  final Piece? piece;

  /// Standard algebraic notation such as `Nf3` or `exd8=Q+`, when known.
  final String? san;

  /// The piece that was captured, if any. Set for en passant too.
  final Piece? captured;

  /// The castling side, if this move castles.
  final CastleSide? castle;

  /// Whether this move captured en passant.
  final bool isEnPassant;

  /// Whether this move gives check (including mate).
  final bool isCheck;

  /// Whether this move gives checkmate.
  final bool isCheckmate;

  /// Whether this move captures a piece.
  bool get isCapture => captured != null;

  /// Whether this move castles.
  bool get isCastle => castle != null;

  /// Whether this move promotes a pawn.
  bool get isPromotion => promotion != null;

  /// UCI notation such as `e2e4` or `a7a8q`.
  String get uci => '${from.name}${to.name}${promotion?.letter ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is BoardMove &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion &&
      other.piece == piece &&
      other.san == san &&
      other.captured == captured &&
      other.castle == castle &&
      other.isEnPassant == isEnPassant &&
      other.isCheck == isCheck &&
      other.isCheckmate == isCheckmate;

  @override
  int get hashCode => Object.hash(
    from,
    to,
    promotion,
    piece,
    san,
    captured,
    castle,
    isEnPassant,
    isCheck,
    isCheckmate,
  );

  @override
  String toString() =>
      san == null ? 'BoardMove($uci)' : 'BoardMove($uci, san: $san)';
}
