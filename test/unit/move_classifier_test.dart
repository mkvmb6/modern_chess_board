import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/controller/move_classifier.dart';

/// Loads [fen], plays [san], and returns the sound event for that move.
SoundEvent eventFor(String fen, String san) {
  final c = ChessBoardController(fen: fen);
  expect(c.moveSan(san), isTrue, reason: san);
  return classifyMove(c.lastMove!, c.status);
}

void main() {
  group('single events', () {
    test('quiet move', () {
      expect(eventFor(kInitialFen, 'e4'), SoundEvent.move);
      expect(eventFor(kInitialFen, 'Nf3'), SoundEvent.move);
    });

    test('capture', () {
      const fen = '4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1';
      expect(eventFor(fen, 'exd5'), SoundEvent.capture);
    });

    test('en passant counts as a capture', () {
      const fen = '4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1';
      expect(eventFor(fen, 'dxe6'), SoundEvent.capture);
    });

    test('check', () {
      const fen = '4k3/8/8/8/8/8/8/R3K3 w - - 0 1';
      expect(eventFor(fen, 'Ra8+'), SoundEvent.check);
    });

    test('castling both ways', () {
      const fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
      expect(eventFor(fen, 'O-O'), SoundEvent.castle);
      expect(eventFor(fen, 'O-O-O'), SoundEvent.castle);
    });

    test('promotion', () {
      const fen = '7k/P6p/8/8/8/8/7P/K7 w - - 0 1';
      expect(eventFor(fen, 'a8=N'), SoundEvent.promotion);
    });

    test('checkmate ends the game', () {
      const fen =
          'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2';
      expect(eventFor(fen, 'Qh4#'), SoundEvent.gameEnd);
    });

    test('stalemate ends the game', () {
      const fen = 'k7/8/1K6/8/8/8/8/2Q5 w - - 0 1';
      expect(eventFor(fen, 'Qc7'), SoundEvent.gameEnd);
    });

    test('a draw by insufficient material ends the game', () {
      const fen = '4k3/8/8/8/8/8/3r4/4K1N1 w - - 0 1';
      expect(eventFor(fen, 'Kxd2'), SoundEvent.gameEnd);
    });
  });

  group('priority when several apply', () {
    test('promotion beats capture and check', () {
      // b7xa8=Q captures a rook and gives check along the back rank.
      const fen = 'r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1';
      final c = ChessBoardController(fen: fen);
      c.moveSan('bxa8=Q+');
      final m = c.lastMove!;
      expect(m.isPromotion && m.isCapture && m.isCheck, isTrue);
      expect(classifyMove(m, c.status), SoundEvent.promotion);
    });

    test('game end beats promotion', () {
      // Promoting with mate.
      const fen = '7k/P5R1/6K1/8/8/8/8/8 w - - 0 1';
      final c = ChessBoardController(fen: fen);
      expect(c.moveSan('a8=Q#'), isTrue);
      expect(c.lastMove!.isPromotion, isTrue);
      expect(classifyMove(c.lastMove!, c.status), SoundEvent.gameEnd);
    });

    test('game end beats a promotion that captures and mates', () {
      const fen = '1r5k/P5R1/6K1/8/8/8/8/8 w - - 0 1';
      final c = ChessBoardController(fen: fen);
      expect(c.moveSan('axb8=Q#'), isTrue);
      final m = c.lastMove!;
      expect(m.isPromotion && m.isCapture && m.isCheckmate, isTrue);
      expect(classifyMove(m, c.status), SoundEvent.gameEnd);
    });

    test('game end for draws by repetition and the fifty-move rule', () {
      final rep = ChessBoardController(fen: '7k/8/6Q1/8/8/8/8/K7 w - - 0 1');
      for (final san in ['Qh6+', 'Kg8', 'Qg6+', 'Kh8', 'Qh6+', 'Kg8', 'Qg6+']) {
        expect(rep.moveSan(san), isTrue);
      }
      expect(rep.moveSan('Kh8'), isTrue);
      expect(rep.drawReason, DrawReason.threefoldRepetition);
      expect(classifyMove(rep.lastMove!, rep.status), SoundEvent.gameEnd);

      final fifty = ChessBoardController(
        fen: '4k3/8/8/8/8/8/R7/4K3 w - - 99 80',
      );
      expect(fifty.moveSan('Ra3'), isTrue);
      expect(fifty.drawReason, DrawReason.fiftyMoveRule);
      expect(classifyMove(fifty.lastMove!, fifty.status), SoundEvent.gameEnd);
    });

    test('castle beats check', () {
      // O-O puts the rook on f1, checking the king on f8.
      const fen = '5k2/8/8/8/8/8/8/4K2R w K - 0 1';
      final c = ChessBoardController(fen: fen);
      expect(c.moveSan('O-O+'), isTrue);
      expect(c.lastMove!.isCheck, isTrue);
      expect(classifyMove(c.lastMove!, c.status), SoundEvent.castle);
    });

    test('check beats capture', () {
      const fen = '4k3/8/8/8/8/8/4r3/4RK2 w - - 0 1';
      final c = ChessBoardController(fen: fen);
      expect(c.moveSan('Rxe2+'), isTrue);
      expect(c.lastMove!.isCapture, isTrue);
      expect(classifyMove(c.lastMove!, c.status), SoundEvent.check);
    });

    test('game end beats capture', () {
      const fen = '4k3/8/8/8/8/8/3r4/4K1N1 w - - 0 1';
      final c = ChessBoardController(fen: fen);
      c.moveSan('Kxd2');
      expect(c.lastMove!.isCapture, isTrue);
      expect(classifyMove(c.lastMove!, c.status), SoundEvent.gameEnd);
    });
  });

  test('never returns the illegal event for an applied move', () {
    for (final status in GameStatus.values) {
      final e = classifyMove(
        const BoardMove(from: Square.e2, to: Square.e4),
        status,
      );
      expect(e, isNot(SoundEvent.illegal));
    }
  });
}
