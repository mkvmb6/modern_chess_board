import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/interaction/board_interaction.dart';

/// An interaction whose moves go straight to the controller, recording the
/// requests it receives.
(BoardInteraction, List<(Square, Square)>) setup([ChessBoardController? c]) {
  final controller = c ?? ChessBoardController();
  final requests = <(Square, Square)>[];
  final interaction = BoardInteraction(
    controller: controller,
    onMove: (from, to) {
      requests.add((from, to));
      return controller.move(from, to, promotion: PieceType.queen);
    },
  );
  return (interaction, requests);
}

void main() {
  group('tap rules', () {
    test('tapping a piece of the side to move selects it', () {
      final (i, _) = setup();
      expect(i.tap(Square.e2), TapOutcome.selected);
      expect(i.selection.value, Square.e2);
    });

    test('tapping a legal destination makes the move', () {
      final (i, requests) = setup();
      i.tap(Square.e2);
      expect(i.tap(Square.e4), TapOutcome.moved);
      expect(requests, [(Square.e2, Square.e4)]);
      expect(i.controller.pieceAt(Square.e4), Piece.whitePawn);
      expect(i.selection.value, isNull);
    });

    test('tapping a capture destination makes the capture', () {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('d5');
      final (i, _) = setup(c);
      i.tap(Square.e4);
      expect(i.tap(Square.d5), TapOutcome.moved);
      expect(c.lastMove!.isCapture, isTrue);
    });

    test('tapping the selected piece again deselects it', () {
      final (i, _) = setup();
      i.tap(Square.g1);
      expect(i.tap(Square.g1), TapOutcome.deselected);
      expect(i.selection.value, isNull);
    });

    test('tapping another piece of the side to move switches selection', () {
      final (i, _) = setup();
      i.tap(Square.g1);
      expect(i.tap(Square.b1), TapOutcome.selected);
      expect(i.selection.value, Square.b1);
    });

    test('a piece with no legal moves can still be selected', () {
      final (i, _) = setup();
      expect(i.tap(Square.a1), TapOutcome.selected);
      expect(i.tap(Square.d1), TapOutcome.selected);
    });

    test('tapping an illegal empty square clears the selection', () {
      final (i, requests) = setup();
      i.tap(Square.e2);
      expect(i.tap(Square.e5), TapOutcome.illegal);
      expect(i.selection.value, isNull);
      expect(requests, isEmpty);
      expect(i.controller.fen, kInitialFen);
    });

    test(
      'tapping an opponent piece it cannot capture clears the selection',
      () {
        final (i, requests) = setup();
        i.tap(Square.e2);
        expect(i.tap(Square.e7), TapOutcome.illegal);
        expect(i.selection.value, isNull);
        expect(requests, isEmpty);
      },
    );

    test('with nothing selected, empty squares and opponent pieces are '
        'ignored without notifying', () {
      final (i, _) = setup();
      var notified = 0;
      i.selection.addListener(() => notified++);
      expect(i.tap(Square.e4), TapOutcome.ignored);
      expect(i.tap(Square.e7), TapOutcome.ignored);
      expect(i.selection.value, isNull);
      expect(notified, 0);
    });

    test('after a move it is the other side that can select', () {
      final (i, _) = setup();
      i.tap(Square.e2);
      i.tap(Square.e4);
      expect(i.tap(Square.e4), TapOutcome.ignored, reason: 'white just moved');
      expect(i.tap(Square.e7), TapOutcome.selected);
    });

    test('a rejected move request keeps the selection cleared', () {
      final c = ChessBoardController();
      final i = BoardInteraction(controller: c, onMove: (_, _) => false);
      i.tap(Square.e2);
      expect(i.tap(Square.e4), TapOutcome.illegal);
      expect(i.selection.value, isNull);
    });
  });

  group('press and release', () {
    test('pressing a piece selects it at once', () {
      final (i, _) = setup();
      expect(i.pressDown(Square.e2), TapOutcome.selected);
      expect(i.selection.value, Square.e2);
      expect(i.pressUp(dragged: false), isFalse);
      expect(i.selection.value, Square.e2);
    });

    test('pressing a legal destination moves at once', () {
      final (i, requests) = setup();
      i.tap(Square.e2);
      expect(i.pressDown(Square.e4), TapOutcome.moved);
      expect(requests, [(Square.e2, Square.e4)]);
    });

    test(
      'pressing the selected piece deselects it only on a plain release',
      () {
        final (i, _) = setup();
        i.tap(Square.e2);
        expect(i.pressDown(Square.e2), TapOutcome.pressedSelected);
        expect(i.selection.value, Square.e2);
        expect(i.pressUp(dragged: true), isFalse);
        expect(i.selection.value, Square.e2, reason: 'a drag keeps it');

        i.pressDown(Square.e2);
        expect(i.pressUp(dragged: false), isTrue);
        expect(i.selection.value, isNull);
      },
    );

    test('a cancelled press on the selected piece keeps it', () {
      final (i, _) = setup();
      i.tap(Square.e2);
      i.pressDown(Square.e2);
      i.pressCancel();
      expect(i.pressUp(dragged: false), isFalse);
      expect(i.selection.value, Square.e2);
    });

    test('a fresh selection is not undone by its own release', () {
      final (i, _) = setup();
      i.pressDown(Square.g1);
      expect(i.pressUp(dragged: false), isFalse);
      expect(i.selection.value, Square.g1);
    });
  });

  group('resolveTarget', () {
    test('a legal destination maps to itself', () {
      final (i, _) = setup();
      expect(i.resolveTarget(Square.g1, Square.f3), Square.f3);
      expect(i.resolveTarget(Square.g1, Square.g3), isNull);
    });

    test('king onto own rook maps to the castling square', () {
      final c = ChessBoardController(
        fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
      );
      final (i, _) = setup(c);
      expect(i.resolveTarget(Square.e1, Square.h1), Square.g1);
      expect(i.resolveTarget(Square.e1, Square.a1), Square.c1);
    });

    test('only a king onto its own rook, on the same rank, castles', () {
      final c = ChessBoardController(
        fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
      );
      final (i, _) = setup(c);
      // A rook onto its king is not castling.
      expect(i.resolveTarget(Square.h1, Square.e1), isNull);
      // The opponent's rook is a capture target, not castling.
      expect(i.resolveTarget(Square.e1, Square.h8), isNull);
    });

    test('no castling rights, no castling', () {
      final c = ChessBoardController(fen: 'r3k2r/8/8/8/8/8/8/R3K2R w kq - 0 1');
      final (i, _) = setup(c);
      expect(i.resolveTarget(Square.e1, Square.h1), isNull);
    });

    test('a rook on another rank never counts as castling', () {
      // Without the same-rank guard, king e1 onto the rook on h2 would
      // pick the kingside castle.
      final c = ChessBoardController(
        fen: '4k3/8/8/8/8/8/7R/R3K2R w KQ - 0 1',
      );
      final (i, _) = setup(c);
      expect(i.resolveTarget(Square.e1, Square.h2), isNull);
    });

    test('dropping the king on its rook when castling is illegal is '
        'rejected', () {
      final c = ChessBoardController(
        fen: 'r3k2r/8/8/8/8/8/8/R3K2R w kq - 0 1',
      );
      final (i, requests) = setup(c);
      expect(i.drop(Square.e1, Square.h1), TapOutcome.illegal);
      expect(requests, isEmpty);
    });

    test('a drop of the king on its rook castles', () {
      final c = ChessBoardController(
        fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
      );
      final (i, requests) = setup(c);
      expect(i.drop(Square.e1, Square.a1), TapOutcome.moved);
      expect(requests, [(Square.e1, Square.c1)]);
    });
  });

  group('who can move', () {
    test('read-only boards accept no selection', () {
      final (i, _) = setup();
      i.readOnly = true;
      expect(i.tap(Square.e2), TapOutcome.ignored);
      expect(i.selection.value, isNull);
    });

    test('nothing can be selected once the game is over', () {
      final c = ChessBoardController();
      for (final san in ['f3', 'e5', 'g4', 'Qh4#']) {
        c.moveSan(san);
      }
      final (i, _) = setup(c);
      expect(i.tap(Square.e1), TapOutcome.ignored);
      expect(i.tap(Square.a2), TapOutcome.ignored);
    });

    test('nothing can be selected while viewing history', () {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('e5')
        ..back();
      final (i, _) = setup(c);
      expect(i.tap(Square.e7), TapOutcome.ignored);
    });

    test('with branching allowed, moves from history are possible', () {
      final c = ChessBoardController(allowBranching: true)
        ..moveSan('e4')
        ..moveSan('e5')
        ..back();
      final (i, _) = setup(c);
      expect(i.tap(Square.d7), TapOutcome.selected);
      expect(i.tap(Square.d5), TapOutcome.moved);
      expect(c.fullLine.map((m) => m.san), ['e4', 'd5']);
    });

    test('interactive side limits which color the user moves', () {
      final (i, _) = setup();
      i.interactiveSide = InteractiveSide.black;
      expect(i.tap(Square.e2), TapOutcome.ignored, reason: 'white is not ours');
      i.controller.move(Square.e2, Square.e4);
      expect(i.tap(Square.e7), TapOutcome.selected);

      i.interactiveSide = InteractiveSide.white;
      i.clear();
      expect(i.tap(Square.e7), TapOutcome.ignored);
    });

    test('InteractiveSide.allows', () {
      expect(InteractiveSide.both.allows(PieceColor.white), isTrue);
      expect(InteractiveSide.both.allows(PieceColor.black), isTrue);
      expect(InteractiveSide.white.allows(PieceColor.black), isFalse);
      expect(InteractiveSide.black.allows(PieceColor.black), isTrue);
    });

    test('a selection that becomes invalid is dropped on revalidate', () {
      final (i, _) = setup();
      i.tap(Square.e2);
      i.readOnly = true;
      i.revalidate();
      expect(i.selection.value, isNull);

      i.readOnly = false;
      i.tap(Square.e2);
      i.revalidate();
      expect(i.selection.value, Square.e2, reason: 'still valid');
    });
  });
}
