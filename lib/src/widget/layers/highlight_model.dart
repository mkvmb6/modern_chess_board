import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../controller/chess_board_controller.dart';
import '../../model/board_move.dart';
import '../../model/piece.dart';
import '../../model/square.dart';
import '../../theme/chess_board_theme.dart';

/// How a legal destination is marked.
enum LegalMarker {
  /// A small dot on an empty square.
  dot,

  /// A ring around a square the piece can capture on, or the own rook a
  /// selected king can castle onto.
  ring,
}

/// Everything the highlight layer paints, worked out from the position, the
/// selection and the theme. Compared by value, so the painter only repaints
/// when something visible changed.
@immutable
class BoardHighlights {
  const BoardHighlights._({
    required this.tints,
    required this.markers,
    required this.hover,
    required this.markerColor,
    required this.hoverColor,
    this.focus,
    this.focusColor = const Color(0x00000000),
  });

  /// No highlights at all.
  static const empty = BoardHighlights._(
    tints: {},
    markers: {},
    hover: null,
    markerColor: Color(0x00000000),
    hoverColor: Color(0x00000000),
  );

  /// Works out the highlights.
  ///
  /// Each square gets at most one tint, picked in priority order: king in
  /// check or checkmated, then the selection, then a queued premove, then
  /// the last move. So a selected square that is also part of the last
  /// move is tinted once, with the selection color.
  ///
  /// When [premoveTargets] is given, the selected piece is being premoved:
  /// those squares are marked instead of its legal moves.
  factory BoardHighlights.compute({
    required ChessBoardController controller,
    required Square? selected,
    required Square? hover,
    required bool showLastMove,
    required ChessBoardTheme theme,
    ({Square from, Square to})? premove,
    Set<Square>? premoveTargets,
    Square? focus,
  }) {
    final tints = <Square, Color>{};
    if (showLastMove) {
      if (controller.lastMove case final BoardMove m) {
        tints[m.from] = theme.lastMoveColor;
        tints[m.to] = theme.lastMoveColor;
      }
    }
    if (premove != null) {
      tints[premove.from] = theme.premoveColor;
      tints[premove.to] = theme.premoveColor;
    }
    if (selected != null) tints[selected] = theme.selectionColor;

    final kingColor = controller.isCheckmate
        ? theme.checkmateColor
        : controller.isCheck
        ? theme.checkColor
        : null;
    if (kingColor != null) {
      final king = Piece(controller.turn, PieceType.king);
      for (final MapEntry(key: square, value: piece)
          in controller.pieces.entries) {
        if (piece == king) tints[square] = kingColor;
      }
    }

    final markers = <Square, LegalMarker>{};
    var hoverShown = false;
    if (selected != null && premoveTargets != null) {
      for (final square in premoveTargets) {
        // A ring where something stands: a capture, or castling onto the
        // rook. A dot elsewhere.
        markers[square] = controller.pieceAt(square) == null
            ? LegalMarker.dot
            : LegalMarker.ring;
        if (square == hover) hoverShown = true;
      }
    } else if (selected != null) {
      for (final m in controller.legalMovesFrom(selected)) {
        markers[m.to] = m.isCapture ? LegalMarker.ring : LegalMarker.dot;
        if (m.to == hover) hoverShown = true;
        // A king can also castle by moving onto its own rook: ring that
        // rook so the move is visible before it's made.
        if (m.castle case final CastleSide side) {
          final rank = selected.rank;
          final rook = Square.at(side == CastleSide.kingside ? 7 : 0, rank);
          final piece = controller.pieceAt(rook);
          if (piece != null &&
              piece.type == PieceType.rook &&
              piece.color == controller.turn) {
            markers[rook] = LegalMarker.ring;
            if (rook == hover) hoverShown = true;
          }
        }
      }
    }

    return BoardHighlights._(
      tints: Map.unmodifiable(tints),
      markers: Map.unmodifiable(markers),
      hover: hoverShown ? hover : null,
      markerColor: theme.legalMoveColor,
      hoverColor: theme.hoverColor,
      focus: focus,
      focusColor: theme.focusColor,
    );
  }

  /// The keyboard focus cursor, or null when hidden.
  final Square? focus;

  /// The color of the [focus] ring.
  final Color focusColor;

  /// One tint per square.
  final Map<Square, Color> tints;

  /// Legal-destination markers for the selected piece.
  final Map<Square, LegalMarker> markers;

  /// A legal destination under the mouse, or null.
  final Square? hover;

  /// The color of [markers].
  final Color markerColor;

  /// The color of the [hover] tint.
  final Color hoverColor;

  @override
  bool operator ==(Object other) =>
      other is BoardHighlights &&
      other.hover == hover &&
      other.focus == focus &&
      other.focusColor == focusColor &&
      other.markerColor == markerColor &&
      other.hoverColor == hoverColor &&
      mapEquals(other.tints, tints) &&
      mapEquals(other.markers, markers);

  @override
  int get hashCode => Object.hash(
    hover,
    focus,
    focusColor,
    markerColor,
    hoverColor,
    Object.hashAllUnordered(
      tints.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      markers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
