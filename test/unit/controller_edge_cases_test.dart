import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/controller/chess_board_controller.dart'
    show applyUserMove;

/// Plays a list of SAN moves, failing the test if any is illegal.
void play(ChessBoardController c, List<String> sans) {
  for (final san in sans) {
    expect(c.moveSan(san), isTrue, reason: 'illegal: $san');
  }
}

void main() {
  group('engine integrity', () {
    test('reading pgn after a promotion does not change the position', () {
      final c = ChessBoardController(fen: '8/P6k/8/8/8/8/8/K7 w - - 0 1');
      c.move(Square.a7, Square.a8, promotion: PieceType.queen);
      final fen = c.fen;
      expect(c.pgn, contains('a8=Q'));
      expect(c.engine.fen, fen);
      c.undo();
      c.move(Square.a7, Square.a8, promotion: PieceType.queen);
      expect(c.fen, fen);
      expect(c.engine.fen, fen);
    });
  });

  group('FEN sanitizing', () {
    test('castling rights without king and rook at home are rejected', () {
      final c = ChessBoardController();
      for (final bad in [
        '4k3/8/8/8/8/8/8/5K2 w K - 0 1', // no rook, king off e1
        '4k3/8/8/8/8/8/8/4K3 w K - 0 1', // king home, no rook
        '4k3/8/8/8/8/8/8/R3K3 w K - 0 1', // rook on the wrong side
        'r3k3/8/8/8/8/8/8/4K3 w k - 0 1', // black rook on the wrong side
      ]) {
        expect(c.loadFen(bad), isFalse, reason: bad);
      }
      expect(c.loadFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'), isTrue);
    });

    test('impossible en passant squares are rejected', () {
      final c = ChessBoardController();
      for (final bad in [
        '4k3/8/8/8/8/8/3P4/4K3 w - e3 0 1', // wrong rank for white to move
        '4k3/8/8/8/8/8/8/4K3 w - e6 0 1', // no black pawn on e5
        '4k3/4p3/8/4p3/8/8/8/4K3 w - e6 0 1', // origin square occupied
      ]) {
        expect(c.loadFen(bad), isFalse, reason: bad);
      }
      const ok = '4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1';
      expect(c.loadFen(ok), isTrue);
      expect(c.move(Square.d5, Square.e6), isTrue);
      expect(c.lastMove!.isEnPassant, isTrue);
    });

    test('startingFen is normalized', () {
      final c = ChessBoardController();
      expect(c.loadFen('4k3/8/8/8/8/8/8/4K2R   w  K - 0 1'), isTrue);
      expect(c.startingFen, '4k3/8/8/8/8/8/8/4K2R w K - 0 1');
    });
  });

  group('PGN parsing and writing', () {
    test('loadPgn rejects input that used to throw or print', () {
      final c = ChessBoardController();
      play(c, ['e4']);
      for (final bad in [
        '[FEN "garbage"]\n\n1. e4 *',
        '[FEN "8/8/8/8/8/8/8/8 w - - 0 1"]\n\n*',
      ]) {
        expect(c.loadPgn(bad), isFalse, reason: bad);
      }
      expect(c.history, hasLength(1));
    });

    test('loadPgn accepts leading blank lines before movetext', () {
      final c = ChessBoardController();
      expect(c.loadPgn('\n\n1. e4 e5 *'), isTrue);
      expect(c.halfMoveCount, 2);
      // The engine's own parser threw a RangeError on this input.
      expect(c.loadPgn('\n1. e4'), isTrue);
      expect(c.halfMoveCount, 1);
    });

    test('pgn round-trips from a FEN with black to move', () {
      const fen = '4k3/p7/8/8/8/8/P7/4K3 b - - 0 1';
      final a = ChessBoardController(fen: fen);
      play(a, ['Kd7', 'Kd2', 'Ke6']);
      expect(a.pgn, contains('[FEN "$fen"]'));
      expect(a.pgn, contains('1... Kd7 2. Kd2 Ke6'));
      final b = ChessBoardController();
      expect(b.loadPgn(a.pgn), isTrue);
      expect(b.fen, a.fen);
      expect(b.startingFen, fen);
      expect(b.history, a.history);
    });

    test('pgn round-trips a game with headers and no moves', () {
      final a = ChessBoardController();
      a.setPgnHeader('Event', 'Club');
      final b = ChessBoardController();
      play(b, ['e4']);
      expect(b.loadPgn(a.pgn), isTrue);
      expect(b.history, isEmpty);
      expect(b.pgnHeaders, {'Event': 'Club'});
    });

    test('loadPgn skips NAGs, semicolon comments and nested variations', () {
      final c = ChessBoardController();
      const pgn =
          '1. e4 \$1 e5 ; a comment\n'
          '2. Nf3 {main} (2. f4 exf4 (2... d5)) Nc6 3. Bb5 a6 *';
      expect(c.loadPgn(pgn), isTrue);
      expect(c.history.map((m) => m.san), [
        'e4',
        'e5',
        'Nf3',
        'Nc6',
        'Bb5',
        'a6',
      ]);
    });

    test('loadPgn reads escaped header values', () {
      final c = ChessBoardController();
      expect(c.loadPgn('[Event "The \\"Open\\""]\n\n*'), isTrue);
      expect(c.pgnHeaders['Event'], 'The "Open"');
    });

    test('setPgnHeader escapes values and rejects managed keys', () {
      final c = ChessBoardController();
      c.setPgnHeader('Event', 'The "Open"\nfinal');
      expect(c.pgn, contains('[Event "The \\"Open\\" final"]'));
      expect(() => c.setPgnHeader('FEN', 'x'), throwsArgumentError);
      expect(() => c.setPgnHeader('SetUp', '1'), throwsArgumentError);
      expect(() => c.setPgnHeader('Bad Key', 'x'), throwsArgumentError);
      expect(() => c.setPgnHeader('', 'x'), throwsArgumentError);
    });

    test('long games wrap movetext below 80 columns', () {
      final c = ChessBoardController();
      for (var i = 0; i < 6; i++) {
        play(c, ['Nf3', 'Nf6', 'Ng1', 'Ng8']);
        c.undo(); // avoid threefold so the game continues
        c.undo();
        c.undo();
        c.undo();
      }
      play(c, [
        'e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6', 'O-O', 'Be7', //
        'Re1', 'b5', 'Bb3', 'd6', 'c3', 'O-O', 'h3', 'Nb8', 'd4', 'Nbd7',
      ]);
      for (final line in c.pgn.split('\n')) {
        expect(line.length, lessThan(80), reason: line);
      }
      final copy = ChessBoardController();
      expect(copy.loadPgn(c.pgn), isTrue);
      expect(copy.fen, c.fen);
    });
  });

  group('game over', () {
    test('no moves are accepted after a draw by rule', () {
      final rep = ChessBoardController();
      play(rep, ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1', 'Ng8']);
      expect(rep.isGameOver, isTrue);
      expect(rep.move(Square.g1, Square.f3), isFalse);
      expect(rep.moveSan('e4'), isFalse);
      expect(applyUserMove(rep, Square.e2, Square.e4), isFalse);

      final bare = ChessBoardController(fen: '4k3/8/8/8/8/8/8/4K3 w - - 0 1');
      expect(bare.drawReason, DrawReason.insufficientMaterial);
      expect(bare.move(Square.e1, Square.d1), isFalse);

      final fifty = ChessBoardController(
        fen: '4k3/8/8/8/8/8/R7/4K3 w - - 99 80',
      );
      expect(fifty.moveSan('Ra3'), isTrue);
      expect(fifty.moveSan('Kd8'), isFalse);
    });

    test('undo after a draw by rule makes moves possible again', () {
      final c = ChessBoardController();
      play(c, ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1', 'Ng8']);
      expect(c.undo(), isTrue);
      expect(c.isGameOver, isFalse);
      expect(c.moveSan('Nc6'), isTrue);
    });
  });

  group('status and changes', () {
    test('a silent move is recorded as a silent MoveApplied', () {
      final c = ChessBoardController();
      c.move(Square.e2, Square.e4, notify: false);
      final change = c.lastChange;
      expect(change, isA<MoveApplied>());
      expect(change.silent, isTrue);
    });

    test('mate on the fiftieth move is a win, not a draw', () {
      final c = ChessBoardController(
        fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 99 80',
      );
      expect(c.moveSan('Ra8#'), isTrue);
      expect(c.status, GameStatus.checkmate);
      expect(c.drawReason, isNull);
      expect(c.result, GameResult.whiteWins);
    });

    test('repetition ignores an en passant square no pawn can use', () {
      final c = ChessBoardController();
      // After 1. e4 the FEN names e3, but no black pawn can capture there,
      // so that position repeats once the knights return.
      play(c, ['e4', 'Nf6', 'Nf3', 'Ng8', 'Ng1', 'Nf6', 'Nf3', 'Ng8']);
      expect(c.isDraw, isFalse);
      expect(c.moveSan('Ng1'), isTrue);
      expect(c.drawReason, DrawReason.threefoldRepetition);
    });

    test('moveSan accepts promotions without the equals sign', () {
      final c = ChessBoardController(fen: '8/P6k/8/8/8/8/8/K7 w - - 0 1');
      expect(c.moveSan('a8Q'), isTrue);
      expect(c.pieceAt(Square.a8), Piece.whiteQueen);
    });

    test('applyUserMove tags the move as a user move and notifies', () {
      final c = ChessBoardController();
      var notified = 0;
      c.addListener(() => notified++);
      expect(applyUserMove(c, Square.e2, Square.e4), isTrue);
      final change = c.lastChange as MoveApplied;
      expect(change.source, MoveSource.user);
      expect(change.silent, isFalse);
      expect(notified, 1);
      expect(applyUserMove(c, Square.e2, Square.e4), isFalse);
      expect(notified, 1);
    });
  });
}
