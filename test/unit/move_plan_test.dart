import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/animation/move_plan.dart';

/// Plays [san] on [c] and returns the plan for that move, built from the
/// pieces before it.
MovePlan planFor(ChessBoardController c, String san) {
  final before = c.pieces;
  expect(c.moveSan(san), isTrue, reason: san);
  return MovePlan.forMove(c.lastMove!, before: before);
}

void main() {
  test('a quiet move slides one piece', () {
    final p = planFor(ChessBoardController(), 'Nf3');
    expect(p.moving, [
      const PieceSlide(Piece.whiteKnight, from: Square.g1, to: Square.f3),
    ]);
    expect(p.fading, isEmpty);
    expect(p.animatedSquares, {Square.f3});
  });

  test('a capture slides the attacker and fades the captured piece', () {
    final c = ChessBoardController()
      ..moveSan('e4')
      ..moveSan('d5');
    final p = planFor(c, 'exd5');
    expect(p.moving, [
      const PieceSlide(Piece.whitePawn, from: Square.e4, to: Square.d5),
    ]);
    expect(p.fading, [const PieceFade(Piece.blackPawn, Square.d5)]);
  });

  test('en passant fades the pawn beside, not on, the target square', () {
    final c = ChessBoardController(fen: '4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1');
    final p = planFor(c, 'dxe6');
    expect(p.fading, [const PieceFade(Piece.blackPawn, Square.e5)]);
    expect(p.moving.single.to, Square.e6);
  });

  test('castling slides the king and the rook', () {
    final c = ChessBoardController(fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
    final p = planFor(c, 'O-O');
    expect(
      p.moving,
      unorderedEquals([
        const PieceSlide(Piece.whiteKing, from: Square.e1, to: Square.g1),
        const PieceSlide(Piece.whiteRook, from: Square.h1, to: Square.f1),
      ]),
    );
    expect(p.animatedSquares, {Square.g1, Square.f1});

    final q = planFor(
      ChessBoardController(fen: 'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1'),
      'O-O-O',
    );
    expect(
      q.moving,
      unorderedEquals([
        const PieceSlide(Piece.blackKing, from: Square.e8, to: Square.c8),
        const PieceSlide(Piece.blackRook, from: Square.a8, to: Square.d8),
      ]),
    );
  });

  test('a promotion slides the pawn and lands as the new piece', () {
    final c = ChessBoardController(fen: '1r5k/P7/8/8/8/8/8/K7 w - - 0 1');
    final before = c.pieces;
    c.move(Square.a7, Square.b8, promotion: PieceType.knight);
    final p = MovePlan.forMove(c.lastMove!, before: before);
    final slide = p.moving.single;
    expect(slide.piece, Piece.whitePawn, reason: 'the pawn travels');
    expect(slide.landsAs, Piece.whiteKnight);
    expect(p.fading, [const PieceFade(Piece.blackRook, Square.b8)]);
  });

  test('value equality', () {
    final c = ChessBoardController();
    final a = planFor(c, 'e4');
    final b = MovePlan.forMove(
      c.lastMove!,
      before: ChessBoardController().pieces,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
