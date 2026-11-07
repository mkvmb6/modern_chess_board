import 'package:glados/glados.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

/// Plays up to [length] random legal moves chosen by [rng].
void playRandom(ChessBoardController c, Random rng, int length) {
  for (var i = 0; i < length && !c.isGameOver; i++) {
    final moves = c.legalMoves;
    final m = moves[rng.nextInt(moves.length)];
    expect(c.move(m.from, m.to, promotion: m.promotion), isTrue);
  }
}

/// FEN after replaying the first [ply] moves of [line] on a fresh board.
String replayFen(List<BoardMove> line, int ply) {
  final c = ChessBoardController();
  for (final m in line.take(ply)) {
    expect(c.move(m.from, m.to, promotion: m.promotion), isTrue);
  }
  return c.fen;
}

void main() {
  Glados3(
    any.intInRange(0, 1 << 30),
    any.intInRange(0, 40),
    any.list(any.intInRange(0, 6)),
  ).test('random navigation, branching and undo always match a replay', (
    seed,
    length,
    steps,
  ) {
    final rng = Random(seed);
    final c = ChessBoardController(allowBranching: true);
    playRandom(c, rng, length);

    for (final step in steps) {
      final lineBefore = c.fullLine;
      final plyBefore = c.ply;
      switch (step) {
        case 0:
          c.back();
        case 1:
          c.forward();
        case 2:
          c.goTo(rng.nextInt(c.fullLine.length + 1));
        case 3:
          rng.nextBool() ? c.goToStart() : c.goToEnd();
        case 4:
          // A move from wherever the view is, branching if needed.
          playRandom(c, rng, 1);
        default:
          c.undo();
      }

      final line = c.fullLine;
      expect(c.fen, replayFen(line, c.ply), reason: 'ply ${c.ply}');
      expect(c.history, line.take(c.ply).toList());
      expect(c.halfMoveCount, line.length);
      if (step <= 3) {
        expect(line, lineBefore, reason: 'navigation never changes moves');
      }
      if (step == 4 && line.length != lineBefore.length) {
        // A branch keeps the moves up to the view and adds one.
        expect(line.take(plyBefore), lineBefore.take(plyBefore));
      }
    }
  });
}
