import 'package:flutter/material.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

/// How a game's half-moves map to score-sheet rows: which move number the
/// game starts at, and whether black moved first (so the first row's white
/// cell is "…").
class MoveNumbering {
  /// Works out the numbering for [controller]'s starting position.
  MoveNumbering(ChessBoardController controller) {
    final fields = controller.startingFen.split(' ');
    blackFirst = fields.length > 1 && fields[1] == 'b';
    firstNumber = fields.length > 5 ? int.tryParse(fields[5]) ?? 1 : 1;
  }

  /// Whether the first half-move is black's.
  late final bool blackFirst;

  /// The move number of the first row.
  late final int firstNumber;

  int get _offset => blackFirst ? 1 : 0;

  /// The move number of half-move [ply] (0 for the first move played).
  int numberOf(int ply) => firstNumber + (ply + _offset) ~/ 2;

  /// Whether half-move [ply] is white's.
  bool isWhite(int ply) => (ply + _offset).isEven;

  /// The row half-move [ply] sits in.
  int rowOf(int ply) => (ply + _offset) ~/ 2;

  /// How many rows [plies] half-moves take.
  int rows(int plies) => ((plies + _offset) / 2).ceil();

  /// The half-move in [row]'s white or black cell (may be out of range).
  int plyAt(int row, {required bool white}) =>
      row * 2 - _offset + (white ? 0 : 1);

  /// Half-move [ply] written as on a score sheet: "12. Nf3" or "12… e5".
  String describe(int ply, String san) =>
      '${numberOf(ply)}${isWhite(ply) ? '.' : '…'} $san';
}

/// The moves of the game laid out like a printed score sheet: a move
/// number, then white's and black's move in aligned columns. Tapping a
/// move shows that position; the buttons below step through the game.
class ScoreSheet extends StatefulWidget {
  /// Creates the score sheet for [controller].
  const ScoreSheet({
    super.key,
    required this.controller,
    this.showNavigation = true,
  });

  /// The game.
  final ChessBoardController controller;

  /// Whether the first/previous/next/last buttons show under the moves.
  /// Small screens put previous and next in their toolbar instead.
  final bool showNavigation;

  @override
  State<ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<ScoreSheet> {
  final _scroll = ScrollController();

  /// Each row's height; rows are all the same, so the current move can be
  /// scrolled into view without measuring.
  static const _rowHeight = 30.0;

  int _shownPly = -1;
  int _shownLength = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the current move in view, but only when the move or the game
  /// changed (not on every rebuild).
  void _followCurrent(MoveNumbering n, int ply, int length) {
    if (ply == _shownPly && length == _shownLength) return;
    _shownPly = ply;
    _shownLength = length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final row = ply == 0 ? 0 : n.rowOf(ply - 1);
      final top = row * _rowHeight;
      final bottom = top + _rowHeight;
      final viewTop = position.pixels;
      final viewBottom = viewTop + position.viewportDimension;
      double? target;
      if (top < viewTop) target = top;
      if (bottom > viewBottom) target = bottom - position.viewportDimension;
      if (target == null) return;
      _scroll.animateTo(
        target.clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final line = c.fullLine;
    final n = MoveNumbering(c);
    final result = c.isGameOver && !c.isViewingHistory ? c.result : null;
    final rows = n.rows(line.length) + (result == null ? 0 : 1);
    _followCurrent(n, c.ply, line.length);

    final figures = text.bodyLarge!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.2,
    );
    final muted = figures.copyWith(color: scheme.onSurfaceVariant);

    Widget cell(int ply, {required bool white}) {
      if (ply < 0) {
        // Black moved first: the white cell of the first row.
        return white && n.blackFirst
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('…', style: muted),
              )
            : const SizedBox();
      }
      if (ply >= line.length) return const SizedBox();
      final current = c.ply == ply + 1;
      final san = line[ply].san ?? '?';
      return Semantics(
        button: true,
        selected: current,
        label: '${n.describe(ply, san)}, ${white ? 'white' : 'black'}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => c.goTo(ply + 1),
          child: Container(
            height: _rowHeight - 4,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: current
                ? BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(
              san,
              style: figures.copyWith(
                fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                color: current ? scheme.onPrimaryContainer : null,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: line.isEmpty
              ? Center(
                  child: Text(
                    'Moves appear here as you play.',
                    style: text.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  itemExtent: _rowHeight,
                  itemCount: rows,
                  itemBuilder: (context, row) {
                    if (result != null && row == rows - 1) {
                      return Center(
                        child: Text(
                          switch (result) {
                            GameResult.draw => '½–½',
                            GameResult.whiteWins => '1–0',
                            GameResult.blackWins => '0–1',
                            GameResult.ongoing => '',
                          },
                          style: figures.copyWith(fontWeight: FontWeight.w600),
                        ),
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${n.firstNumber + row}.',
                            textAlign: TextAlign.right,
                            style: muted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: cell(n.plyAt(row, white: true), white: true),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: cell(
                              n.plyAt(row, white: false),
                              white: false,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        if (widget.showNavigation) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'First position',
                onPressed: c.canGoBack ? c.goToStart : null,
                icon: const Icon(Icons.first_page),
              ),
              IconButton(
                tooltip: 'Previous move',
                onPressed: c.canGoBack ? c.back : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next move',
                onPressed: c.canGoForward ? c.forward : null,
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Latest position',
                onPressed: c.canGoForward ? c.goToEnd : null,
                icon: const Icon(Icons.last_page),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One line saying whose turn it is, or how the game ended.
String statusLine(ChessBoardController c) {
  if (c.isViewingHistory) {
    if (c.ply == 0) {
      return 'Looking at the starting position. Step forward, or jump to '
          'the latest position.';
    }
    final n = MoveNumbering(c);
    final ply = c.ply - 1;
    final san = c.fullLine[ply].san ?? '?';
    return 'Looking back at ${n.describe(ply, san)}. Play on from here, or '
        'jump to the latest position.';
  }
  final side = c.turn == PieceColor.white ? 'White' : 'Black';
  final other = c.turn == PieceColor.white ? 'Black' : 'White';
  if (c.isCheckmate) return 'Checkmate. $other wins.';
  if (c.isDraw) {
    return switch (c.drawReason) {
      DrawReason.stalemate => 'Stalemate. The game is drawn.',
      DrawReason.fiftyMoveRule => 'Draw by the fifty-move rule.',
      DrawReason.threefoldRepetition => 'Draw by threefold repetition.',
      DrawReason.insufficientMaterial => 'Draw. Neither side can checkmate.',
      null => 'The game is drawn.',
    };
  }
  if (c.isCheck) return '$side to move, in check.';
  return '$side to move.';
}
