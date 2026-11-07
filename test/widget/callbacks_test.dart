import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

Widget host(ChessBoard board) => MaterialApp(
  home: Material(
    child: Center(child: SizedBox.square(dimension: 400, child: board)),
  ),
);

Future<void> pumpBoard(WidgetTester tester, ChessBoard board) async {
  await tester.pumpWidget(host(board));
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => board.pieceSet.precache(context));
  await tester.pump();
}

Finder _squares() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
);

Future<void> tapSquare(WidgetTester tester, Square square) async {
  final g =
      (tester.widget<CustomPaint>(_squares()).painter! as BoardSquaresPainter)
          .geometry;
  await tester.tapAt(tester.getTopLeft(_squares()) + g.squareCenter(square));
  await tester.pump();
}

Future<void> userMove(WidgetTester tester, Square from, Square to) async {
  await tapSquare(tester, from);
  await tapSquare(tester, to);
}

void main() {
  group('onMove', () {
    testWidgets('reports each user move with SAN and the resulting FEN', (
      tester,
    ) async {
      final c = ChessBoardController();
      final moves = <BoardMove>[];
      final fens = <String>[];
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          onMove: (move) {
            moves.add(move);
            fens.add(c.fen);
          },
        ),
      );
      await userMove(tester, Square.e2, Square.e4);
      await userMove(tester, Square.e7, Square.e5);
      expect(moves.map((m) => m.san), ['e4', 'e5']);
      expect(moves.first.from, Square.e2);
      expect(moves.first.to, Square.e4);
      expect(moves.first.piece, Piece.whitePawn);
      expect(fens.last, c.fen, reason: 'the move is applied before onMove');
    });

    testWidgets('reports the chosen promotion piece', (tester) async {
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      final moves = <BoardMove>[];
      await pumpBoard(tester, ChessBoard(controller: c, onMove: moves.add));
      await userMove(tester, Square.a7, Square.a8);
      expect(moves, isEmpty, reason: 'not until a piece is chosen');
      await tester.tap(find.byKey(const ValueKey('promotion-rook')));
      await tester.pump();
      expect(moves.single.promotion, PieceType.rook);
      expect(moves.single.san, 'a8=R+');
    });

    testWidgets('moves made through the controller are not reported', (
      tester,
    ) async {
      final c = ChessBoardController();
      final moves = <BoardMove>[];
      await pumpBoard(tester, ChessBoard(controller: c, onMove: moves.add));
      c.move(Square.e2, Square.e4);
      c.moveSan('e5');
      await tester.pump();
      expect(moves, isEmpty);
    });

    testWidgets('rejected and cancelled moves are not reported', (
      tester,
    ) async {
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      final moves = <BoardMove>[];
      await pumpBoard(tester, ChessBoard(controller: c, onMove: moves.add));
      await userMove(tester, Square.a1, Square.a3); // illegal
      await userMove(tester, Square.a7, Square.a8);
      await tapSquare(tester, Square.e4); // cancels the picker
      expect(moves, isEmpty);
    });

    testWidgets('the callback can be replaced', (tester) async {
      final c = ChessBoardController();
      final first = <BoardMove>[];
      final second = <BoardMove>[];
      await pumpBoard(tester, ChessBoard(controller: c, onMove: first.add));
      await tester.pumpWidget(
        host(ChessBoard(controller: c, onMove: second.add)),
      );
      await userMove(tester, Square.e2, Square.e4);
      expect(first, isEmpty);
      expect(second, hasLength(1));
    });
  });

  group('onGameEnd', () {
    testWidgets('fires once with the result when a user move mates', (
      tester,
    ) async {
      final c = ChessBoardController()
        ..moveSan('f3')
        ..moveSan('e5')
        ..moveSan('g4');
      final ends = <GameEnd>[];
      await pumpBoard(tester, ChessBoard(controller: c, onGameEnd: ends.add));
      await userMove(tester, Square.d8, Square.h4);
      expect(ends, [
        const GameEnd(
          status: GameStatus.checkmate,
          result: GameResult.blackWins,
        ),
      ]);
      // Rebuilds and unrelated notifications don't fire it again.
      await tester.pumpWidget(
        host(ChessBoard(controller: c, onGameEnd: ends.add)),
      );
      c.allowBranching = true;
      await tester.pump();
      expect(ends, hasLength(1));
    });

    testWidgets('fires for a game ended by a code move too', (tester) async {
      final c = ChessBoardController(fen: 'k7/8/1K6/8/8/8/8/2Q5 w - - 0 1');
      final ends = <GameEnd>[];
      await pumpBoard(tester, ChessBoard(controller: c, onGameEnd: ends.add));
      c.moveSan('Qc7');
      await tester.pump();
      expect(ends, [
        const GameEnd(
          status: GameStatus.stalemate,
          result: GameResult.draw,
          drawReason: DrawReason.stalemate,
        ),
      ]);
    });

    testWidgets('fires for draws by repetition', (tester) async {
      final c = ChessBoardController();
      for (final san in ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1']) {
        c.moveSan(san);
      }
      final ends = <GameEnd>[];
      await pumpBoard(tester, ChessBoard(controller: c, onGameEnd: ends.add));
      await userMove(tester, Square.f6, Square.g8);
      expect(ends, [
        const GameEnd(
          status: GameStatus.draw,
          result: GameResult.draw,
          drawReason: DrawReason.threefoldRepetition,
        ),
      ]);
    });

    testWidgets('does not fire for an already-finished game, history '
        'navigation or loading a finished game', (tester) async {
      final finished = ChessBoardController()
        ..moveSan('f3')
        ..moveSan('e5')
        ..moveSan('g4')
        ..moveSan('Qh4#');
      final ends = <GameEnd>[];
      await pumpBoard(
        tester,
        ChessBoard(controller: finished, onGameEnd: ends.add),
      );
      expect(ends, isEmpty, reason: 'the board appeared on a finished game');
      finished
        ..back()
        ..forward();
      await tester.pump();
      expect(ends, isEmpty, reason: 'navigating does not end a game');
      finished.loadPgn('1. f3 e5 2. g4 Qh4# 0-1');
      await tester.pump();
      expect(ends, isEmpty, reason: 'loading is not playing');
    });

    testWidgets('fires again in a new game after undo or reset', (
      tester,
    ) async {
      final c = ChessBoardController()
        ..moveSan('f3')
        ..moveSan('e5')
        ..moveSan('g4');
      final ends = <GameEnd>[];
      await pumpBoard(tester, ChessBoard(controller: c, onGameEnd: ends.add));
      c.moveSan('Qh4#');
      await tester.pump();
      c.undo();
      await tester.pump();
      c.moveSan('Qh4#');
      await tester.pump();
      expect(ends, hasLength(2));
    });

    testWidgets('a silent game-ending move does not fire', (tester) async {
      final c = ChessBoardController()
        ..moveSan('f3')
        ..moveSan('e5')
        ..moveSan('g4');
      final ends = <GameEnd>[];
      await pumpBoard(tester, ChessBoard(controller: c, onGameEnd: ends.add));
      c.moveSan('Qh4#', notify: false);
      c.notifyListeners();
      await tester.pump();
      expect(ends, isEmpty);
    });
  });

  group('ordering and re-entry', () {
    testWidgets('an app reply from inside onMove that ends the game reports '
        'each callback once', (tester) async {
      final c = ChessBoardController()
        ..moveSan('f3')
        ..moveSan('e5');
      final log = <String>[];
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          onMove: (m) {
            log.add('move ${m.san}');
            // The "engine" replies at once with mate.
            if (m.san == 'g4') c.moveSan('Qh4#');
          },
          onGameEnd: (end) => log.add('end ${end.result.pgn}'),
        ),
      );
      await userMove(tester, Square.g2, Square.g4);
      expect(log, ['move g4', 'end 0-1']);
      expect(c.isCheckmate, isTrue);
    });

    testWidgets('a promotion that mates reports the move, then the end', (
      tester,
    ) async {
      final c = ChessBoardController(fen: '7k/P5R1/6K1/8/8/8/8/8 w - - 0 1');
      final log = <String>[];
      await pumpBoard(
        tester,
        ChessBoard(
          controller: c,
          onMove: (m) => log.add('move ${m.san}'),
          onGameEnd: (end) => log.add('end ${end.status.name}'),
        ),
      );
      await userMove(tester, Square.a7, Square.a8);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('promotion-queen')));
      await tester.pump();
      expect(log, ['move a8=Q#', 'end checkmate']);
    });

    testWidgets('after a controller swap only the new controller reports', (
      tester,
    ) async {
      final a = ChessBoardController();
      final b = ChessBoardController();
      final moves = <BoardMove>[];
      final ends = <GameEnd>[];
      await pumpBoard(
        tester,
        ChessBoard(controller: a, onMove: moves.add, onGameEnd: ends.add),
      );
      await tester.pumpWidget(
        host(ChessBoard(controller: b, onMove: moves.add, onGameEnd: ends.add)),
      );
      expect(moves, isEmpty, reason: 'the swap itself reports nothing');
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        a.moveSan(san);
      }
      await tester.pump();
      expect(ends, isEmpty, reason: 'the old controller is not watched');
      await userMove(tester, Square.e2, Square.e4);
      expect(moves.map((m) => m.san), ['e4']);
    });

    test('GameEnd has value equality and a readable toString', () {
      const a = GameEnd(
        status: GameStatus.draw,
        result: GameResult.draw,
        drawReason: DrawReason.fiftyMoveRule,
      );
      const b = GameEnd(
        status: GameStatus.draw,
        result: GameResult.draw,
        drawReason: DrawReason.fiftyMoveRule,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(const GameEnd(status: GameStatus.draw, result: GameResult.draw)),
      );
      expect('$a', 'GameEnd(draw, 1/2-1/2, fiftyMoveRule)');
    });
  });
}
