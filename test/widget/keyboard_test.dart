import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/modern_chess_board.dart';
import 'package:modern_chess_board/src/widget/layers/highlight_layer.dart';
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

Offset centerOf(WidgetTester tester, Square square) =>
    tester.getTopLeft(_squares()) +
    (tester.widget<CustomPaint>(_squares()).painter! as BoardSquaresPainter)
        .geometry
        .squareCenter(square);

/// Gives the board keyboard focus, as a click or Tab would.
Future<void> focusBoard(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
}

/// The square the focus ring is on, or null when it isn't shown.
Square? focusRing(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is BoardMarkersPainter,
                  ),
                )
                .painter!
            as BoardMarkersPainter)
        .highlights
        .focus;

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> times(
  WidgetTester tester,
  LogicalKeyboardKey key,
  int count,
) async {
  for (var i = 0; i < count; i++) {
    await press(tester, key);
  }
}

/// Types [text], holding Shift for capitals.
Future<void> type(WidgetTester tester, String text) async {
  for (final ch in text.split('')) {
    final upper = ch != ch.toLowerCase();
    final key = switch (ch.toLowerCase()) {
      final c when RegExp('[a-z]').hasMatch(c) => LogicalKeyboardKey(
        LogicalKeyboardKey.keyA.keyId + c.codeUnitAt(0) - 'a'.codeUnitAt(0),
      ),
      final c when RegExp('[0-9]').hasMatch(c) => LogicalKeyboardKey(
        LogicalKeyboardKey.digit0.keyId + c.codeUnitAt(0) - '0'.codeUnitAt(0),
      ),
      '-' => LogicalKeyboardKey.minus,
      '=' => LogicalKeyboardKey.equal,
      _ => throw ArgumentError(ch),
    };
    if (upper) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key, character: ch);
    if (upper) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }
}

