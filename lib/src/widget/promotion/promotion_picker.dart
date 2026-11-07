import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../model/piece.dart';
import '../../model/square.dart';
import '../../pieces/piece_set.dart';
import '../../theme/chess_board_theme.dart';
import '../board_geometry.dart';

/// A pending promotion: which pawn is promoting, where, and how to finish.
///
/// Passed to a custom [PromotionPickerBuilder]. Call [choose] with the
/// piece the user picked, or [cancel] to take the move back. A new request
/// is built on every rebuild, so requests are not compared by value.
@immutable
class PromotionRequest {
  /// Creates a request.
  const PromotionRequest({
    required this.from,
    required this.to,
    required this.color,
    required this.squareRect,
    required this.choose,
    required this.cancel,
  });

  /// The pawn's square.
  final Square from;

  /// The promotion square on the last rank.
  final Square to;

  /// The promoting side.
  final PieceColor color;

  /// Where [to] is drawn, in the coordinates of the area the picker is laid
  /// over, so a custom picker can place itself over the promotion square.
  /// Its width is the square size.
  final Rect squareRect;

  /// Completes the move, promoting to [type] (queen, rook, bishop or knight).
  final ValueChanged<PieceType> choose;

  /// Cancels the move and leaves the position unchanged.
  final VoidCallback cancel;
}

/// Builds a custom promotion picker, laid over the whole board.
///
/// Taps on the area around the picker cancel the promotion, as do Escape
/// and the system Back action.
typedef PromotionPickerBuilder =
    Widget Function(BuildContext context, PromotionRequest request);

/// The pieces offered, in order from the promotion square inward: the queen
/// is where the pawn lands, so the common choice needs no aiming.
const List<PieceType> kPromotionChoices = [
  PieceType.queen,
  PieceType.knight,
  PieceType.rook,
  PieceType.bishop,
];

/// How long the picker takes to appear.
const Duration kPromotionPickerAppear = Duration(milliseconds: 120);

/// The default picker: the four choices in a column from the promotion
/// square toward the middle of the board, over a dimmed board.
///
/// It appears with a short fade and grows out of the promotion square, or
/// at once when the platform asks for reduced motion. Tapping anywhere
/// outside the column cancels. Escape and Back are handled by the board.
///
/// From the keyboard, up and down move between the choices (the queen is
/// highlighted first), Enter or Space picks the highlighted one, and Q, R,
/// B or N pick a piece directly.
class PromotionPicker extends StatefulWidget {
  /// Creates the default picker.
  const PromotionPicker({
    super.key,
    required this.request,
    required this.geometry,
    required this.pieceSet,
    required this.theme,
  });

  /// What is being promoted.
  final PromotionRequest request;

  /// Where squares are.
  final BoardGeometry geometry;

  /// The artwork for the choices.
  final PieceSet pieceSet;

  /// Colors for the scrim and the choice background.
  final ChessBoardTheme theme;

  @override
  State<PromotionPicker> createState() => _PromotionPickerState();
}

