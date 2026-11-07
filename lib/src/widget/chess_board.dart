import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller/board_change.dart';
import '../controller/chess_board_controller.dart';
import '../model/board_move.dart';
import '../model/game_status.dart';
import '../model/piece.dart';
import '../model/square.dart';
import '../pieces/piece_set.dart';
import '../theme/chess_board_theme.dart';
import 'animation/move_animator.dart';
import 'animation/move_plan.dart';
import 'board_geometry.dart';
import 'interaction/board_gesture_layer.dart';
import 'interaction/board_interaction.dart';
import 'interaction/drag_layer.dart';
import 'layers/drag_feedback_layer.dart';
import 'layers/highlight_layer.dart';
import 'layers/highlight_model.dart';
import 'layers/labels_layer.dart';
import 'layers/pieces_layer.dart';
import 'layers/squares_layer.dart';
import 'promotion/promotion_picker.dart';

/// An interactive chess board.
///
/// The simplest board needs only a controller:
///
/// ```dart
/// final controller = ChessBoardController();
///
/// ChessBoard(controller: controller)
/// ```
///
/// The board is always square, sized to the smaller of the available width
/// and height, and updates itself whenever the controller changes.
class ChessBoard extends StatefulWidget {
  /// Creates a chess board.
  const ChessBoard({
    super.key,
    required this.controller,
    this.orientation = BoardOrientation.white,
    this.initialFen,
    this.theme = ChessBoardTheme.defaultTheme,
    this.lightSquareColor,
    this.darkSquareColor,
    this.checkmateColor,
    this.pieceSet = PieceSet.standard,
    this.coordinates = CoordinateMode.inside,
    this.readOnly = false,
    this.interactiveSide = InteractiveSide.both,
    this.autoQueen = false,
    this.promotionPickerBuilder,
    this.onMove,
    this.onGameEnd,
    this.showLastMove = true,
    this.animationDuration = const Duration(milliseconds: 150),
  });

  /// The game shown on the board.
  final ChessBoardController controller;

  /// Which color is at the bottom.
  final BoardOrientation orientation;

  /// A position to load into [controller] when the board first appears.
  ///
  /// Applied only to a controller that hasn't been used yet: when the board
  /// first appears, and when the app swaps in a fresh controller, for
  /// example to start a new game. A controller with moves played or a
  /// position loaded is never reset. Changing [initialFen] alone has no
  /// effect; use the controller to change the position. Throws an
  /// [ArgumentError] if the FEN is not a valid position.
  ///
  /// `ChessBoardController(fen: ...)` is usually simpler.
  final String? initialFen;

  /// Every color the board paints. Defaults to the green preset.
  final ChessBoardTheme theme;

  /// Overrides [ChessBoardTheme.lightSquareColor].
  final Color? lightSquareColor;

  /// Overrides [ChessBoardTheme.darkSquareColor].
  final Color? darkSquareColor;

  /// Overrides [ChessBoardTheme.checkmateColor].
  final Color? checkmateColor;

  /// The piece artwork.
  final PieceSet pieceSet;

  /// Where coordinate labels go.
  final CoordinateMode coordinates;

  /// When true, the user can't move pieces in any way. Moves made through
  /// the controller still show.
  final bool readOnly;

  /// Which colors the user may move, for example only black when the app
  /// plays white. Defaults to both.
  final InteractiveSide interactiveSide;

  /// When true, pawns reaching the last rank become queens without asking.
  final bool autoQueen;

  /// Replaces the built-in promotion picker. The widget it returns is laid
  /// over the whole board; call [PromotionRequest.choose] or
  /// [PromotionRequest.cancel] to finish.
  final PromotionPickerBuilder? promotionPickerBuilder;

  /// Called after each move the user makes on the board, by tap, drag or
  /// promotion choice. The move carries from, to, promotion and SAN, and is
  /// already applied: `controller.fen` is the resulting position. Read it
  /// before replying with a move of your own. Moves made through the
  /// controller are not reported.
  final ValueChanged<BoardMove>? onMove;

