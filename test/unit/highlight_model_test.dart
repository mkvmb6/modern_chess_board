import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/highlight_model.dart';

const _theme = ChessBoardTheme.green;

BoardHighlights build(
  ChessBoardController c, {
  Square? selected,
  Square? hover,
  bool showLastMove = true,
  ChessBoardTheme theme = _theme,
}) => BoardHighlights.compute(
  controller: c,
  selected: selected,
  hover: hover,
  showLastMove: showLastMove,
  theme: theme,
);

void main() {
  group('selection and legal markers', () {
    test('nothing is highlighted at the start', () {
      final h = build(ChessBoardController());
      expect(h.tints, isEmpty);
      expect(h.markers, isEmpty);
    });

    test('the selected square is tinted with the selection color', () {
      final h = build(ChessBoardController(), selected: Square.g1);
      expect(h.tints, {Square.g1: _theme.selectionColor});
    });

    test('empty legal squares get dots', () {
      final h = build(ChessBoardController(), selected: Square.g1);
      expect(h.markers, {
        Square.f3: LegalMarker.dot,
        Square.h3: LegalMarker.dot,
      });
    });

    test('captures get rings, including en passant', () {
      final c = ChessBoardController(fen: '4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1');
      final h = build(c, selected: Square.d5);
      expect(h.markers, {
        Square.d6: LegalMarker.dot,
        Square.e6: LegalMarker.ring,
      });

      final d = ChessBoardController(fen: '4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1');
      expect(build(d, selected: Square.e4).markers, {
        Square.e5: LegalMarker.dot,
        Square.d5: LegalMarker.ring,
      });
    });

    test('promotion squares show one marker, not four', () {
      final c = ChessBoardController(fen: '1r5k/P7/8/8/8/8/8/K7 w - - 0 1');
      final h = build(c, selected: Square.a7);
      expect(h.markers, {
        Square.a8: LegalMarker.dot,
        Square.b8: LegalMarker.ring,
      });
    });

    test('a selected king rings its own rook when it can castle there', () {
      final c = ChessBoardController(
        fen: 'r3k2r/8/8/8/8/8/8/R3K2R w Kkq - 0 1',
      );
      final h = build(c, selected: Square.e1);
      expect(h.markers[Square.h1], LegalMarker.ring, reason: 'king-onto-rook');
      expect(h.markers[Square.g1], LegalMarker.dot, reason: 'two squares');
      expect(h.markers.containsKey(Square.a1), isFalse, reason: 'no Q rights');
    });

    test('a selected piece with no legal moves shows only the selection', () {
      final h = build(ChessBoardController(), selected: Square.a1);
      expect(h.tints, {Square.a1: _theme.selectionColor});
      expect(h.markers, isEmpty);
    });
  });

  group('last move', () {
    test('from and to are tinted', () {
      final c = ChessBoardController()..moveSan('e4');
      expect(build(c).tints, {
        Square.e2: _theme.lastMoveColor,
        Square.e4: _theme.lastMoveColor,
      });
    });

    test('can be turned off', () {
      final c = ChessBoardController()..moveSan('e4');
      expect(build(c, showLastMove: false).tints, isEmpty);
    });

    test('a selected square that is also part of the last move is tinted '
        'once, with the selection color', () {
      // Pawns keep the game going; a lone knight would be a draw.
      final c = ChessBoardController(fen: '4k3/7p/8/8/8/8/7P/4K1N1 b - - 0 1')
        ..moveSan('Kd7');
      // The last move is black's; select white's king, which is not in it.
      expect(build(c, selected: Square.e1).tints, {
        Square.e8: _theme.lastMoveColor,
        Square.d7: _theme.lastMoveColor,
        Square.e1: _theme.selectionColor,
      });

      // Now the selected square is the last move's destination.
      final same = ChessBoardController(
        fen: '4k3/7p/8/8/8/8/7P/4K1N1 w - - 0 1',
      )..moveSan('Nf3');
      // It's black's turn, but the model takes any selected square; the
      // interaction rules decide what can be selected.
      final h = build(same, selected: Square.f3);
      expect(h.tints[Square.f3], _theme.selectionColor);
      expect(h.tints[Square.g1], _theme.lastMoveColor);
      expect(
        h.tints.values.where((c) => c == _theme.lastMoveColor),
        hasLength(1),
      );
    });

    test('follows history navigation', () {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5')
        ..back();
      expect(build(c).tints.keys.toSet(), {Square.e2, Square.e4});
      c.goToStart();
      expect(build(c).tints, isEmpty);
    });
  });

  group('check and mate', () {
    test('a checkmated king is tinted', () {
      final c = ChessBoardController();
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        c.moveSan(san);
      }
      final h = build(c, showLastMove: false);
      expect(h.tints, {Square.e1: _theme.checkmateColor});
    });

    test('check is not tinted by default', () {
      final c = ChessBoardController(fen: '4k3/8/8/8/8/8/8/R3K3 w - - 0 1')
        ..moveSan('Ra8+');
      expect(build(c, showLastMove: false).tints, isEmpty);
    });

    test('check is tinted when the theme gives it a color', () {
      const red = Color(0x99E53935);
      final c = ChessBoardController(fen: '4k3/8/8/8/8/8/8/R3K3 w - - 0 1')
        ..moveSan('Ra8+');
      final h = build(
        c,
        showLastMove: false,
        theme: _theme.copyWith(checkColor: red),
      );
      expect(h.tints, {Square.e8: red});
    });

    test('mate uses the mate color even when a check color is set', () {
      final c = ChessBoardController();
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        c.moveSan(san);
      }
      final h = build(
        c,
        showLastMove: false,
        theme: _theme.copyWith(checkColor: const Color(0xFF00FF00)),
      );
      expect(h.tints[Square.e1], _theme.checkmateColor);
    });

    test('the king tint sits on top of the last-move tint', () {
      // Qh4# lands next to the king; e1 isn't part of the move, but a king
      // that moved into a square later attacked would be. Here we check
      // the layering order.
      final c = ChessBoardController();
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        c.moveSan(san);
      }
      final h = build(c);
      expect(h.tints[Square.e1], _theme.checkmateColor);
      expect(h.tints[Square.h4], _theme.lastMoveColor);
    });
  });

  group('hover', () {
    test('only a legal destination of the selection shows hover', () {
      final c = ChessBoardController();
      expect(build(c, hover: Square.f3).hover, isNull, reason: 'no selection');
      expect(build(c, selected: Square.g1, hover: Square.f3).hover, Square.f3);
      expect(
        build(c, selected: Square.g1, hover: Square.g3).hover,
        isNull,
        reason: 'not legal',
      );
    });
  });

  test('value equality, so the painter can skip repaints', () {
    final c = ChessBoardController()..moveSan('e4');
    expect(build(c, selected: Square.e7), build(c, selected: Square.e7));
    expect(build(c, selected: Square.e7), isNot(build(c, selected: Square.d7)));
  });
}