/// Toggles history navigation mode.
Future<void> toggleHistory(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'H');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  group('focus cursor', () {
    testWidgets('the ring appears on the first key, at e2 for white', (
      tester,
    ) async {
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      await focusBoard(tester);
      expect(focusRing(tester), isNull);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusRing(tester), Square.e2);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusRing(tester), Square.e3);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusRing(tester), Square.d3);
    });

    testWidgets('arrows follow the screen with black at the bottom', (
      tester,
    ) async {
      await pumpBoard(
        tester,
        ChessBoard(
          controller: ChessBoardController(),
          orientation: BoardOrientation.black,
        ),
      );
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusRing(tester), Square.e7);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusRing(tester), Square.e6);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusRing(tester), Square.f6);
    });

    testWidgets('the cursor stops at the edge', (tester) async {
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      await focusBoard(tester);
      await times(tester, LogicalKeyboardKey.arrowDown, 5);
      expect(focusRing(tester), Square.e1);
    });

    testWidgets('a pointer press hides the ring', (tester) async {
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await tester.tapAt(centerOf(tester, Square.a1));
      await tester.pump();
      expect(focusRing(tester), isNull);
    });

    testWidgets('disabled: no focus, no keys', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c, enableKeyboard: false));
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.enter);
      expect(focusRing(tester), isNull);
    });
  });

  group('playing with keys', () {
    testWidgets('Enter on e2 then e4 plays e4, and reports it', (tester) async {
      final c = ChessBoardController();
      final moves = <BoardMove>[];
      await pumpBoard(tester, ChessBoard(controller: c, onMove: moves.add));
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp); // shows e2
      await press(tester, LogicalKeyboardKey.enter);
      await times(tester, LogicalKeyboardKey.arrowUp, 2);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e4), Piece.whitePawn);
      expect(moves.single.san, 'e4');
    });

    testWidgets('Space works like Enter', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.space);
      await times(tester, LogicalKeyboardKey.arrowUp, 1);
      await press(tester, LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.e3), Piece.whitePawn);
    });

    testWidgets('Escape clears the selection', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.escape);
      await times(tester, LogicalKeyboardKey.arrowUp, 2);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // e4 was pressed with nothing selected: nothing moved.
      expect(c.pieceAt(Square.e2), Piece.whitePawn);
    });

    testWidgets('keys follow the same rules: castling onto the rook', (
      tester,
    ) async {
      final c = ChessBoardController(
        fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
      );
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp); // e2
      await press(tester, LogicalKeyboardKey.arrowDown); // e1
      await press(tester, LogicalKeyboardKey.enter);
      await times(tester, LogicalKeyboardKey.arrowRight, 3); // h1
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.lastMove?.castle, CastleSide.kingside);
    });
  });

  group('typing moves', () {
    testWidgets('Nf3 plus Enter plays the move and reports it', (tester) async {
      final c = ChessBoardController();
      final moves = <BoardMove>[];
      await pumpBoard(tester, ChessBoard(controller: c, onMove: moves.add));
      await focusBoard(tester);
      await type(tester, 'Nf3');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.f3), Piece.whiteKnight);
      expect(moves.single.san, 'Nf3');
    });

    testWidgets('the typed text is shown while typing', (tester) async {
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      await focusBoard(tester);
      await type(tester, 'e4');
      expect(find.text('e4'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.backspace);
      expect(find.text('e'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.text('e'), findsNothing);
    });

    testWidgets('an illegal move is rejected and can be corrected', (
      tester,
    ) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await type(tester, 'e5');
      await press(tester, LogicalKeyboardKey.enter);
      expect(c.history, isEmpty);
      // The text stays so it can be fixed.
      await press(tester, LogicalKeyboardKey.backspace);
      await type(tester, '4');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.lastMove?.san, 'e4');
    });

    testWidgets('a typed move obeys the interactive side', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(
        tester,
        ChessBoard(controller: c, interactiveSide: InteractiveSide.black),
      );
      await focusBoard(tester);
      await type(tester, 'e4');
      await press(tester, LogicalKeyboardKey.enter);
      expect(c.history, isEmpty);
    });

    testWidgets('castling can be typed', (tester) async {
      final c = ChessBoardController(
        fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
      );
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await type(tester, 'O-O-O');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.lastMove?.castle, CastleSide.queenside);
    });
  });

  group('review fixes', () {
    testWidgets('lowercase nf3 plays the knight, not a pawn', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await type(tester, 'nf3');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.lastMove?.san, 'Nf3');
    });

    testWidgets('qh5 never becomes a pawn move', (tester) async {
      final c = ChessBoardController()
        ..moveSan('e4')
        ..moveSan('a6')
        ..moveSan('h4')
        ..moveSan('a5');
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await type(tester, 'qh5');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.lastMove?.san, 'Qh5');
    });

    testWidgets('bxc3 is the pawn, Bxc3 the bishop', (tester) async {
      // A b-pawn and a bishop can both take the knight on c3.
      final c = ChessBoardController(
        fen: '4k3/8/8/4b3/1p6/2N5/8/4K3 b - - 0 1',
      );
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await type(tester, 'bxc3');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.lastMove?.piece?.type, PieceType.pawn);
    });

    testWidgets('a coordinate move such as e2e4 works', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await type(tester, 'e2e4');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.lastMove?.san, 'e4');
    });

    testWidgets('the promotion picker works from the keyboard', (tester) async {
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp); // e2
      await times(tester, LogicalKeyboardKey.arrowLeft, 4); // a2
      await times(tester, LogicalKeyboardKey.arrowUp, 5); // a7
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.arrowUp); // a8
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('promotion-queen')), findsOneWidget);
      // Arrows move within the picker, not the board cursor beneath.
      await press(tester, LogicalKeyboardKey.arrowDown); // queen highlighted
      await press(tester, LogicalKeyboardKey.arrowDown); // knight
      expect(focusRing(tester), Square.a8);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.a8), Piece.whiteKnight);
    });

    testWidgets('a letter picks a promotion piece directly', (tester) async {
      final c = ChessBoardController(fen: '7k/P7/8/8/8/8/8/K7 w - - 0 1');
      await pumpBoard(tester, ChessBoard(controller: c));
      await tester.tapAt(centerOf(tester, Square.a7));
      await tester.pump();
      await tester.tapAt(centerOf(tester, Square.a8));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR, character: 'r');
      await tester.pumpAndSettle();
      expect(c.pieceAt(Square.a8), Piece.whiteRook);
    });

    testWidgets('modifier shortcuts and unused Escape reach the app', (
      tester,
    ) async {
      var copies = 0;
      var escapes = 0;
      final c = ChessBoardController();
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.keyC,
                control: true,
              ): () =>
                  copies++,
              const SingleActivator(LogicalKeyboardKey.escape): () => escapes++,
            },
            child: Material(
              child: Center(
                child: SizedBox.square(
                  dimension: 400,
                  child: ChessBoard(controller: c),
                ),
              ),
            ),
          ),
        ),
      );
      await focusBoard(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'c');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await press(tester, LogicalKeyboardKey.escape);
      expect(copies, 1);
      expect(escapes, 1);
      expect(find.text('c'), findsNothing);
    });

    testWidgets('losing focus ends navigation mode', (tester) async {
      final c = ChessBoardController();
      final other = FocusNode();
      addTearDown(other.dispose);
      final board = ChessBoard(controller: c);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Column(
              children: [
                SizedBox.square(dimension: 400, child: board),
                Focus(focusNode: other, child: const SizedBox(height: 10)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await focusBoard(tester);
      await toggleHistory(tester);
      expect(find.textContaining('History'), findsOneWidget);
      other.requestFocus();
      // Focus changes settle after the frame, then the pill rebuilds.
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('History'), findsNothing);
    });

    testWidgets('a controller swap drops typed text', (tester) async {
      final c = ChessBoardController();
      await pumpBoard(tester, ChessBoard(controller: c));
      await focusBoard(tester);
      await type(tester, 'e4');
      final next = ChessBoardController();
      await tester.pumpWidget(host(ChessBoard(controller: next)));
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(next.history, isEmpty);
    });

    testWidgets('a read-only board ignores typing', (tester) async {
      final c = ChessBoardController()..moveSan('e4');
      await pumpBoard(tester, ChessBoard(controller: c, readOnly: true));
      await focusBoard(tester);
      await type(tester, 'e5');
      expect(find.text('e5'), findsNothing);
    });

    testWidgets('holding Backspace keeps deleting', (tester) async {
      await pumpBoard(tester, ChessBoard(controller: ChessBoardController()));
      await focusBoard(tester);
      await type(tester, 'Nf3');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.text('N'), findsOneWidget);
    });
  });

  group('navigation mode', () {
    testWidgets(
      'Shift+H toggles it; left and right then step through history',
      (tester) async {
        final c = ChessBoardController()
          ..moveSan('e4')
          ..moveSan('e5');
        await pumpBoard(tester, ChessBoard(controller: c));
        await focusBoard(tester);
        await toggleHistory(tester);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(c.ply, 1);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(c.ply, 0);
        await press(tester, LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(c.ply, 1);
        // Home and End jump.
        await press(tester, LogicalKeyboardKey.end);
        expect(c.ply, 2);
        await press(tester, LogicalKeyboardKey.home);
        expect(c.ply, 0);
        // Shift+H again: arrows move the cursor, not the game.
        await toggleHistory(tester);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(c.ply, 0);
      },
    );

    testWidgets('a read-only board is always in navigation mode', (
      tester,
    ) async {
      final c = ChessBoardController()..moveSan('e4');
      await pumpBoard(tester, ChessBoard(controller: c, readOnly: true));
      await focusBoard(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(c.ply, 0);
    });
  });
}
