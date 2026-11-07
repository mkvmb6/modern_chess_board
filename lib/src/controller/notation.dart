import '../model/board_move.dart';
import '../model/game_status.dart';
import '../model/piece.dart';

/// Describes [move] in plain English for screen readers, such as
/// "White knight to f3, check" or "Black castles queenside".
///
/// [move] should be an applied move from the controller, so it carries the
/// moved piece, SAN and flags. Pass the resulting position's [drawReason] to
/// announce draws. When two pieces of the same kind could have made the
/// move, the origin square is included ("White knight from b1 to d2"). A
/// bare request without piece information reads as "e2 to e4".
///
/// The board uses this by default; apps can supply their own announcer to
/// localize it.
String describeMove(BoardMove move, {DrawReason? drawReason}) {
  final parts = <String>[_action(move)];
  if (move.promotion case final PieceType p) parts.add('promotes to ${p.name}');
  if (move.isCheckmate) {
    parts.add('checkmate');
  } else {
    // Keep the check even when the move also draws, as in perpetual check.
    if (move.isCheck) parts.add('check');
    if (drawReason != null) parts.add(_drawText(drawReason));
  }
  return parts.join(', ');
}

String _action(BoardMove move) {
  final piece = move.piece;
  if (piece == null) return '${move.from.name} to ${move.to.name}';

  final side = _capitalize(piece.color.name);
  if (move.castle case final CastleSide wing) {
    return '$side castles ${wing == CastleSide.kingside ? 'kingside' : 'queenside'}';
  }

  final from = _isDisambiguated(move) ? ' from ${move.from.name}' : '';
  final mover = '$side ${piece.type.name}$from';
  final captured = move.captured;
  if (captured == null) return '$mover to ${move.to.name}';
  if (move.isEnPassant) {
    return '$mover takes ${captured.label} en passant, to ${move.to.name}';
  }
  return '$mover takes ${captured.label} on ${move.to.name}';
}

/// Whether the SAN names the origin file or rank to tell two pieces apart,
/// as in `Nbd2`, `R1e2` or `Qh4e1`. Pawn captures (`exd5`) always name the
/// file, so they don't count.
bool _isDisambiguated(BoardMove move) {
  final san = move.san;
  if (san == null || move.piece?.type == PieceType.pawn) return false;
  // Strip the piece letter, capture mark, destination and suffixes; what is
  // left is the disambiguator.
  final core = san.replaceAll(RegExp(r'[+#!?]+$'), '');
  final match = RegExp(r'^[NBRQK]([a-h]?[1-8]?)x?[a-h][1-8]$').firstMatch(core);
  return match != null && match.group(1)!.isNotEmpty;
}

String _drawText(DrawReason reason) => switch (reason) {
  DrawReason.stalemate => 'stalemate',
  DrawReason.fiftyMoveRule => 'draw by the fifty-move rule',
  DrawReason.threefoldRepetition => 'draw by threefold repetition',
  DrawReason.insufficientMaterial => 'draw by insufficient material',
};

String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);
