import '../model/board_move.dart';
import '../model/game_status.dart';

/// Picks the single sound event for [move], an applied move with its flags
/// filled in, given the [status] of the position it led to.
///
/// Priority, highest first: game end, promotion, castling, check, capture
/// (en passant included), then a plain move. Never returns
/// [SoundEvent.illegal]; the board sends that for rejected input itself.
SoundEvent classifyMove(BoardMove move, GameStatus status) {
  if (status.isGameOver) return SoundEvent.gameEnd;
  if (move.isPromotion) return SoundEvent.promotion;
  if (move.isCastle) return SoundEvent.castle;
  if (move.isCheck) return SoundEvent.check;
  if (move.isCapture) return SoundEvent.capture;
  return SoundEvent.move;
}
