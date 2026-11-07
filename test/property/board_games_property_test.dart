import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/squares_layer.dart';

/// Random legal games played through the board widget: each move is made
/// by tapping or dragging, in a random orientation, and after every move
/// the pieces drawn on screen must match the controller's position.
///
/// `glados` drives the pure property tests; its runner doesn't fit
/// `testWidgets`, so these games use fixed seeds instead. A failure names
/// its seed, so it can be replayed with [playGame].

const _starts = [
  kInitialFen,
  // Promotions for both sides, with pieces to capture on the way.
  'r1n4k/1PPP4/8/8/8/8/1ppp4/R1N4K w - - 0 1',
  // Castling either way for both sides.
  'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
  // En passant available at once.
  '4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1',
];

Widget _host(ChessBoard board) => MaterialApp(
  home: MediaQuery(
    // Animations would only slow the games down; they are covered elsewhere.
    data: const MediaQueryData(disableAnimations: true),
    child: Material(
      child: Center(child: SizedBox.square(dimension: 400, child: board)),
    ),
  ),
);

Finder _squares() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is BoardSquaresPainter,
);

/// The square under the center of each drawn piece, mapped to the piece.
Map<Square, Piece> renderedPieces(WidgetTester tester) {
  final origin = tester.getTopLeft(_squares());
  final geometry =
      (tester.widget<CustomPaint>(_squares()).painter! as BoardSquaresPainter)
          .geometry;
  final out = <Square, Piece>{};
  for (final element in find.byType(ChessPieceView).evaluate()) {
    final view = element.widget as ChessPieceView;
    final box = element.renderObject! as RenderBox;
    // Only pieces on the board, not the promotion picker's choices.
    if (!box.hasSize || !box.attached) continue;
    final center = box.localToGlobal(box.size.center(Offset.zero)) - origin;
    final square = geometry.squareAt(center);
    if (square == null) continue;
    expect(out.containsKey(square), isFalse, reason: 'two pieces on $square');
    out[square] = view.piece;
  }
  return out;
}

Offset _center(WidgetTester tester, Square square) =>
    tester.getTopLeft(_squares()) +
    (tester.widget<CustomPaint>(_squares()).painter! as BoardSquaresPainter)
        .geometry
        .squareCenter(square);

/// Plays [length] random moves from start [start] with [seed], alternating
/// taps and drags, and checks the drawn board after each one.
Future<void> playGame(
  WidgetTester tester, {
  required int seed,
  required int start,
  required int length,
}) async {
  final rng = Random(seed);
  final c = ChessBoardController(fen: _starts[start]);
  final orientation = rng.nextBool()
      ? BoardOrientation.white
      : BoardOrientation.black;
  final board = ChessBoard(
    controller: c,
    orientation: orientation,
    // The picker would need a separate choice step; promotions are covered
    // by their own tests, so pawns promote to a queen here.
    autoQueen: true,
  );
  await tester.pumpWidget(_host(board));
  final context = tester.element(find.byType(ChessBoard));
  await tester.runAsync(() => board.pieceSet.precache(context));
  await tester.pump();

  for (var i = 0; i < length && !c.isGameOver; i++) {
    final moves = c.legalMoves;
    final pick = moves[rng.nextInt(moves.length)];
    final from = _center(tester, pick.from);
    final to = _center(tester, pick.to);
    if (rng.nextBool()) {
      await tester.tapAt(from);
      await tester.pump();
      await tester.tapAt(to);
    } else {
      final g = await tester.startGesture(from);
      await g.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await g.moveTo(to);
      await tester.pump();
      await g.up();
    }
    await tester.pumpAndSettle();
    final reason = 'seed $seed, start $start, move ${i + 1} (${pick.san})';
    expect(c.history.length, i + 1, reason: '$reason: move not played');
    expect(renderedPieces(tester), c.pieces, reason: reason);
  }
}

void main() {
  for (var seed = 0; seed < 12; seed++) {
    final start = seed % _starts.length;
    testWidgets('random game, seed $seed', (tester) async {
      await playGame(tester, seed: seed, start: start, length: 30);
    });
  }
}
