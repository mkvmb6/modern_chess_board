import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

/// Counts listener notifications on [c].
int Function() countNotifications(ChessBoardController c) {
  var n = 0;
  c.addListener(() => n++);
  return () => n;
}

/// Plays a list of SAN moves, failing the test if any is illegal.
void play(ChessBoardController c, List<String> sans) {
  for (final san in sans) {
    expect(c.moveSan(san), isTrue, reason: 'illegal: $san');
  }
}

void main() {
  group('initial state', () {
    test('starts at the standard position', () {
      final c = ChessBoardController();
      expect(c.fen, kInitialFen);
      expect(c.startingFen, kInitialFen);
      expect(c.turn, PieceColor.white);
      expect(c.status, GameStatus.ongoing);
      expect(c.result, GameResult.ongoing);
      expect(c.history, isEmpty);
      expect(c.lastMove, isNull);
      expect(c.halfMoveCount, 0);
      expect(c.legalMoves, hasLength(20));
      expect(c.pieces, hasLength(32));
      expect(c.pieceAt(Square.e1), Piece.whiteKing);
      expect(c.pieceAt(Square.e4), isNull);
    });

    test('accepts a starting FEN', () {
      const fen = '4k3/8/8/8/8/8/8/4K2R w K - 0 1';
      final c = ChessBoardController(fen: fen);
      expect(c.fen, fen);
      expect(c.startingFen, fen);
    });

    test('throws ArgumentError on an invalid starting FEN', () {
      expect(() => ChessBoardController(fen: 'nonsense'), throwsArgumentError);
    });
  });

  group('move legality', () {
    test('applies legal moves and rejects illegal ones', () {
      final c = ChessBoardController();
      expect(c.move(Square.e2, Square.e5), isFalse);
      expect(c.move(Square.e7, Square.e5), isFalse, reason: 'not black turn');
      expect(c.move(Square.e4, Square.e5), isFalse, reason: 'empty square');
      expect(c.fen, kInitialFen);

      expect(c.move(Square.e2, Square.e4), isTrue);
      expect(c.turn, PieceColor.black);
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
      expect(c.halfMoveCount, 1);
      expect(c.lastMove!.san, 'e4');
      expect(c.lastMove!.piece, Piece.whitePawn);
    });

    test('legalMovesFrom lists moves for one square', () {
      final c = ChessBoardController();
      final knight = c.legalMovesFrom(Square.g1).map((m) => m.to).toSet();
      expect(knight, {Square.f3, Square.h3});
      expect(c.legalMovesFrom(Square.e4), isEmpty);
      expect(c.legalMovesFrom(Square.e7), isEmpty, reason: 'not black turn');
    });

    test('a move into check is rejected', () {
      // White king on e1 pinned rook on e2 by black rook on e8.
      final c = ChessBoardController(fen: '4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1');
      expect(c.move(Square.e2, Square.d2), isFalse);
      expect(c.move(Square.e2, Square.e5), isTrue);
    });

    test('moveSan accepts optional suffixes and zero castling', () {
      final c = ChessBoardController();
      expect(c.moveSan('Nf3!'), isTrue);
      expect(c.moveSan('Nf6?!'), isTrue);
      expect(c.moveSan('g3'), isTrue);
      expect(c.moveSan('g6'), isTrue);
      expect(c.moveSan('Bg2'), isTrue);
      expect(c.moveSan('Bg7'), isTrue);
      expect(c.moveSan('0-0'), isTrue);
      expect(c.lastMove!.castle, CastleSide.kingside);
      expect(c.moveSan('Qxd8'), isFalse);
      expect(c.moveSan(''), isFalse);
      expect(c.moveSan('nonsense'), isFalse);
    });
  });

  group('special moves', () {
    test('promotion requires a piece and applies the chosen one', () {
      final c = ChessBoardController(fen: '8/P6k/8/8/8/8/8/K7 w - - 0 1');
      expect(c.move(Square.a7, Square.a8), isFalse);
      expect(c.fen, '8/P6k/8/8/8/8/8/K7 w - - 0 1');

      expect(c.move(Square.a7, Square.a8, promotion: PieceType.knight), isTrue);
      expect(c.pieceAt(Square.a8), Piece.whiteKnight);
      expect(c.lastMove!.promotion, PieceType.knight);
      expect(c.lastMove!.isPromotion, isTrue);
      expect(c.lastMove!.san, 'a8=N');
    });

    test('promotion is ignored for moves that do not promote', () {
      final c = ChessBoardController();
      expect(c.move(Square.e2, Square.e4, promotion: PieceType.queen), isTrue);
      expect(c.lastMove!.promotion, isNull);
    });

    test('promotion moves are listed once per piece', () {
      final c = ChessBoardController(fen: '8/P6k/8/8/8/8/8/K7 w - - 0 1');
      final promos = c
          .legalMovesFrom(Square.a7)
          .map((m) => m.promotion)
          .toSet();
      expect(promos, {
        PieceType.queen,
        PieceType.rook,
        PieceType.bishop,
        PieceType.knight,
      });
    });

    test('castling both sides is flagged and moves the rook', () {
      const fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
      final c = ChessBoardController(fen: fen);
      expect(c.move(Square.e1, Square.g1), isTrue);
      expect(c.lastMove!.castle, CastleSide.kingside);
      expect(c.pieceAt(Square.f1), Piece.whiteRook);
      expect(c.pieceAt(Square.h1), isNull);

      expect(c.move(Square.e8, Square.c8), isTrue);
      expect(c.lastMove!.castle, CastleSide.queenside);
      expect(c.pieceAt(Square.d8), Piece.blackRook);
      expect(c.pieceAt(Square.a8), isNull);
    });

    test('en passant is flagged as a capture of a pawn', () {
      final c = ChessBoardController();
      play(c, ['e4', 'a6', 'e5', 'd5']);
      expect(c.move(Square.e5, Square.d6), isTrue);
      final m = c.lastMove!;
      expect(m.isEnPassant, isTrue);
      expect(m.isCapture, isTrue);
      expect(m.captured, Piece.blackPawn);
      expect(c.pieceAt(Square.d5), isNull);
    });

    test('captures record the captured piece with the opponent color', () {
      final c = ChessBoardController();
      play(c, ['e4', 'd5']);
      expect(c.move(Square.e4, Square.d5), isTrue);
      expect(c.lastMove!.captured, Piece.blackPawn);
    });

    test('check and mate flags', () {
      final c = ChessBoardController();
      play(c, ['f3', 'e5', 'g4']);
      expect(c.isCheck, isFalse);
      expect(c.moveSan('Qh4'), isTrue);
      final m = c.lastMove!;
      expect(m.isCheck, isTrue);
      expect(m.isCheckmate, isTrue);
      expect(m.san, 'Qh4#');
    });
  });

  group('game end', () {
    test('checkmate', () {
      final c = ChessBoardController();
      play(c, ['f3', 'e5', 'g4', 'Qh4#']);
      expect(c.isCheck, isTrue);
      expect(c.isCheckmate, isTrue);
      expect(c.isGameOver, isTrue);
      expect(c.isDraw, isFalse);
      expect(c.drawReason, isNull);
      expect(c.status, GameStatus.checkmate);
      expect(c.result, GameResult.blackWins);
      expect(c.legalMoves, isEmpty);
    });

    test('stalemate', () {
      final c = ChessBoardController(fen: '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(c.isStalemate, isTrue);
      expect(c.isCheck, isFalse);
      expect(c.isDraw, isTrue);
      expect(c.drawReason, DrawReason.stalemate);
      expect(c.status, GameStatus.stalemate);
      expect(c.result, GameResult.draw);
    });

    test('insufficient material', () {
      final c = ChessBoardController(fen: '8/8/8/4k3/8/8/8/4K1N1 w - - 0 1');
      expect(c.drawReason, DrawReason.insufficientMaterial);
      expect(c.status, GameStatus.draw);
      expect(c.isGameOver, isTrue);
    });

    test('threefold repetition', () {
      final c = ChessBoardController();
      play(c, ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1']);
      expect(c.isDraw, isFalse);
      expect(c.moveSan('Ng8'), isTrue);
      expect(c.drawReason, DrawReason.threefoldRepetition);
      expect(c.status, GameStatus.draw);
      expect(c.result, GameResult.draw);
    });

    test('fifty-move rule', () {
      final c = ChessBoardController(fen: '8/8/8/4k3/8/8/R7/4K3 w - - 99 80');
      expect(c.isDraw, isFalse);
      expect(c.move(Square.a2, Square.b2), isTrue);
      expect(c.drawReason, DrawReason.fiftyMoveRule);
      expect(c.status, GameStatus.draw);
    });
  });

  group('undo, reset and FEN', () {
    test('undo takes back the last move', () {
      final c = ChessBoardController();
      play(c, ['e4', 'e5']);
      expect(c.undo(), isTrue);
      expect(c.halfMoveCount, 1);
      expect(c.turn, PieceColor.black);
      expect(c.pieceAt(Square.e5), isNull);
      expect(c.undo(), isTrue);
      expect(c.fen, kInitialFen);
    });

    test('undo with no moves does nothing and does not notify', () {
      final c = ChessBoardController();
      final count = countNotifications(c);
      final id = c.changeId;
      expect(c.undo(), isFalse);
      expect(count(), 0);
      expect(c.changeId, id);
    });

    test('undo clears a draw by repetition', () {
      final c = ChessBoardController();
      play(c, ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1', 'Ng8']);
      expect(c.isDraw, isTrue);
      c.undo();
      expect(c.isDraw, isFalse);
    });

    test('reset returns to the start and clears headers', () {
      final c = ChessBoardController(fen: '8/8/8/4k3/8/8/R7/4K3 w - - 0 1');
      c.setPgnHeader('White', 'Ann');
      c.move(Square.a2, Square.a3);
      c.reset();
      expect(c.fen, kInitialFen);
      expect(c.startingFen, kInitialFen);
      expect(c.history, isEmpty);
      expect(c.pgnHeaders, isEmpty);
    });

    test('loadFen replaces the game', () {
      final c = ChessBoardController();
      play(c, ['e4']);
      const fen = '4k3/8/8/8/8/8/8/4K2R w K - 0 1';
      expect(c.loadFen(fen), isTrue);
      expect(c.fen, fen);
      expect(c.startingFen, fen);
      expect(c.history, isEmpty);
    });

    test('loadFen tolerates surrounding whitespace', () {
      final c = ChessBoardController();
      expect(c.loadFen('  $kInitialFen \n'), isTrue);
      expect(c.fen, kInitialFen);
    });

    test('invalid FEN is rejected and leaves the game unchanged', () {
      final c = ChessBoardController();
      play(c, ['e4']);
      final before = c.fen;
      final count = countNotifications(c);
      for (final bad in [
        '',
        'nonsense',
        '8/8/8/8/8/8/8/8 w - - 0 1', // no kings
        '4k3/8/8/8/8/8/8/8 w - - 0 1', // no white king
        'kk6/8/8/8/8/8/8/4K3 w - - 0 1', // two black kings
        '4k3/8/8/8/8/8/8/4K3 w - -', // missing fields
        'P3k3/8/8/8/8/8/8/4K3 w - - 0 1', // pawn on back rank
        '4k3/8/8/8/8/8/8/4R1K1 w - - 0 1', // black in check, white to move
      ]) {
        expect(c.loadFen(bad), isFalse, reason: bad);
      }
      expect(c.fen, before);
      expect(c.history, hasLength(1));
      expect(count(), 0);
    });
  });

  group('PGN', () {
    test('pgn includes moves, headers and the result when over', () {
      final c = ChessBoardController();
      c.setPgnHeader('White', 'Ann');
      play(c, ['f3', 'e5', 'g4', 'Qh4#']);
      final pgn = c.pgn;
      expect(pgn, contains('[White "Ann"]'));
      expect(pgn, contains('[Result "0-1"]'));
      expect(pgn, contains('1. f3 e5 2. g4 Qh4# 0-1'));
    });

    test('setPgnHeader with null removes a header', () {
      final c = ChessBoardController();
      c.setPgnHeader('Event', 'Club');
      c.setPgnHeader('Event', null);
      expect(c.pgnHeaders, isEmpty);
      expect(c.pgn, isNot(contains('Event')));
    });

    test('loadPgn replays the game with headers and flags', () {
      final c = ChessBoardController();
      expect(
        c.loadPgn('[White "A"]\n[Black "B"]\n\n1. e4 e5 2. Nf3 Nc6 *'),
        isTrue,
      );
      expect(c.halfMoveCount, 4);
      expect(c.history.map((m) => m.san), ['e4', 'e5', 'Nf3', 'Nc6']);
      expect(c.history[2].piece, Piece.whiteKnight);
      expect(c.pgnHeaders, {'White': 'A', 'Black': 'B'});
      expect(c.turn, PieceColor.white);
    });

    test('loadPgn supports a FEN header', () {
      final c = ChessBoardController();
      const fen = '4k3/8/8/8/8/8/8/4K2R w K - 0 1';
      expect(c.loadPgn('[SetUp "1"]\n[FEN "$fen"]\n\n1. O-O *'), isTrue);
      expect(c.startingFen, fen);
      expect(c.lastMove!.castle, CastleSide.kingside);
      expect(c.pgnHeaders, isNot(contains('FEN')));
    });

    test('pgn round-trips through loadPgn', () {
      final a = ChessBoardController();
      play(a, ['d4', 'd5', 'c4', 'dxc4', 'e4', 'b5']);
      final b = ChessBoardController();
      expect(b.loadPgn(a.pgn), isTrue);
      expect(b.fen, a.fen);
      expect(b.history, a.history);
    });

    test('invalid PGN is rejected and leaves the game unchanged', () {
      final c = ChessBoardController();
      play(c, ['e4']);
      final count = countNotifications(c);
      for (final bad in ['', '   ', '1. e4 e5 2. Ke3 *', '1. Qh5xf7']) {
        expect(c.loadPgn(bad), isFalse, reason: bad);
      }
      expect(c.history, hasLength(1));
      expect(count(), 0);
    });
  });

  group('notifications and changes', () {
    test('each action notifies once by default', () {
      final c = ChessBoardController();
      final count = countNotifications(c);
      c.move(Square.e2, Square.e4);
      c.moveSan('e5');
      c.undo();
      c.loadFen(kInitialFen);
      c.loadPgn('1. e4 *');
      c.reset();
      expect(count(), 6);
    });

    test('rejected actions do not notify', () {
      final c = ChessBoardController();
      final count = countNotifications(c);
      c.move(Square.e2, Square.e5);
      c.moveSan('Ke2');
      c.loadFen('bad');
      c.loadPgn('bad');
      expect(count(), 0);
    });

    test('notify: false skips notification; notifyListeners batches', () {
      final c = ChessBoardController();
      final count = countNotifications(c);
      c.move(Square.e2, Square.e4, notify: false);
      c.moveSan('e5', notify: false);
      c.undo(notify: false);
      c.reset(notify: false);
      c.loadFen(kInitialFen, notify: false);
      c.loadPgn('1. d4 *', notify: false);
      expect(count(), 0);
      expect(c.halfMoveCount, 1, reason: 'state still changed');
      c.notifyListeners();
      expect(count(), 1);
    });

    test('lastChange describes the change and changeId increases', () {
      final c = ChessBoardController();
      var id = c.changeId;

      c.move(Square.e2, Square.e4);
      expect(c.changeId, greaterThan(id));
      id = c.changeId;
      final change = c.lastChange;
      expect(change, isA<MoveApplied>());
      change as MoveApplied;
      expect(change.move.san, 'e4');
      expect(change.source, MoveSource.code);
      expect(change.silent, isFalse);

      c.moveSan('e5', notify: false);
      expect(c.changeId, greaterThan(id));
      expect((c.lastChange as MoveApplied).silent, isTrue);

      c.undo();
      expect(c.lastChange, isA<PositionReplaced>());
      expect(c.lastChange.silent, isFalse);

      c.reset(notify: false);
      expect(c.lastChange, isA<PositionReplaced>());
      expect(c.lastChange.silent, isTrue);
    });

    test('setPgnHeader does not notify', () {
      final c = ChessBoardController();
      final count = countNotifications(c);
      c.setPgnHeader('White', 'Ann');
      expect(count(), 0);
    });
  });

  group('read-only views', () {
    test('history, headers and pieces cannot be mutated by the app', () {
      final c = ChessBoardController();
      play(c, ['e4']);
      c.setPgnHeader('White', 'Ann');
      expect(() => c.history.clear(), throwsUnsupportedError);
      expect(() => c.pgnHeaders.clear(), throwsUnsupportedError);
      expect(() => c.pieces.clear(), throwsUnsupportedError);
      expect(() => c.legalMoves.clear(), throwsUnsupportedError);
      expect(() => c.legalMovesFrom(Square.e7).clear(), throwsUnsupportedError);
    });

    test('engine is reachable', () {
      final c = ChessBoardController();
      expect(c.engine.fen, c.fen);
    });
  });
}
