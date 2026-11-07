import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../controller/chess_board_controller.dart';
import '../../model/square.dart';
import '../board_geometry.dart';

/// What screen readers learn about one square: its label, whether it is
/// selected, and whether the selected piece can move there.
@immutable
class SquareSemantics {
  /// Creates the description of one square.
  const SquareSemantics({
    required this.label,
    required this.selected,
    this.hint,
  });

  /// For example "e4, white pawn" or "e4, empty".
  final String label;

  /// Whether this square's piece is selected.
  final bool selected;

  /// Extra state, such as "legal move" when the selected piece can move
  /// here, or null.
  final String? hint;

  @override
  bool operator ==(Object other) =>
      other is SquareSemantics &&
      other.label == label &&
      other.selected == selected &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(label, selected, hint);
}

/// The label for [square]: its name and what stands on it.
String squareLabel(ChessBoardController c, Square square) {
  final piece = c.pieceAt(square);
  return '${square.name}, ${piece == null ? 'empty' : piece.label}';
}

/// A grid of 64 semantic nodes, one per square, laid over the board so a
/// screen reader can explore it square by square and make moves with the
/// standard activate gesture.
///
/// Nothing here paints or takes pointer input: the board's own gesture
/// layer handles touches, and [onActivate] handles only a screen reader's
/// activation, going through the same tap rules. Squares are listed rank
/// by rank from the top of the screen, left to right, so reading order
/// follows the board as it is drawn.
class BoardSemanticsLayer extends StatelessWidget {
  /// Creates the grid.
  const BoardSemanticsLayer({
    super.key,
    required this.geometry,
    required this.describe,
    required this.listenable,
    required this.onActivate,
  });

  /// Where squares are.
  final BoardGeometry geometry;

  /// What each square says, worked out when [listenable] notifies.
  final SquareSemantics Function(Square square) describe;

  /// Notifies when any square's description may have changed.
  final Listenable listenable;

  /// Activates [square], or null when the board can't be used (read-only
  /// or interaction off), so squares offer no tap action.
  final void Function(Square square)? onActivate;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: listenable,
    builder: (context, _) {
      final activate = onActivate;
      final white = geometry.orientation == BoardOrientation.white;
      return Stack(
        children: [
          for (var row = 0; row < 8; row++)
            for (var col = 0; col < 8; col++)
              () {
                final square = Square.at(
                  white ? col : 7 - col,
                  white ? 7 - row : row,
                );
                final d = describe(square);
                return Positioned.fromRect(
                  rect: geometry.squareRect(square),
                  child: Semantics(
                    // Each square is its own node, read on its own.
                    container: true,
                    sortKey: OrdinalSortKey(row * 8.0 + col),
                    label: d.label,
                    button: activate != null,
                    selected: d.selected,
                    hint: d.hint,
                    onTap: activate == null ? null : () => activate(square),
                    child: const SizedBox.expand(),
                  ),
                );
              }(),
        ],
      );
    },
  );
}
