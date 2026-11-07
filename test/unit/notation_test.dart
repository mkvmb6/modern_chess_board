import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/controller/notation.dart';

/// Loads [fen], plays [san], and returns the spoken description.
String spoken(String fen, String san) {
  final c = ChessBoardController(fen: fen);
  expect(c.moveSan(san), isTrue, reason: san);
  return describeMove(c.lastMove!, drawReason: c.drawReason);
}

void main() {
  test('quiet moves name the piece and square', () {
    expect(spoken(kInitialFen, 'e4'), 'White pawn to e4');
    expect(spoken(kInitialFen, 'Nf3'), 'White knight to f3');
    final c = ChessBoardController()..moveSan('e4');
    c.moveSan('c5');
    expect(describeMove(c.lastMove!), 'Black pawn to c5');
  });

  test('captures name the captured piece', () {
    const fen = '4k3/7p/5n2/8/8/8/1B5P/4K3 w - - 0 1';
    expect(spoken(fen, 'Bxf6'), 'White bishop takes black knight on f6');
  });

  test('en passant is called out', () {
    const fen = '4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1';
    expect(
      spoken(fen, 'dxe6'),
      'White pawn takes black pawn en passant, to e6',
    );
  });

  test('castling', () {
    const fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
    expect(spoken(fen, 'O-O'), 'White castles kingside');
    expect(spoken(fen, 'O-O-O'), 'White castles queenside');
    const black = 'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1';
    expect(spoken(black, 'O-O-O'), 'Black castles queenside');
  });

  test('promotion, with and without capture', () {
    expect(
      spoken('7k/P6p/8/8/8/8/7P/K7 w - - 0 1', 'a8=N'),
      'White pawn to a8, promotes to knight',
    );
    expect(
      spoken('1r5k/P6p/8/8/8/8/7P/K7 w - - 0 1', 'axb8=N'),
      'White pawn takes black rook on b8, promotes to knight',
    );
  });

  test('check and checkmate', () {
    expect(
      spoken('4k3/8/8/8/8/8/8/R3K3 w - - 0 1', 'Ra8+'),
      'White rook to a8, check',
    );
    expect(
      spoken(
        'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2',
        'Qh4#',
      ),
      'Black queen to h4, checkmate',
    );
  });

  test('draws are announced with their reason', () {
    expect(
      spoken('k7/8/1K6/8/8/8/8/2Q5 w - - 0 1', 'Qc7'),
      'White queen to c7, stalemate',
    );
    expect(
      spoken('4k3/8/8/8/8/8/3r4/4K1N1 w - - 0 1', 'Kxd2'),
      'White king takes black rook on d2, draw by insufficient material',
    );
    final c = ChessBoardController();
    for (final san in ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1']) {
      c.moveSan(san);
    }
    c.moveSan('Ng8');
    expect(
      describeMove(c.lastMove!, drawReason: c.drawReason),
      'Black knight to g8, draw by threefold repetition',
    );
    expect(
      describeMove(
        const BoardMove(from: Square.a1, to: Square.a2, piece: Piece.whiteRook),
        drawReason: DrawReason.fiftyMoveRule,
      ),
      'White rook to a2, draw by the fifty-move rule',
    );
  });

  test('a checking move that draws announces both check and the draw', () {
    // Verified sequence: the third ...Kh8 completes a threefold repetition.
    final c = ChessBoardController(fen: '7k/8/6Q1/8/8/8/8/K7 w - - 0 1');
    for (final san in ['Qh6+', 'Kg8', 'Qg6+', 'Kh8', 'Qh6+', 'Kg8', 'Qg6+']) {
      expect(c.moveSan(san), isTrue, reason: san);
    }
    expect(c.isDraw, isFalse);
    expect(c.moveSan('Kh8'), isTrue);
    expect(
      describeMove(c.lastMove!, drawReason: c.drawReason),
      'Black king to h8, draw by threefold repetition',
    );

    // A checking move that draws keeps both parts, in that order.
    expect(
      describeMove(
        const BoardMove(
          from: Square.g6,
          to: Square.h6,
          piece: Piece.whiteQueen,
          san: 'Qh6+',
          isCheck: true,
        ),
        drawReason: DrawReason.threefoldRepetition,
      ),
      'White queen to h6, check, draw by threefold repetition',
    );
  });

  test('castling with mate and promotion with capture and mate', () {
    expect(
      spoken('1r5k/P5R1/6K1/8/8/8/8/8 w - - 0 1', 'axb8=Q#'),
      'White pawn takes black rook on b8, promotes to queen, checkmate',
    );
    expect(
      describeMove(
        const BoardMove(
          from: Square.e1,
          to: Square.g1,
          piece: Piece.whiteKing,
          san: 'O-O#',
          castle: CastleSide.kingside,
          isCheck: true,
          isCheckmate: true,
        ),
      ),
      'White castles kingside, checkmate',
    );
  });

  test('the origin square is named when SAN disambiguates', () {
    expect(
      spoken('4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1', 'Nbd2'),
      'White knight from b1 to d2',
    );
    expect(
      spoken('4k3/8/8/8/R7/8/8/R3K3 w - - 0 1', 'R1a2'),
      'White rook from a1 to a2',
    );
    // Pawn captures name the file in SAN but don't need "from".
    expect(
      spoken('4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1', 'exd5'),
      'White pawn takes black pawn on d5',
    );
  });

  test('a bare promotion request mentions the piece', () {
    expect(
      describeMove(
        const BoardMove(
          from: Square.e7,
          to: Square.e8,
          promotion: PieceType.queen,
        ),
      ),
      'e7 to e8, promotes to queen',
    );
  });

  test('a bare request without piece information still reads well', () {
    expect(
      describeMove(const BoardMove(from: Square.e2, to: Square.e4)),
      'e2 to e4',
    );
  });
}
