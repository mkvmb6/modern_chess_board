import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

void main() {
  group('Square', () {
    test('has 64 unique values ordered a1..h8', () {
      expect(Square.values, hasLength(64));
      expect(Square.values.toSet(), hasLength(64));
      expect(Square.values.first, Square.a1);
      expect(Square.values[1], Square.b1);
      expect(Square.values.last, Square.h8);
    });

    test('file, rank, index and name agree', () {
      expect(Square.e4.file, 4);
      expect(Square.e4.rank, 3);
      expect(Square.e4.index, 28);
      expect(Square.e4.name, 'e4');
      expect(Square.e4.toString(), 'e4');
      for (final s in Square.values) {
        expect(Square.values[s.index], s);
        expect(Square.at(s.file, s.rank), s);
        expect(Square.parse(s.name), s);
      }
    });

    test('square colors match the standard board (a1 is dark)', () {
      expect(Square.a1.isLight, isFalse);
      expect(Square.h1.isLight, isTrue);
      expect(Square.a8.isLight, isTrue);
      expect(Square.h8.isLight, isFalse);
      expect(Square.e4.isLight, isTrue);
      expect(Square.d4.isLight, isFalse);
    });

    test('value equality', () {
      expect(Square.parse('e4'), Square.e4);
      expect(Square.parse('e4').hashCode, Square.e4.hashCode);
      expect(Square.e4, isNot(Square.e5));
    });

    test('tryParse accepts upper case and trims nothing else', () {
      expect(Square.tryParse('E4'), Square.e4);
      expect(Square.tryParse(' e4'), isNull);
    });

    test('tryParse rejects bad names', () {
      for (final bad in [
        '',
        'e',
        '4',
        'z9',
        'i1',
        'a0',
        'a9',
        'e44',
        'e4 ',
        '44',
        'ee',
        '-1',
      ]) {
        expect(Square.tryParse(bad), isNull, reason: bad);
      }
      expect(Square.tryParse(null), isNull);
    });

    test('tryParse rejects non-ASCII look-alikes', () {
      // Kelvin sign (lower-cases to ASCII k), dotted capital I, full-width
      // digit one, accented e, and an emoji surrogate pair.
      for (final bad in ['K1', 'İ1', 'e１', 'é4', '\u{1F600}']) {
        expect(Square.tryParse(bad), isNull, reason: bad);
      }
    });

    test('parse throws FormatException on bad names', () {
      expect(() => Square.parse('z9'), throwsFormatException);
    });

    test('at throws RangeError when out of range', () {
      expect(() => Square.at(8, 0), throwsRangeError);
      expect(() => Square.at(0, -1), throwsRangeError);
    });
  });

  group('Piece', () {
    test('code and label', () {
      const p = Piece(PieceColor.white, PieceType.king);
      expect(p.code, 'wK');
      expect(p.label, 'white king');
      expect(const Piece(PieceColor.black, PieceType.knight).code, 'bN');
      expect(Piece.blackPawn.label, 'black pawn');
    });

    test('there are 12 distinct pieces and fromCode round-trips', () {
      expect(Piece.values, hasLength(12));
      expect(Piece.values.toSet(), hasLength(12));
      for (final p in Piece.values) {
        expect(Piece.fromCode(p.code), p);
      }
      expect(Piece.tryFromCode('xK'), isNull);
      expect(Piece.tryFromCode('wX'), isNull);
      expect(Piece.tryFromCode('wKK'), isNull);
      expect(Piece.tryFromCode('wk'), isNull);
      expect(Piece.tryFromCode('wK'), isNull); // Kelvin sign
    });

    test('value equality', () {
      expect(const Piece(PieceColor.white, PieceType.queen), Piece.whiteQueen);
      expect(Piece.whiteQueen, isNot(Piece.blackQueen));
    });

    test('color opposite and type letters', () {
      expect(PieceColor.white.opposite, PieceColor.black);
      expect(PieceColor.black.opposite, PieceColor.white);
      expect(PieceType.knight.letter, 'n');
      expect(PieceType.fromLetter('Q'), PieceType.queen);
      expect(PieceType.fromLetter('x'), isNull);
      expect(PieceType.fromLetter('K'), isNull); // Kelvin sign
      expect(PieceColor.white.letter, 'w');
      expect(PieceColor.black.letter, 'b');
      expect(PieceColor.fromLetter('w'), PieceColor.white);
      expect(PieceColor.fromLetter('b'), PieceColor.black);
      expect(PieceColor.fromLetter('W'), isNull);
    });
  });

  group('BoardMove', () {
    test('value equality covers all fields', () {
      const a = BoardMove(
        from: Square.e7,
        to: Square.e8,
        promotion: PieceType.queen,
        piece: Piece.blackPawn,
        san: 'e8=Q+',
        isCheck: true,
      );
      const b = BoardMove(
        from: Square.e7,
        to: Square.e8,
        promotion: PieceType.queen,
        piece: Piece.blackPawn,
        san: 'e8=Q+',
        isCheck: true,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const BoardMove(from: Square.e7, to: Square.e8)));
    });

    test('each field takes part in equality', () {
      const base = BoardMove(from: Square.e2, to: Square.e4);
      const variants = [
        BoardMove(from: Square.d2, to: Square.e4),
        BoardMove(from: Square.e2, to: Square.e3),
        BoardMove(from: Square.e2, to: Square.e4, promotion: PieceType.queen),
        BoardMove(from: Square.e2, to: Square.e4, piece: Piece.whitePawn),
        BoardMove(from: Square.e2, to: Square.e4, san: 'e4'),
        BoardMove(from: Square.e2, to: Square.e4, captured: Piece.blackPawn),
        BoardMove(from: Square.e2, to: Square.e4, castle: CastleSide.kingside),
        BoardMove(from: Square.e2, to: Square.e4, isEnPassant: true),
        BoardMove(from: Square.e2, to: Square.e4, isCheck: true),
        BoardMove(
          from: Square.e2,
          to: Square.e4,
          isCheck: true,
          isCheckmate: true,
        ),
      ];
      for (final v in variants) {
        expect(v, isNot(base), reason: '$v');
      }
    });

    test('uci matches a bare request against an applied move', () {
      const request = BoardMove(from: Square.g1, to: Square.f3);
      const applied = BoardMove(
        from: Square.g1,
        to: Square.f3,
        piece: Piece.whiteKnight,
        san: 'Nf3',
      );
      expect(applied, isNot(request));
      expect(applied.uci, request.uci);
    });

    test('checkmate without check fails an assert', () {
      expect(
        () => BoardMove(from: Square.e2, to: Square.e4, isCheckmate: true),
        throwsAssertionError,
      );
    });

    test('toString shows uci and san', () {
      expect(
        const BoardMove(from: Square.e2, to: Square.e4).toString(),
        'BoardMove(e2e4)',
      );
      expect(
        const BoardMove(from: Square.e2, to: Square.e4, san: 'e4').toString(),
        'BoardMove(e2e4, san: e4)',
      );
    });

    test('derived flags', () {
      const castle = BoardMove(
        from: Square.e1,
        to: Square.g1,
        castle: CastleSide.kingside,
      );
      expect(castle.isCastle, isTrue);
      expect(castle.isCapture, isFalse);
      expect(castle.isPromotion, isFalse);

      const ep = BoardMove(
        from: Square.e5,
        to: Square.d6,
        captured: Piece.blackPawn,
        isEnPassant: true,
      );
      expect(ep.isCapture, isTrue);
      expect(ep.isCastle, isFalse);
    });

    test('uci notation', () {
      expect(const BoardMove(from: Square.e2, to: Square.e4).uci, 'e2e4');
      expect(
        const BoardMove(
          from: Square.a7,
          to: Square.a8,
          promotion: PieceType.knight,
        ).uci,
        'a7a8n',
      );
    });
  });

  group('Arrow', () {
    test('resolves valid squares', () {
      const a = Arrow('e2', 'e4');
      expect(a.fromSquare, Square.e2);
      expect(a.toSquare, Square.e4);
      expect(a.isValid, isTrue);
    });

    test('bad square names resolve to null without throwing', () {
      const a = Arrow('z9', 'e4');
      expect(a.fromSquare, isNull);
      expect(a.toSquare, Square.e4);
      expect(a.isValid, isFalse);
      expect(const Arrow('e4', 'e4').isValid, isFalse);
    });

    test('value equality includes color', () {
      expect(const Arrow('e2', 'e4'), const Arrow('e2', 'e4'));
      expect(
        const Arrow('e2', 'e4', color: Color(0xFFFF0000)),
        isNot(const Arrow('e2', 'e4')),
      );
      expect(
        const Arrow('e2', 'e4', color: Color(0xFFFF0000)).hashCode,
        const Arrow('e2', 'e4', color: Color(0xFFFF0000)).hashCode,
      );
    });

    test('fromSquares builds an arrow from Square values', () {
      expect(Arrow.fromSquares(Square.g1, Square.f3), const Arrow('g1', 'f3'));
    });
  });

  group('SquareMark', () {
    test('resolves and defaults to a circle', () {
      const m = SquareMark('d5');
      expect(m.markedSquare, Square.d5);
      expect(m.shape, MarkShape.circle);
      expect(const SquareMark('k1').markedSquare, isNull);
    });

    test('value equality', () {
      expect(const SquareMark('d5'), const SquareMark('d5'));
      expect(
        const SquareMark('d5', shape: MarkShape.fill),
        isNot(const SquareMark('d5')),
      );
      expect(
        const SquareMark('d5', color: Color(0xFF00FF00)),
        isNot(const SquareMark('d5')),
      );
      expect(
        const SquareMark('d5', color: Color(0xFF00FF00)).hashCode,
        const SquareMark('d5', color: Color(0xFF00FF00)).hashCode,
      );
    });
  });

  group('game status and results', () {
    test('result PGN tokens', () {
      expect(GameResult.whiteWins.pgn, '1-0');
      expect(GameResult.blackWins.pgn, '0-1');
      expect(GameResult.draw.pgn, '1/2-1/2');
      expect(GameResult.ongoing.pgn, '*');
    });

    test('status game-over flag', () {
      expect(GameStatus.ongoing.isGameOver, isFalse);
      expect(GameStatus.checkmate.isGameOver, isTrue);
      expect(GameStatus.stalemate.isGameOver, isTrue);
      expect(GameStatus.draw.isGameOver, isTrue);
    });

    test('stalemate counts as a draw', () {
      expect(GameStatus.stalemate.isDraw, isTrue);
      expect(GameStatus.draw.isDraw, isTrue);
      expect(GameStatus.checkmate.isDraw, isFalse);
      expect(GameStatus.ongoing.isDraw, isFalse);
    });

    test('draw reasons and sound events exist', () {
      expect(DrawReason.values, hasLength(4));
      expect(SoundEvent.values, hasLength(7));
    });
  });
}