class _PromotionPickerState extends State<PromotionPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: kPromotionPickerAppear,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appear.isDismissed) {
      final reduceMotion =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduceMotion) {
        _appear.value = 1;
      } else {
        _appear.forward();
      }
    }
  }

  /// Takes keyboard focus once shown. Key events travel from the focused
  /// node up, so the picker must hold focus to see them; the board's
  /// promotion scope above it still counts as focused.
  final FocusNode _keys = FocusNode(debugLabel: 'promotion choices');

  @override
  void initState() {
    super.initState();
    // Runs after the scope's own focus request (the scope builds first),
    // so the picker ends up with focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keys.requestFocus();
    });
  }

  @override
  void dispose() {
    _appear.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// The highlighted choice for keyboard users, or null until a key is
  /// pressed (so pointer users never see it).
  int? _keyChoice;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final request = widget.request;
    final key = event.logicalKey;
    // The column runs from the promotion square toward the center; on
    // screen that is down when the promotion square is at the top.
    final towardCenterIsDown =
        widget.geometry.squareCenter(request.to).dy <
        widget.geometry.boardRect.center.dy;
    int move(int by) {
      final current = _keyChoice;
      if (current == null) return 0;
      return (current + by).clamp(0, kPromotionChoices.length - 1);
    }

    switch (key) {
      case LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowUp:
        final down = key == LogicalKeyboardKey.arrowDown;
        setState(() => _keyChoice = move(down == towardCenterIsDown ? 1 : -1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space:
        if (event is KeyRepeatEvent) return KeyEventResult.handled;
        request.choose(kPromotionChoices[_keyChoice ?? 0]);
        return KeyEventResult.handled;
    }
    final type = PieceType.fromLetter(event.character?.toLowerCase() ?? '');
    if (type != null && kPromotionChoices.contains(type)) {
      request.choose(type);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final geometry = widget.geometry;
    final theme = widget.theme;
    final size = geometry.squareSize;
    // Squares from the promotion square toward the board's center, in
    // board terms: down the file for a promotion on rank 8, up for rank 1.
    final step = request.to.rank == 7 ? -1 : 1;
    final squares = [
      for (var i = 0; i < 4; i++)
        Square.at(request.to.file, request.to.rank + step * i),
    ];
    final column = squares
        .map(geometry.squareRect)
        .reduce((a, b) => a.expandToInclude(b));
    // A slightly larger card, kept inside the board so its rounded corners
    // aren't clipped at the edge.
    final card = column.inflate(size * 0.04).intersect(geometry.boardRect);

    // Grow out of the promotion square: scale around its center.
    final origin = geometry.squareCenter(request.to);
    final alignment = Alignment(
      (origin.dx - column.left) / column.width * 2 - 1,
      (origin.dy - column.top) / column.height * 2 - 1,
    );
    final curve = CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic);

    return Focus(
      focusNode: _keys,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // The scrim: dims the board and cancels when tapped.
          Positioned.fill(
            child: FadeTransition(
              opacity: curve,
              child: Semantics(
                button: true,
                label: 'Cancel promotion',
                onTap: request.cancel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: request.cancel,
                  child: ColoredBox(color: theme.promotionScrimColor),
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: card,
            child: FadeTransition(
              opacity: curve,
              child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(curve),
                alignment: alignment,
                child: Stack(
                  children: [
                    // A soft card behind the column, so the choices read as
                    // one group.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.promotionBackgroundColor,
                            borderRadius: BorderRadius.circular(size * 0.12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x40000000),
                                blurRadius: size * 0.25,
                                offset: Offset(0, size * 0.06),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (final (i, type) in kPromotionChoices.indexed)
                      Positioned.fromRect(
                        rect: geometry
                            .squareRect(squares[i])
                            .shift(-card.topLeft),
                        child: _Choice(
                          key: ValueKey('promotion-${type.name}'),
                          piece: Piece(request.color, type),
                          size: size,
                          pieceSet: widget.pieceSet,
                          hoverColor: theme.hoverColor,
                          focusColor: theme.focusColor,
                          keyboardFocused: _keyChoice == i,
                          onTap: () => request.choose(type),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatefulWidget {
  const _Choice({
    super.key,
    required this.piece,
    required this.size,
    required this.pieceSet,
    required this.hoverColor,
    required this.focusColor,
    required this.keyboardFocused,
    required this.onTap,
  });

  final Piece piece;
  final double size;
  final PieceSet pieceSet;
  final Color hoverColor;
  final Color focusColor;
  final bool keyboardFocused;
  final VoidCallback onTap;

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final lifted = _hover || widget.keyboardFocused;
    final inset = widget.size * (lifted ? 0.02 : 0.08);
    // The tap action lives on the Semantics node itself: excludeSemantics
    // drops the GestureDetector's own action, so screen readers would find
    // the choice but couldn't activate it.
    return Semantics(
      button: true,
      label: 'Promote to ${widget.piece.type.name}',
      focused: widget.keyboardFocused ? true : null,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: lifted ? widget.hoverColor : null,
              shape: BoxShape.circle,
              border: widget.keyboardFocused
                  ? Border.all(
                      color: widget.focusColor,
                      width: (widget.size * 0.05).clamp(2.0, 4.0),
                    )
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.all(inset),
              child: ChessPieceView(
                piece: widget.piece,
                size: widget.size - 2 * inset,
                pieceSet: widget.pieceSet,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
