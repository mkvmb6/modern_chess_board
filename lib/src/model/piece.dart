import 'package:flutter/foundation.dart';

/// The side a piece belongs to.
enum PieceColor {
  /// White, moves first.
  white,

  /// Black.
  black;

  /// The other color.
  PieceColor get opposite => this == white ? black : white;

  /// `w` or `b`, as used in FEN and piece codes.
  String get letter => this == white ? 'w' : 'b';

  /// The color for `w` or `b`, or null for anything else.
  static PieceColor? fromLetter(String letter) => switch (letter) {
    'w' => white,
    'b' => black,
    _ => null,
  };
}

/// The kind of a chess piece.
enum PieceType {
  /// Pawn.
  pawn('p'),

  /// Knight.
  knight('n'),

  /// Bishop.
  bishop('b'),

  /// Rook.
  rook('r'),

  /// Queen.
  queen('q'),

  /// King.
  king('k');

  const PieceType(this.letter);

  /// Lower-case letter used in FEN and UCI (`p`, `n`, `b`, `r`, `q`, `k`).
  final String letter;

  /// The type for an ASCII FEN/SAN letter in either case (`n` or `N`), or
  /// null for anything else.
  static PieceType? fromLetter(String letter) {
    for (final t in values) {
      if (letter == t.letter || letter == t.letter.toUpperCase()) return t;
    }
    return null;
  }
}

/// A chess piece: a [color] and a [type].
@immutable
class Piece {
  /// Creates a piece.
  const Piece(this.color, this.type);

  /// The side the piece belongs to.
  final PieceColor color;

  /// What kind of piece it is.
  final PieceType type;

  /// White king.
  static const whiteKing = Piece(PieceColor.white, PieceType.king);

  /// White queen.
  static const whiteQueen = Piece(PieceColor.white, PieceType.queen);

  /// White rook.
  static const whiteRook = Piece(PieceColor.white, PieceType.rook);

  /// White bishop.
  static const whiteBishop = Piece(PieceColor.white, PieceType.bishop);

  /// White knight.
  static const whiteKnight = Piece(PieceColor.white, PieceType.knight);

  /// White pawn.
  static const whitePawn = Piece(PieceColor.white, PieceType.pawn);

  /// Black king.
  static const blackKing = Piece(PieceColor.black, PieceType.king);

  /// Black queen.
  static const blackQueen = Piece(PieceColor.black, PieceType.queen);

  /// Black rook.
  static const blackRook = Piece(PieceColor.black, PieceType.rook);

  /// Black bishop.
  static const blackBishop = Piece(PieceColor.black, PieceType.bishop);

  /// Black knight.
  static const blackKnight = Piece(PieceColor.black, PieceType.knight);

  /// Black pawn.
  static const blackPawn = Piece(PieceColor.black, PieceType.pawn);

  /// All 12 pieces, white first, each color ordered king to pawn.
  static const List<Piece> values = [
    whiteKing, whiteQueen, whiteRook, whiteBishop, whiteKnight, whitePawn, //
    blackKing, blackQueen, blackRook, blackBishop, blackKnight, blackPawn,
  ];

  /// Two-letter code such as `wK` or `bN`, matching the asset file names.
  String get code => '${color.letter}${type.letter.toUpperCase()}';

  /// Human-readable name such as `white king`, used for accessibility.
  String get label => '${color.name} ${type.name}';

  /// Parses a code such as `wK`. Throws a [FormatException] if invalid.
  static Piece fromCode(String code) {
    final piece = tryFromCode(code);
    if (piece == null) throw FormatException('Not a piece code', code);
    return piece;
  }

  /// Parses a code such as `wK`, returning null if invalid.
  static Piece? tryFromCode(String code) {
    if (code.length != 2) return null;
    final color = PieceColor.fromLetter(code[0]);
    final upper = code[1];
    if (color == null || upper != upper.toUpperCase()) return null;
    final type = PieceType.fromLetter(upper);
    return type == null ? null : Piece(color, type);
  }

  @override
  bool operator ==(Object other) =>
      other is Piece && other.color == color && other.type == type;

  @override
  int get hashCode => Object.hash(color, type);

  @override
  String toString() => code;
}
