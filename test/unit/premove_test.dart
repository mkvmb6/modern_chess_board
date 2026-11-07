import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/interaction/board_interaction.dart';
import 'package:modern_chess_board/src/widget/interaction/premove.dart';

Set<Square> squares(List<String> names) => {
  for (final n in names) Square.parse(n),
};

void main() {
  group('premoveDestinations', () {
    test('sliding pieces reach through other pieces to the edge', () {
      // Black queen on d8 behind her own pawn and white pieces in the way.
      final c = ChessBoardController(fen: '3qk3/3p4/8/8/3P4/8/8/4K3 w - - 0 1');
      final d = premoveDestinations(c, Square.d8);
      // Down the file past its own pawn, to the edge.
      expect(d, containsAll(squares(['d6', 'd4', 'd1'])));
      // Its own pieces' squares count, for premoved recaptures.
      expect(d, containsAll(squares(['d7', 'e8'])));
      expect(d, isNot(contains(Square.d8)));
    });

    test('pawns may premove both diagonals onto empty squares', () {
      final c = ChessBoardController();
      expect(
        premoveDestinations(c, Square.e7),
        squares(['e6', 'e5', 'd6', 'f6']),
      );
    });

    test('a pawn off its start square moves one step', () {
      final c = ChessBoardController(fen: '4k3/8/4p3/8/8/8/8/4K3 w - - 0 1');
      expect(premoveDestinations(c, Square.e6), squares(['e5', 'd5', 'f5']));
    });

    test('the king lists castling squares and its rooks', () {
      final c = ChessBoardController(fen: 'r3k2r/8/8/8/8/8/8/4K3 w kq - 0 1');
      final d = premoveDestinations(c, Square.e8);
      expect(d, containsAll(squares(['g8', 'h8', 'c8', 'a8'])));
    });

    test('no castling without the right', () {
      final c = ChessBoardController(fen: 'r3k2r/8/8/8/8/8/8/4K3 w q - 0 1');
      final d = premoveDestinations(c, Square.e8);
      expect(d, isNot(contains(Square.g8)));
      expect(d, isNot(contains(Square.h8)));
      expect(d, contains(Square.c8));
    });
  });

  group('BoardInteraction premoves', () {
    BoardInteraction make(
      ChessBoardController c, {
      InteractiveSide side = InteractiveSide.black,
      bool premoves = true,
      List<(Square, Square)>? queued,
    }) => BoardInteraction(
      controller: c,
      onMove: (from, to) => c.move(from, to),
      onPremove: (from, to) {
        queued?.add((from, to));
        return true;
      },
      interactiveSide: side,
      enablePremoves: premoves,
    );

    test('the off-turn side can select and premove', () {
      final queued = <(Square, Square)>[];
      final i = make(ChessBoardController(), queued: queued);
      expect(i.canMove(PieceColor.black), isFalse);
      expect(i.canPremove(PieceColor.black), isTrue);
      expect(i.tap(Square.e7), TapOutcome.selected);
      expect(i.tap(Square.e5), TapOutcome.premoved);
      expect(queued, [(Square.e7, Square.e5)]);
    });

    test('premoves need a single interactive side', () {
      final i = make(ChessBoardController(), side: InteractiveSide.both);
      expect(i.canPremove(PieceColor.black), isFalse);
    });

    test('premoves are off unless enabled', () {
      final i = make(ChessBoardController(), premoves: false);
      expect(i.canPremove(PieceColor.black), isFalse);
      expect(i.tap(Square.e7), TapOutcome.ignored);
    });

    test('no premoves on a read-only board or after the game', () {
      final i = make(ChessBoardController())..readOnly = true;
      expect(i.canPremove(PieceColor.black), isFalse);
      final over = ChessBoardController();
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        over.moveSan(san);
      }
      expect(
        make(over, side: InteractiveSide.white).canPremove(PieceColor.white),
        isFalse,
      );
    });

    test('a drop on a premove destination queues it', () {
      final queued = <(Square, Square)>[];
      final i = make(ChessBoardController(), queued: queued);
      expect(i.drop(Square.g8, Square.f6), TapOutcome.premoved);
      expect(queued, [(Square.g8, Square.f6)]);
    });

    test('a drop elsewhere is illegal', () {
      final i = make(ChessBoardController());
      expect(i.drop(Square.g8, Square.g6), TapOutcome.illegal);
    });
  });
}
