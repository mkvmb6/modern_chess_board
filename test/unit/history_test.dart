import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/controller/chess_board_controller.dart'
    show applyUserMove;

void play(ChessBoardController c, List<String> sans) {
  for (final san in sans) {
    expect(c.moveSan(san), isTrue, reason: 'illegal: $san');
  }
}

const _ruyLopez = ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6'];

/// FEN after playing the first [n] moves of [sans] from the start.
String fenAfter(List<String> sans, int n) {
  final c = ChessBoardController();
  play(c, sans.take(n).toList());
  return c.fen;
}

void main() {
  group('navigation keeps the line', () {
    test('back and forward step through the game', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      expect(c.ply, 6);
      expect(c.isViewingHistory, isFalse);
      expect(c.canGoForward, isFalse);

      expect(c.back(), isTrue);
      expect(c.ply, 5);
      expect(c.isViewingHistory, isTrue);
      expect(c.fen, fenAfter(_ruyLopez, 5));
      expect(c.fullLine, hasLength(6), reason: 'line is kept');
      expect(c.history, hasLength(5));
      expect(c.halfMoveCount, 6, reason: 'counts the whole game');
      expect(c.lastMove!.san, 'Bb5');

      expect(c.forward(), isTrue);
      expect(c.ply, 6);
      expect(c.isViewingHistory, isFalse);
      expect(c.fen, fenAfter(_ruyLopez, 6));
    });

    test('back at the start and forward at the end do nothing', () {
      final c = ChessBoardController();
      var n = 0;
      c.addListener(() => n++);
      expect(c.back(), isFalse);
      expect(c.forward(), isFalse);
      play(c, ['e4']);
      n = 0;
      expect(c.forward(), isFalse);
      c.goToStart();
      n = 0;
      expect(c.back(), isFalse);
      expect(c.goToStart(), isFalse);
      expect(n, 0);
    });

    test('goTo jumps to any ply and validates the range', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      for (final ply in [0, 3, 6, 1, 4]) {
        expect(c.goTo(ply), ply != c.ply || true);
        expect(c.ply, ply);
        expect(c.fen, fenAfter(_ruyLopez, ply));
      }
      expect(() => c.goTo(-1), throwsRangeError);
      expect(() => c.goTo(7), throwsRangeError);
    });

    test('goToStart and goToEnd', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      expect(c.goToStart(), isTrue);
      expect(c.ply, 0);
      expect(c.fen, kInitialFen);
      expect(c.lastMove, isNull);
      expect(c.canGoBack, isFalse);
      expect(c.goToEnd(), isTrue);
      expect(c.ply, 6);
      expect(c.goToEnd(), isFalse);
    });

    test('navigation notifies with a NavigatedTo change', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      var n = 0;
      c.addListener(() => n++);
      c.back();
      expect(n, 1);
      final change = c.lastChange as NavigatedTo;
      expect(change.fromPly, 6);
      expect(change.toPly, 5);
      expect(change.silent, isFalse);

      c.goTo(2, notify: false);
      expect(n, 1);
      expect((c.lastChange as NavigatedTo).silent, isTrue);
      expect((c.lastChange as NavigatedTo).fromPly, 5);
    });

    test('status reflects the viewed position', () {
      final c = ChessBoardController();
      play(c, ['f3', 'e5', 'g4', 'Qh4#']);
      expect(c.isCheckmate, isTrue);
      c.back();
      expect(c.isCheckmate, isFalse);
      expect(c.isGameOver, isFalse);
      c.forward();
      expect(c.isCheckmate, isTrue);
    });

    test('repetition only counts positions up to the viewed ply', () {
      final c = ChessBoardController();
      play(c, ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1', 'Ng8']);
      expect(c.isDraw, isTrue);
      c.back();
      expect(c.isDraw, isFalse);
      c.forward();
      expect(c.isDraw, isTrue);
    });

    test('pgn always contains the full line', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      c.goTo(2);
      expect(c.pgn, contains('3. Bb5 a6'));
    });

    test('reading pgn while viewing history keeps the view', () {
      final c = ChessBoardController();
      play(c, ['f3', 'e5', 'g4', 'Qh4#']);
      c.goTo(0);
      final moves = c.legalMoves;
      expect(c.pgn, contains('Qh4# 0-1'), reason: 'result of the full game');
      expect(c.ply, 0);
      expect(c.fen, kInitialFen);
      expect(c.legalMoves, moves);
      expect(c.isGameOver, isFalse);
    });

    test('silent navigation then one notifyListeners call', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      var n = 0;
      c.addListener(() => n++);
      c.back(notify: false);
      c.back(notify: false);
      c.goTo(1, notify: false);
      expect(n, 0);
      c.notifyListeners();
      expect(n, 1);
      final change = c.lastChange as NavigatedTo;
      expect(change.fromPly, 4);
      expect(change.toPly, 1);
      expect(c.fen, fenAfter(_ruyLopez, 1));
    });
  });

  group('moves while viewing history', () {
    test('are rejected by default and keep the line', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      c.goTo(2);
      var n = 0;
      c.addListener(() => n++);
      expect(c.move(Square.d2, Square.d4), isFalse);
      expect(c.moveSan('Nf3'), isFalse, reason: 'even the mainline move');
      expect(applyUserMove(c, Square.d2, Square.d4), isFalse);
      expect(c.fullLine, hasLength(6));
      expect(c.ply, 2);
      expect(n, 0);
    });

    test('branch the game when branching is enabled', () {
      final c = ChessBoardController(allowBranching: true);
      play(c, _ruyLopez);
      c.goTo(2);
      expect(c.move(Square.d2, Square.d4), isTrue);
      expect(c.fullLine.map((m) => m.san), ['e4', 'e5', 'd4']);
      expect(c.ply, 3);
      expect(c.isViewingHistory, isFalse);
      final change = c.lastChange as MoveApplied;
      expect(change.isBranch, isTrue);
      expect(change.discardedPlies, 4);
    });

    test('ordinary moves report no discarded plies', () {
      final c = ChessBoardController(allowBranching: true);
      play(c, ['e4']);
      final change = c.lastChange as MoveApplied;
      expect(change.isBranch, isFalse);
      expect(change.discardedPlies, 0);
    });

    test('branch through moveSan and from the starting position', () {
      final c = ChessBoardController(allowBranching: true);
      play(c, _ruyLopez);
      c.goToStart();
      expect(c.moveSan('d4'), isTrue);
      expect(c.fullLine.map((m) => m.san), ['d4']);
      expect((c.lastChange as MoveApplied).discardedPlies, 6);
    });

    test('discarded positions no longer count towards repetition', () {
      final c = ChessBoardController(allowBranching: true);
      play(c, ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1', 'Ng8']);
      expect(c.isDraw, isTrue);
      c.goTo(4);
      play(c, ['e4']);
      play(c, ['Nf6', 'Nf3', 'Ng8', 'Ng1', 'Nf6']);
      expect(c.isDraw, isFalse, reason: 'old repetitions were discarded');
    });

    test('undo right after a branch removes the new move', () {
      final c = ChessBoardController(allowBranching: true);
      play(c, _ruyLopez);
      c.goTo(2);
      play(c, ['d4']);
      expect(c.undo(), isTrue);
      expect(c.fullLine.map((m) => m.san), ['e4', 'e5']);
      expect(c.ply, 2);
      expect(c.fen, fenAfter(_ruyLopez, 2));
    });

    test('changing allowBranching notifies listeners', () {
      final c = ChessBoardController();
      var n = 0;
      c.addListener(() => n++);
      c.allowBranching = true;
      expect(n, 1);
      c.allowBranching = true;
      expect(n, 1, reason: 'no change, no notification');
      c.allowBranching = false;
      expect(n, 2);
    });

    test('undo only works on the live position', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      c.back();
      expect(c.undo(), isFalse);
      expect(c.fullLine, hasLength(6));
      c.forward();
      expect(c.undo(), isTrue);
      expect(c.fullLine, hasLength(5));
      expect(c.ply, 5);
    });

    test('reset, loadFen and loadPgn return to a live position', () {
      final c = ChessBoardController();
      play(c, _ruyLopez);
      c.goTo(1);
      c.reset();
      expect(c.ply, 0);
      expect(c.fullLine, isEmpty);

      play(c, _ruyLopez);
      c.goTo(1);
      c.loadFen(kInitialFen);
      expect(c.isViewingHistory, isFalse);
      expect(c.fullLine, isEmpty);

      expect(c.loadPgn('1. e4 e5 2. Nf3 *'), isTrue);
      expect(c.ply, 3);
      expect(c.isViewingHistory, isFalse);
      expect(c.back(), isTrue);
      expect(c.fen, fenAfter(_ruyLopez, 2));
    });

    test('navigation works through promotions and castling', () {
      final c = ChessBoardController(fen: 'r3k3/1P6/8/8/8/8/8/4K2R w Kq - 0 1');
      play(c, ['O-O', 'Kd7', 'bxa8=Q']);
      final end = c.fen;
      c.goToStart();
      expect(c.fen, 'r3k3/1P6/8/8/8/8/8/4K2R w Kq - 0 1');
      expect(c.pieceAt(Square.b7), Piece.whitePawn);
      c.goToEnd();
      expect(c.fen, end);
      expect(c.pieceAt(Square.a8), Piece.whiteQueen);
    });
  });
}