  /// Called once when a move ends the game, whether the user or the app
  /// made it, with the status, result and draw reason.
  ///
  /// Not called for loading a finished game, navigating history, or
  /// changes made with `notify: false`. Several silent changes followed by
  /// one `notifyListeners()` count as a single change.
  final ValueChanged<GameEnd>? onGameEnd;

  /// Whether the from and to squares of the last move are highlighted.
  final bool showLastMove;

  /// How long a move takes to animate when made by tap or through the
  /// controller. Dragged moves never animate, since the user already moved
  /// the piece. [Duration.zero] turns animation off, and so does the
  /// platform's reduced-motion setting.
  final Duration animationDuration;

  /// The theme with the shortcut color parameters applied.
  ChessBoardTheme get effectiveTheme =>
      lightSquareColor == null &&
          darkSquareColor == null &&
          checkmateColor == null
      ? theme
      : theme.copyWith(
          lightSquareColor: lightSquareColor,
          darkSquareColor: darkSquareColor,
          checkmateColor: checkmateColor,
        );

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

/// Test-only view of the board's state.
@visibleForTesting
abstract interface class BoardStateDebug {
  /// The selected square, or null.
  Square? get debugSelection;
}

/// How many times any board's main build ran. Tests use it to check that an
/// input which changes nothing doesn't rebuild the board.
@visibleForTesting
int debugBoardBuildCount = 0;

class _ChessBoardState extends State<ChessBoard>
    with TickerProviderStateMixin
    implements BoardStateDebug {
  /// Runs move animations.
  late final MoveAnimator _animation = MoveAnimator(vsync: this);

  /// Drives a board flip; at 1 when not flipping.
  late final AnimationController _flip = AnimationController(
    vsync: this,
    value: 1,
  );

  late final CurvedAnimation _flipCurve = CurvedAnimation(
    parent: _flip,
    curve: Curves.easeInOutCubic,
  );

  /// Which way the running flip turns. Flips from rest turn clockwise; a
  /// flip reversed part way turns the other way, so pieces retrace their
  /// arc.
  bool _flipClockwise = true;

  /// The geometry of the last build, used to re-aim a drag after a flip.
  BoardGeometry? _lastGeometry;

  /// Overlay opacity during a flip: fades out over the first half and
  /// back in over the second, fully visible when not flipping.
  late final Animation<double> _overlayOpacity = _flip.drive(
    TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
    ]),
  );

  /// The pieces as last drawn, so the next move's animation knows what
  /// was on the board before it.
  Map<Square, Piece> _shownPieces = const {};

  /// Set while a drop is being applied, so the move it makes doesn't
  /// animate.
  bool _dropping = false;

  /// The set currently drawn. Stays on the previous set while a new one
  /// loads, and is null only before the first set is ready.
  PieceSet? _shownSet;

  /// The set being loaded, to ignore results that arrive after a newer
  /// request.
  PieceSet? _loadingSet;

  late final BoardInteraction _interaction;

  /// The controller change last handled, so rebuilds alone don't clear
  /// the selection.
  int _seenChangeId = -1;

  /// Tells the pieces layer the position changed.
  final _ChangeSignal _positionChanges = _ChangeSignal();

  /// The piece being dragged, or null. Updated on every pointer move; only
  /// the drag layer and the gesture layer listen.
  final ValueNotifier<DragInfo?> _drag = ValueNotifier(null);

  /// The square the dragged piece came from, hidden while dragging. Only
  /// changes when a drag starts or ends, so the pieces layer doesn't
  /// rebuild on every pointer move.
  final ValueNotifier<Square?> _draggedFrom = ValueNotifier(null);

  /// A pawn move waiting for the promotion choice, or null. While set, the
  /// pawn is hidden from its square and the picker covers the board.
  final ValueNotifier<_PendingPromotion?> _promotion = ValueNotifier(null);

  /// The square left empty on the board, kept apart from [_draggedFrom] so a
  /// waiting promotion doesn't show the grabbing cursor.
  final ValueNotifier<Set<Square>> _hiddenSquares = ValueNotifier(const {});

  /// The square under a hovering mouse, for the hover tint.
  final ValueNotifier<Square?> _hover = ValueNotifier(null);

  /// The square under a dragged piece and whether it is a legal drop.
  /// Changes only when the pointer crosses into another square.
  final ValueNotifier<DropTarget?> _dropTarget = ValueNotifier(null);

  /// Fades [child] out and back in while the board flips, so labels,
  /// highlights and arrows (which switch to the new orientation at once)
  /// never sit on squares the turning pieces haven't reached.
  Widget _whileNotFlipping(Widget child) =>
      FadeTransition(opacity: _overlayOpacity, child: child);

  /// A highlight painter that repaints only when the position, selection or
  /// hover changes, and only if what it would paint actually differs.
  Widget _highlightLayer(
    ChessBoardTheme theme,
    CustomPainter Function(BoardHighlights) painter,
  ) => IgnorePointer(
    child: RepaintBoundary(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _positionChanges,
          _interaction.selection,
          _hover,
        ]),
        builder: (context, _) => CustomPaint(
          painter: painter(
            BoardHighlights.compute(
              controller: widget.controller,
              selected: _interaction.selection.value,
              hover: _hover.value,
              showLastMove: widget.showLastMove,
              theme: theme,
            ),
          ),
        ),
      ),
    ),
  );

  /// The square a press started on and the pointer kind, while the press
  /// could still become a drag of that square's piece.
  (Square, PointerDeviceKind)? _pressOrigin;

  @override
  void initState() {
    super.initState();
    _applyInitialFen();
    _interaction = BoardInteraction(
      controller: widget.controller,
      onMove: _requestMove,
      readOnly: widget.readOnly,
      interactiveSide: widget.interactiveSide,
    );
    _seenChangeId = widget.controller.changeId;
    widget.controller.addListener(_onControllerChanged);
    _draggedFrom.addListener(_syncHiddenSquare);
    _promotion.addListener(_syncHiddenSquare);
    _animation.addListener(_syncHiddenSquare);
    _shownPieces = widget.controller.pieces;
  }

  /// Loads [ChessBoard.initialFen] into a controller that hasn't been used
  /// yet. A controller with moves played or a position loaded is left
  /// alone, so remounting the board (tabs, lists, route changes) or giving
  /// the same controller to a second board never wipes a game in progress.
  void _applyInitialFen() {
    final fen = widget.initialFen;
    if (fen == null) return;
    final c = widget.controller;
    final untouched = c.changeId == 0 && c.startingFen == kInitialFen;
    if (!untouched) {
      // Still validate, so a bad value fails the same way every time.
      if (!ChessBoardController.isValidFen(fen)) _throwBadFen(fen);
      return;
    }
    if (!c.loadFen(fen, notify: false)) _throwBadFen(fen);
  }

  Never _throwBadFen(String fen) => throw ArgumentError.value(
    fen,
    'initialFen',
    'Not a valid chess position',
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shownSet == null && _loadingSet == null) _load(widget.pieceSet);
  }

  @override
  void didUpdateWidget(ChessBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.orientation != oldWidget.orientation) {
      // Twice a move, capped so a slow custom move duration doesn't make
      // the flip drag.
      final requested = widget.animationDuration * 2;
      const cap = Duration(milliseconds: 500);
      final duration = effectiveAnimationDuration(
        context,
        requested > cap ? cap : requested,
      );
      // A move in flight lands first, so only the flip moves pieces. A drag
      // in progress carries on: the floating piece stays under the finger
      // and drops on whatever square is there in the new orientation.
      _animation.finish();
      _retargetAfterFlip();
      if (duration == Duration.zero) {
        _flip.value = 1;
      } else {
        // Flipping again mid-flip turns back from where the pieces are:
        // the curve is point-symmetric, so 1 - t with the turn reversed
        // continues along the same arc without a jump.
        final reversing = _flip.isAnimating;
        _flipClockwise = reversing ? !_flipClockwise : true;
        final from = reversing ? 1 - _flip.value : 0.0;
        _flip
          ..duration = duration
          ..forward(from: from);
      }
    }
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      // A fresh controller for a new game gets the initial position too;
      // a controller already in use is left as it is.
      _applyInitialFen();
      _interaction.controller = widget.controller;
      _seenChangeId = widget.controller.changeId;
      widget.controller.addListener(_onControllerChanged);
      _resetEphemeralState();
    }
    _interaction
      ..readOnly = widget.readOnly
      ..interactiveSide = widget.interactiveSide
      ..revalidate();
    if (_drag.value case final d? when !_canDragFrom(d.from)) _cancelDrag();
    _revalidatePromotion();
    if (widget.pieceSet != oldWidget.pieceSet &&
        widget.pieceSet != _loadingSet) {
      _load(widget.pieceSet);
    }
  }

  /// After a flip the squares move under a resting pointer, so the drop
  /// target and hover square are recomputed for the new layout once it has
  /// been built.
  void _retargetAfterFlip() {
    _hover.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final drag = _drag.value;
      final geometry = _lastGeometry;
      if (drag == null || geometry == null) return;
      _updateDropTarget(drag.from, drag.position, geometry);
    });
  }

  /// Clears everything the board holds about the current interaction:
  /// selection, drag, pending promotion, premove, hint, user drawings and
  /// running animations. Called when the controller is swapped. Later
  /// features add their state here rather than resetting it elsewhere.
  void _resetEphemeralState() {
    _animation.finish();
    _flip.value = 1;
    _dropping = false;
    _shownPieces = widget.controller.pieces;
    _cancelPromotion();
    _interaction.clear();
    _cancelDrag();
  }

  /// Reports the change just seen to [ChessBoard.onMove] and
  /// [ChessBoard.onGameEnd]. Only a played move that wasn't silent counts:
  /// loading, undo, reset and navigation never report.
  ///
  /// The game-end check is taken before [ChessBoard.onMove] runs. If the
  /// app replies to the move from inside onMove, that reply is a change of
  /// its own and is reported by its own notification; this pass then stops,
  /// so a reply that ends the game is reported once, not twice.
  void _reportChange() {
    final c = widget.controller;
    final change = c.lastChange;
    if (change is! MoveApplied || change.silent) return;
    final id = c.changeId;
    final end = c.isGameOver ? GameEnd._of(c) : null;
    if (change.source == MoveSource.user) widget.onMove?.call(change.move);
    if (!mounted || widget.controller.changeId != id) return;
    if (end != null) widget.onGameEnd?.call(end);
  }

  /// Starts the animation for the change just seen, if it is a move that
  /// should animate: any non-silent move except one the user dragged. A
  /// running animation is finished first, so the board never shows a stale
  /// position. Other changes (loading, undo, reset, navigation) snap.
  void _planAnimation(int previousId) {
    final c = widget.controller;
    final before = _shownPieces;
    _shownPieces = c.pieces;
    final change = c.lastChange;
    final dragged = _dropping;
    _dropping = false;
    // Several changes coalesced into one notification (for example a
    // silent move followed by a notified one) can't be shown as a single
    // slide from the position last drawn, so they snap.
    final single = c.changeId == previousId + 1;
    final plan = !single || change.silent || dragged
        ? null
        : switch (change) {
            MoveApplied(:final move) => MovePlan.forMove(move, before: before),
            // One step through history animates like a move, forward or
            // back; longer jumps snap.
            NavigatedTo(:final fromPly, :final toPly)
                when toPly == fromPly + 1 =>
              MovePlan.forMove(c.fullLine[fromPly], before: before),
            NavigatedTo(:final fromPly, :final toPly)
                when toPly == fromPly - 1 =>
              MovePlan.forUndo(c.fullLine[toPly], after: before),
            _ => null,
          };
    if (plan == null) {
      _animation.finish();
      return;
    }
    final duration = effectiveAnimationDuration(
      context,
      widget.animationDuration,
    );
    _animation.play(plan, duration);
  }

  /// The board's only controller listener. A changed position clears any
  /// selection (it refers to the old position) and redraws the pieces.
  /// Notifications that change no position, such as toggling
  /// `allowBranching`, only recheck whether the selection is still valid.
  void _onControllerChanged() {
    final id = _interaction.controller.changeId;
    if (id != _seenChangeId) {
      final previousId = _seenChangeId;
      _seenChangeId = id;
      _interaction.clear();
      // A drag from the old position can't land in the new one.
      _cancelDrag();
      _cancelPromotion();
      _planAnimation(previousId);
      _positionChanges.notify();
      _reportChange();
    } else {
      _interaction.revalidate();
      if (_drag.value case final d? when !_canDragFrom(d.from)) _cancelDrag();
      _revalidatePromotion();
    }
  }

  /// Carries out a user move. A pawn reaching the last rank waits for the
  /// promotion choice, unless [ChessBoard.autoQueen] is set. Returns true
  /// when the move was made or is waiting for a choice.
  bool _requestMove(Square from, Square to) {
    final promotes = widget.controller
        .legalMovesFrom(from)
        .any((m) => m.to == to && m.isPromotion);
    if (!promotes || widget.autoQueen) {
      return applyUserMove(
        widget.controller,
        from,
        to,
        promotion: PieceType.queen,
      );
    }
    final color = widget.controller.pieceAt(from)!.color;
    _promotion.value = (from: from, to: to, color: color);
    return true;
  }

  void _choosePromotion(PieceType type) {
    final pending = _promotion.value;
    if (pending == null) return;
    _promotion.value = null;
    // The pawn already waited on its way; sliding it again from its
    // origin would look like a hiccup. Land it in place.
    _dropping = true;
    applyUserMove(widget.controller, pending.from, pending.to, promotion: type);
    _dropping = false;
  }

  void _cancelPromotion() {
    if (_promotion.value == null) return;
    _promotion.value = null;
    _dropping = false;
  }

  /// The square whose piece the pieces layer leaves out: the dragged piece's
  /// origin, or the pawn waiting for its promotion choice.
  void _syncHiddenSquare() {
    final hidden = <Square>{
      ?_draggedFrom.value,
      ?_promotion.value?.from,
      ..._animation.hiddenSquares,
    };
    if (!setEquals(hidden, _hiddenSquares.value)) _hiddenSquares.value = hidden;
  }

  /// Closes the picker if its pawn can no longer move, for example after the
  /// board became read-only.
  void _revalidatePromotion() {
    final pending = _promotion.value;
    if (pending != null && !_canDragFrom(pending.from)) _cancelPromotion();
  }

  PromotionRequest _requestFor(_PendingPromotion p, BoardGeometry g) =>
      PromotionRequest(
        from: p.from,
        to: p.to,
        color: p.color,
        squareRect: g.squareRect(p.to),
        choose: _choosePromotion,
        cancel: _cancelPromotion,
      );

  bool _canDragFrom(Square square) {
    final piece = widget.controller.pieceAt(square);
    return piece != null && _interaction.canMove(piece.color);
  }

  void _onPressDown(Square square, PointerDeviceKind kind) {
    // A piece still sliding lands at once, so it can be pressed or
    // dragged without showing twice.
    _animation.finish();
    final outcome = _interaction.pressDown(square);
    // Only a press that leaves its piece selected can turn into a drag. A
    // press that made a move, or landed on nothing movable, can't.
    final dragsPiece =
        outcome == TapOutcome.selected || outcome == TapOutcome.pressedSelected;
    _pressOrigin = dragsPiece ? (square, kind) : null;
  }

  void _onDragStart(Offset position, BoardGeometry geometry) {
    final origin = _pressOrigin;
    if (origin == null) return;
    final (from, kind) = origin;
    final piece = widget.controller.pieceAt(from);
    if (piece == null || !_canDragFrom(from)) return;
    _drag.value = DragInfo(
      from: from,
      piece: piece,
      position: position,
      kind: kind,
    );
    _draggedFrom.value = from;
    _updateDropTarget(from, position, geometry);
  }

  void _onDragUpdate(Offset position, BoardGeometry geometry) {
    final drag = _drag.value;
    if (drag == null) return;
    _drag.value = drag.moveTo(position);
    _updateDropTarget(drag.from, position, geometry);
  }

  /// Shows whether the square under the pointer is a legal drop. Uses the
  /// same rules as a drop, so dragging the king over its own rook shows
  /// castling as legal. The source square and off-board points show
  /// nothing.
  void _updateDropTarget(Square from, Offset position, BoardGeometry g) {
    final square = g.squareAt(position);
    _dropTarget.value = square == null || square == from
        ? null
        : DropTarget(
            square,
            legal: _interaction.resolveTarget(from, square) != null,
          );
  }

  void _onPressUp(
    Offset position,
    BoardGeometry geometry, {
    required bool dragged,
  }) {
    _pressOrigin = null;
    final drag = _drag.value;
    if (drag == null) {
      _interaction.pressUp(dragged: dragged);
      return;
    }
    _endDrag();
    // The drop target is the square under the finger or pointer, as on
    // every chess app. On touch the piece is drawn half a square above the
    // finger, so its lower edge still overlaps the target square, and
    // targeting the piece instead would make the back rank unreachable.
    final target = geometry.squareAt(position);
    _interaction.pressUp(dragged: true);
    if (target == null || target == drag.from) return; // Snap back.
    // The user already moved the piece: the resulting move doesn't
    // animate. A drop onto a promotion square waits for the choice, which
    // then lands without animating too.
    _dropping = true;
    _interaction.drop(drag.from, target);
    if (_promotion.value == null) _dropping = false;
  }

  void _onPressCancel() {
    _pressOrigin = null;
    _interaction.pressCancel();
    _cancelDrag();
  }

  void _endDrag() {
    _drag.value = null;
    _draggedFrom.value = null;
    _dropTarget.value = null;
  }

  void _cancelDrag() {
    _pressOrigin = null;
    if (_drag.value != null) _endDrag();
  }

  @override
  Square? get debugSelection => _interaction.selection.value;

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _interaction.dispose();
    _positionChanges.dispose();
    _drag.dispose();
    _draggedFrom.dispose();
    _promotion.dispose();
    _hiddenSquares.dispose();
    _animation.dispose();
    _hover.dispose();
    _flipCurve.dispose();
    _flip.dispose();
    _dropTarget.dispose();
    super.dispose();
  }

  void _load(PieceSet set) {
    _loadingSet = set;
    final future = set.precache(context);
    void show() {
      if (!mounted || _loadingSet != set) return;
      _loadingSet = null;
      if (_shownSet != set) setState(() => _shownSet = set);
    }

    if (future is SynchronousFuture) {
      // Already loaded: show it in this frame, without a rebuild.
      _loadingSet = null;
      _shownSet = set;
      return;
    }
    future.then(
      (_) => show(),
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'modern_chess_board',
            context: ErrorDescription('while loading the piece set $set'),
          ),
        );
        // Show the set anyway; pieces load on demand.
        show();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      debugBoardBuildCount++;
      return true;
    }());
    final theme = widget.effectiveTheme;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final ambientStyle = DefaultTextStyle.of(context).style;
    // Without a Material ancestor, the ambient style is Flutter's red
    // "missing Material" debug style; never let that tint the labels.
    final ambient = _isFallbackStyle(ambientStyle) ? null : ambientStyle.color;
    return BoardLayout(
      coordinates: widget.coordinates,
      builder: (context, metrics) {
        final geometry = metrics.geometry(widget.orientation);
        _lastGeometry = geometry;
        final labels = layoutBoardLabels(
          metrics: metrics,
          orientation: widget.orientation,
          theme: theme,
          ambientTextColor: ambient,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: BoardSquaresPainter(
                    geometry: geometry,
                    lightColor: theme.lightSquareColor,
                    darkColor: theme.darkSquareColor,
                    devicePixelRatio: dpr,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: _whileNotFlipping(
                _highlightLayer(
                  theme,
                  (h) => BoardTintsPainter(geometry: geometry, highlights: h),
                ),
              ),
            ),
            Positioned.fill(
              // Under the pieces, like the other square tints, so a piece on
              // the target square (a capture) is framed, not washed out.
              child: DragFeedbackLayer(
                target: _dropTarget,
                geometry: geometry,
                theme: theme,
              ),
            ),
            if (labels.isNotEmpty)
              Positioned.fill(
                child: _whileNotFlipping(
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: BoardLabelsPainter(
                        labels: labels,
                        // Inherit the app's font family; size, weight and
                        // line height are the board's. Colors come per label.
                        style:
                            (_isFallbackStyle(ambientStyle)
                                    ? const TextStyle()
                                    : ambientStyle)
                                .merge(
                                  TextStyle(
                                    fontSize: metrics.labelFontSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1,
                                    letterSpacing: 0,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                        marginColor: theme.marginColor,
                        metrics: metrics,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: PiecesLayer(
                controller: widget.controller,
                positionChanges: _positionChanges,
                hiddenSquares: _hiddenSquares,
                geometry: geometry,
                pieceSet: _shownSet,
                flip: _flipCurve,
                flipClockwise: _flipClockwise,
              ),
            ),
            Positioned.fill(
              child: MoveAnimationLayer(
                animator: _animation,
                geometry: geometry,
                pieceSet: _shownSet,
                flip: _flipCurve,
                flipClockwise: _flipClockwise,
              ),
            ),
            Positioned.fill(
              child: _whileNotFlipping(
                _highlightLayer(
                  theme,
                  (h) => BoardMarkersPainter(geometry: geometry, highlights: h),
                ),
              ),
            ),
            Positioned.fill(
              // Keeps per-move repaints of the floating piece from reaching
              // the app content around the board.
              child: RepaintBoundary(
                child: DragLayer(
                  drag: _drag,
                  geometry: geometry,
                  pieceSet: _shownSet,
                ),
              ),
            ),
            Positioned.fill(
              // Rebuilds only when a drag starts or ends, not on every move.
              // Input waits out the short flip, so a tap never lands on a
              // square whose piece is still turning.
              child: _IgnoreWhileFlipping(
                flip: _flip,
                child: ValueListenableBuilder<Square?>(
                  valueListenable: _draggedFrom,
                  builder: (context, draggedFrom, _) => BoardGestureLayer(
                    geometry: geometry,
                    canDragFrom: _canDragFrom,
                    dragging: draggedFrom != null,
                    refresh: _positionChanges,
                    onPressDown: _onPressDown,
                    onDragStart: (p) => _onDragStart(p, geometry),
                    onDragUpdate: (p) => _onDragUpdate(p, geometry),
                    onPressUp: (p, {required dragged}) =>
                        _onPressUp(p, geometry, dragged: dragged),
                    onPressCancel: _onPressCancel,
                    onHoverSquare: (s) => _hover.value = s,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              // The picker sits on a square too, so it fades and waits out a
              // flip like the other overlays.
              child: _IgnoreWhileFlipping(
                flip: _flip,
                child: _whileNotFlipping(
                  ValueListenableBuilder<_PendingPromotion?>(
                    valueListenable: _promotion,
                    builder: (context, pending, _) {
                      if (pending == null) return const SizedBox.shrink();
                      final request = _requestFor(pending, geometry);
                      final custom = widget.promotionPickerBuilder;
                      final Widget picker = custom == null
                          ? PromotionPicker(
                              request: request,
                              geometry: geometry,
                              pieceSet: _shownSet ?? widget.pieceSet,
                              theme: theme,
                            )
                          : Stack(
                              children: [
                                // Taps outside a custom picker cancel too.
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: request.cancel,
                                  ),
                                ),
                                Positioned.fill(
                                  child: custom(context, request),
                                ),
                              ],
                            );
                      return _PromotionScope(
                        onCancel: request.cancel,
                        child: picker,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Whether [style] is the red debug style Flutter uses for text with no
/// Material ancestor. That style marks a missing ancestor; it is never a
/// color the app chose for its text.
bool _isFallbackStyle(TextStyle style) =>
    style.color == const Color(0xD0FF0000) &&
    style.decoration == TextDecoration.underline;

/// How a game ended, reported by [ChessBoard.onGameEnd].
@immutable
class GameEnd {
  /// Creates a game end.
  const GameEnd({required this.status, required this.result, this.drawReason});

  GameEnd._of(ChessBoardController c)
    : status = c.status,
      result = c.result,
      drawReason = c.drawReason;

  /// Checkmate, stalemate or draw.
  final GameStatus status;

  /// Who won, or a draw.
  final GameResult result;

  /// Why the game was drawn, or null when it was won.
  final DrawReason? drawReason;

  @override
  bool operator ==(Object other) =>
      other is GameEnd &&
      other.status == status &&
      other.result == result &&
      other.drawReason == drawReason;

  @override
  int get hashCode => Object.hash(status, result, drawReason);

  @override
  String toString() =>
      'GameEnd(${status.name}, ${result.pgn}'
      '${drawReason == null ? '' : ', ${drawReason!.name}'})';
}

/// A pawn move waiting for the user to choose a piece.
typedef _PendingPromotion = ({Square from, Square to, PieceColor color});

/// Lets Escape and the system Back action cancel an open promotion picker,
/// instead of leaving the page. Takes keyboard focus while open so Escape
/// works right after the press that opened it, and cancels when focus moves
/// elsewhere (for example to a text field next to the board), so the picker
/// never lingers where Escape can't reach it.
class _PromotionScope extends StatefulWidget {
  const _PromotionScope({required this.onCancel, required this.child});

  final VoidCallback onCancel;
  final Widget child;

  @override
  State<_PromotionScope> createState() => _PromotionScopeState();
}

class _PromotionScopeState extends State<_PromotionScope> {
  final FocusNode _focus = FocusNode(debugLabel: 'promotion picker');

  /// Set once the picker has received focus, so losing focus before then
  /// (while the request is still pending) doesn't cancel.
  bool _hadFocus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) widget.onCancel();
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Focus(
        focusNode: _focus,
        onFocusChange: (focused) {
          if (focused) {
            _hadFocus = true;
          } else if (_hadFocus) {
            widget.onCancel();
          }
        },
        child: widget.child,
      ),
    ),
  );
}

/// A listenable that notifies on demand.
class _ChangeSignal extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Ignores pointer input while [flip] runs.
class _IgnoreWhileFlipping extends AnimatedWidget {
  const _IgnoreWhileFlipping({
    required Animation<double> flip,
    required this.child,
  }) : super(listenable: flip);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final flip = listenable as Animation<double>;
    return IgnorePointer(ignoring: flip.status.isAnimating, child: child);
  }
}
