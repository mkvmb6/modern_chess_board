import 'package:glados/glados.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/controller/move_classifier.dart';
import 'package:modern_chess_board/src/controller/notation.dart';

/// Starting positions that make rare move types likely in short random
/// games: promotions, castling (sometimes with check), en passant, and
/// endgames that reach draws.
const _starts = [
  kInitialFen,
  // Pawns one step from promotion for both sides, with pieces to capture.
  'r1n4k/1PPP4/8/8/8/8/1ppp4/R1N4K w - - 0 1',
  // Both sides ready to castle either way.
  'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
  // Castling can give check: open f-file to the black king.
  '5k2/8/8/8/8/8/8/R3K2R w KQ - 0 1',
  // En passant available immediately.
  '4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1',
  // Sparse endgame where captures quickly reach insufficient material.
  '4k3/8/3n4/8/8/2B5/8/4K3 w - - 0 1',
  // Halfmove clock close to the fifty-move limit.
  '4k3/8/8/8/8/8/R7/4K3 w - - 90 80',
];

/// Plays one random game and checks every move. Shared by the property test
/// and by quick fixed-seed runs when debugging.
void checkRandomGame(int seed, int start, int length) {
  final rng = Random(seed);
  final c = ChessBoardController(fen: _starts[start]);
  for (var i = 0; i < length && !c.isGameOver; i++) {
    final before = c.pieces;
    final moves = c.legalMoves;
    final pick = moves[rng.nextInt(moves.length)];
    expect(c.move(pick.from, pick.to, promotion: pick.promotion), isTrue);
    final m = c.lastMove!;
    final after = c.pieces;
    final mover = before[m.from]!;

    expect(m.piece, mover, reason: '$m');
    // The moved piece (or its promotion) is on the target square.
    expect(after[m.to]!.color, mover.color);
    expect(after[m.from], isNull);

    // Captures remove exactly one opposing piece, which is reported.
    expect(m.isCapture, after.length == before.length - 1);
    if (m.isEnPassant) {
      expect(before[m.to], isNull);
      final victim = Square.at(m.to.file, m.from.rank);
      expect(m.captured, before[victim]);
      expect(after[victim], isNull);
    } else if (m.isCapture) {
      expect(m.captured, before[m.to]);
    } else {
      expect(m.captured, isNull);
    }

    // Promotion: reported piece equals the piece now on the square.
    if (m.isPromotion) {
      expect(mover.type, PieceType.pawn);
      expect(after[m.to]!.type, m.promotion);
    } else {
      expect(after[m.to], mover);
    }

    // Castling: the king moved two files and the rook landed beside it.
    final twoFiles =
        mover.type == PieceType.king && (m.to.file - m.from.file).abs() == 2;
    expect(m.isCastle, twoFiles);
    if (m.castle case final CastleSide side) {
      final kingside = side == CastleSide.kingside;
      expect(m.to.file, kingside ? 6 : 2);
      final rookSquare = Square.at(kingside ? 5 : 3, m.from.rank);
      expect(after[rookSquare], Piece(mover.color, PieceType.rook));
    }

    // Check and mate agree with the resulting position.
    expect(m.isCheck, c.isCheck);
    expect(m.isCheckmate, c.isCheckmate);

    final expected = c.isGameOver
        ? SoundEvent.gameEnd
        : m.isPromotion
        ? SoundEvent.promotion
        : m.isCastle
        ? SoundEvent.castle
        : m.isCheck
        ? SoundEvent.check
        : m.isCapture
        ? SoundEvent.capture
        : SoundEvent.move;
    expect(classifyMove(m, c.status), expected);

    final text = describeMove(m, drawReason: c.drawReason);
    expect(
      text,
      startsWith(mover.color == PieceColor.white ? 'White' : 'Black'),
    );
    expect(text, isNot(contains('null')));
    if (c.isCheckmate) expect(text, endsWith('checkmate'));
    if (c.drawReason != null) expect(text, contains(','));
  }
}

void main() {
  // Plays random games and checks each move's description against what
  // actually changed on the board, then checks the sound event follows the
  // priority order. This tests the controller's move descriptions and the
  // classifier together.
  Glados3(
    any.intInRange(0, 1 << 30),
    any.intInRange(0, _starts.length),
    any.intInRange(1, 80),
  ).test(
    'move details match the board and sounds follow the priority order',
    checkRandomGame,
  );
}
