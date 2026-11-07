import 'package:flutter/foundation.dart';

import '../../controller/chess_board_controller.dart';
import '../../model/piece.dart';
import '../../model/square.dart';

/// A move queued on the opponent's turn, played when they have moved.
@immutable
class Premove {
  /// Creates a premove of the [color] piece on [from] to [to].
  const Premove({required this.from, required this.to, required this.color});

  /// Where the piece stands.
  final Square from;

  /// Where it goes. For castling this may be the king's target square or
  /// the rook's square, as the user chose; both resolve to castling.
  final Square to;

  /// The side the premove belongs to.
  final PieceColor color;

  @override
  bool operator ==(Object other) =>
      other is Premove &&
      other.from == from &&
      other.to == to &&
      other.color == color;

  @override
  int get hashCode => Object.hash(from, to, color);

  @override
  String toString() => 'Premove($from -> $to)';
}

const _knightSteps = [
  (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2), //
];
const _kingSteps = [
  (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1), //
];
const _rookDirs = [(1, 0), (0, 1), (-1, 0), (0, -1)];
const _bishopDirs = [(1, 1), (-1, 1), (-1, -1), (1, -1)];

/// Squares the piece on [from] may be premoved to.
///
/// Premoves are made before the opponent moves, so the position they will
/// be played in isn't known yet. The set therefore follows how the piece
/// moves, not what stands in its way: sliding pieces reach to the edge of
/// the board through other pieces, and pawns may premove a diagonal capture
/// onto an empty square. Squares held by the piece's own side count too,
/// so a recapture can be premoved onto a piece the opponent is about to
/// take, and a king can castle onto its rook. Whether the move is legal is
/// checked when it is played.
Set<Square> premoveDestinations(ChessBoardController c, Square from) {
  final piece = c.pieceAt(from);
  if (piece == null) return const {};
  final out = <Square>{};
  void add(int file, int rank) {
    if (file < 0 || file > 7 || rank < 0 || rank > 7) return;
    out.add(Square.at(file, rank));
  }

  void rays(List<(int, int)> dirs) {
    for (final (df, dr) in dirs) {
      for (var k = 1; k < 8; k++) {
        add(from.file + df * k, from.rank + dr * k);
      }
    }
  }

  switch (piece.type) {
    case PieceType.pawn:
      final dir = piece.color == PieceColor.white ? 1 : -1;
      final start = piece.color == PieceColor.white ? 1 : 6;
      add(from.file, from.rank + dir);
      if (from.rank == start) add(from.file, from.rank + 2 * dir);
      add(from.file - 1, from.rank + dir);
      add(from.file + 1, from.rank + dir);
    case PieceType.knight:
      for (final (df, dr) in _knightSteps) {
        add(from.file + df, from.rank + dr);
      }
    case PieceType.bishop:
      rays(_bishopDirs);
    case PieceType.rook:
      rays(_rookDirs);
    case PieceType.queen:
      rays([..._rookDirs, ..._bishopDirs]);
    case PieceType.king:
      for (final (df, dr) in _kingSteps) {
        add(from.file + df, from.rank + dr);
      }
      out.addAll(_castlingPremoves(c, from, piece.color));
  }
  return out;
}

/// The king's castling squares, and the rooks it can castle onto, for the
/// castling rights still held.
Set<Square> _castlingPremoves(
  ChessBoardController c,
  Square from,
  PieceColor color,
) {
  final homeRank = color == PieceColor.white ? 0 : 7;
  if (from != Square.at(4, homeRank)) return const {};
  final rights = c.fen.split(' ')[2];
  final rook = Piece(color, PieceType.rook);
  final out = <Square>{};
  final white = color == PieceColor.white;
  if (rights.contains(white ? 'K' : 'k') &&
      c.pieceAt(Square.at(7, homeRank)) == rook) {
    out
      ..add(Square.at(6, homeRank))
      ..add(Square.at(7, homeRank));
  }
  if (rights.contains(white ? 'Q' : 'q') &&
      c.pieceAt(Square.at(0, homeRank)) == rook) {
    out
      ..add(Square.at(2, homeRank))
      ..add(Square.at(0, homeRank));
  }
  return out;
}
