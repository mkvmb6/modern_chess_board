import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controller/board_change.dart';
import '../controller/chess_board_controller.dart';
import '../controller/move_classifier.dart';
import '../controller/notation.dart';
import '../haptics/haptics.dart';
import '../model/annotations.dart';
import '../model/board_move.dart';
import '../model/game_status.dart';
import '../model/piece.dart';
import '../model/square.dart';
import '../pieces/piece_set.dart';
import '../sound/chess_sound_pack.dart';
import '../sound/safe_sound_dispatcher.dart';
import '../theme/chess_board_theme.dart';
import 'animation/move_animator.dart';
import 'animation/move_plan.dart';
import 'board_geometry.dart';
import 'interaction/annotation_drawing.dart';
import 'interaction/board_gesture_layer.dart';
import 'interaction/board_interaction.dart';
import 'interaction/board_keyboard.dart';
import 'interaction/drag_layer.dart';
import 'interaction/premove.dart';
import 'layers/arrows_layer.dart';
import 'layers/drag_feedback_layer.dart';
import 'layers/highlight_layer.dart';
import 'layers/highlight_model.dart';
import 'layers/labels_layer.dart';
import 'layers/pieces_layer.dart';
import 'layers/semantics_layer.dart';
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
    this.enablePremoves = false,
    this.enableKeyboard = true,
    this.soundPack = const SilentSoundPack(),
    this.enableHaptics = false,
    this.moveAnnouncer = defaultMoveAnnouncer,
    this.semanticsLabel = 'Chess board',
    this.autoQueen = false,
    this.promotionPickerBuilder,
    this.onMove,
    this.onGameEnd,
    this.showLastMove = true,
    this.animationDuration = const Duration(milliseconds: 150),
    this.arrows = const [],
    this.marks = const [],
    this.hint,
    this.hintTimeout,
    this.enableUserAnnotations = true,
    this.clearUserAnnotationsOnMove = true,
    this.onUserArrowsChanged,
    this.onUserMarksChanged,
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

  /// Whether the user can queue a move on the opponent's turn, as on chess
  /// sites. Needs [interactiveSide] to be a single color.
  ///
  /// A premove is made by tap or drag like a move, shown in
  /// [ChessBoardTheme.premoveColor], and played as soon as the opponent's
  /// move arrives through the controller, if it is legal then; otherwise it
  /// is dropped without a sound. Pressing anywhere that isn't a premove
  /// destination cancels it. [onMove] reports a premove when it is played,
  /// not when it is queued. A premoved promotion always becomes a queen,
  /// whatever [autoQueen] says, since there is no time to ask. Premoves may
  /// target squares the user's own pieces hold, so a recapture can be
  /// queued. Off by default.
  final bool enablePremoves;

  /// Whether the board can be played with a keyboard. When the board has
  /// focus (Tab, or a click), the arrow keys move a cursor across the
  /// squares, following the orientation; Enter or Space acts like a tap on
  /// the cursor's square, and Escape clears the selection. Typing a move in
  /// algebraic notation, such as `Nf3` or `O-O`, then Enter plays it.
  ///
  /// Lowercase piece letters (`nf3`) and coordinates (`e2e4`) work too.
  /// While the promotion picker is open, up and down pick a piece and
  /// Enter chooses it, or Q, R, B or N choose directly.
  ///
  /// Shift+H switches to history navigation, where left and right step
  /// through history and Home and End jump to its ends. A [readOnly] board
  /// is always in navigation mode. Keys with Ctrl, Cmd or Alt, and an
  /// Escape with nothing to close, are left to the app.
  ///
  /// The cursor stays hidden until a key is pressed, so touch and mouse
  /// users never see it. On by default; any hardware keyboard works,
  /// including one attached to a phone or tablet.
  final bool enableKeyboard;

  /// Plays sounds for moves. The board sends one [SoundEvent] per move,
  /// whoever made it (the user, a premove, or the app through the
  /// controller), and [SoundEvent.illegal] when the user drops a piece on a
  /// square it can't go to or enters a typed move that can't be played.
  /// Tapping away to clear a selection, or dropping a piece back where it
  /// started or off the board, is a cancel, not an attempt, and is silent. Nothing is sent for undo, reset, loading, history
  /// navigation or changes made with `notify: false`. Errors from the pack
  /// are reported and never break the board. Silent by default.
  final ChessSoundPack soundPack;

  /// Whether the board gives light haptic feedback on phones and tablets:
  /// a click when a piece is picked up to drag, and a tap when it is
  /// dropped on a square it can go to. Off by default.
  final bool enableHaptics;

  /// Words the move a screen reader announces after each move, for
  /// example "White knight to f3, check". Defaults to [defaultMoveAnnouncer], in
  /// English; pass your own to localize. Moves are announced however they
  /// were made; history navigation and silent changes aren't.
  final MoveAnnouncer moveAnnouncer;

  /// What screen readers call the board as a whole; each square has its
  /// own label inside it.
  final String semanticsLabel;

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

  /// Annotation arrows drawn over the board, in their own color or the
  /// theme's [ChessBoardTheme.arrowColor]. They never block touches. The
  /// board only reads this list; it never changes it. Arrows with bad
  /// square names are skipped.
  final List<Arrow> arrows;

  /// Circled or tinted squares, following the same rules as [arrows].
  final List<SquareMark> marks;

  /// A single suggestion arrow, such as an engine's best move. It is drawn
  /// dashed with an open head in [ChessBoardTheme.hintArrowColor], so it
  /// never looks like an annotation arrow.
  ///
  /// The hint disappears when the position changes (a move made on the
  /// board or through the controller, an undo, history navigation or a
  /// newly loaded position) and when [hintTimeout] passes. It is compared
  /// by value: passing an equal hint again doesn't bring it back; pass a
  /// different one, or null and then the hint, to show it again.
  final Arrow? hint;

  /// How long [hint] stays up when no move is made, or null to keep it
  /// until the next move. A new hint restarts the timer.
  final Duration? hintTimeout;

  /// Whether the user can draw arrows and circles: right-click (or
  /// long-press on touch) and drag draws an arrow, releasing on the
  /// starting square toggles a circle. Shift, Alt and Shift+Alt pick the
  /// other [ChessBoardTheme.annotationColors]. Drawing something already
  /// there in the same color removes it. Turning this off clears them.
  final bool enableUserAnnotations;

  /// Whether user drawings are cleared when the position changes: a move
  /// (on the board or through the controller), an undo, history
  /// navigation or a newly loaded position. Drawings are about the
  /// position they were drawn on, so this is on by default.
  final bool clearUserAnnotationsOnMove;

  /// Called with the user's arrows whenever they change.
  final ValueChanged<List<Arrow>>? onUserArrowsChanged;

  /// Called with the user's circles whenever they change.
  final ValueChanged<List<SquareMark>>? onUserMarksChanged;

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

  /// The hint arrow being shown, or null once dismissed.
  final ValueNotifier<Arrow?> _hint = ValueNotifier(null);

  /// The queued premove, or null.
  final ValueNotifier<Premove?> _premove = ValueNotifier(null);

  /// Sends sound events without letting the pack's errors escape.
  late final SafeSoundDispatcher _sound = SafeSoundDispatcher(widget.soundPack);

  BoardHaptics get _haptics => widget.enableHaptics
      ? const BoardHaptics(enabled: true)
      : const BoardHaptics(enabled: false);

  /// Tells screen readers about the move just seen.
  void _announceMove() {
    final c = widget.controller;
    final change = c.lastChange;
    if (change is! MoveApplied || change.silent) return;
    final text = widget.moveAnnouncer(change.move, c.drawReason);
    if (text.isEmpty) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      Directionality.of(context),
    );
  }

  /// What a screen reader is told about [square].
  SquareSemantics _describeSquare(Square square) {
    final selected = _interaction.selection.value;
    final target =
        selected != null && _interaction.resolveAny(selected, square) != null;
    final piece = selected == null ? null : widget.controller.pieceAt(selected);
    final queued = _premove.value;
    return SquareSemantics(
      label: squareLabel(widget.controller, square),
      selected: selected == square,
      hint: target
          ? (piece != null && _interaction.canMove(piece.color)
                ? 'legal move'
                : 'premove')
          : (queued != null && (queued.from == square || queued.to == square))
          ? 'premove queued'
          : null,
    );
  }

  /// A screen reader activated [square]: a whole tap, with the same rules
  /// as a pointer press.
  void _activateSquare(Square square) {
    if (_promotion.value != null) return;
    _onPressDown(square, PointerDeviceKind.unknown, fromKeyboard: true);
    _pressOrigin = null;
    _interaction.pressUp(dragged: false);
  }

  /// What the semantics grid rebuilds for.
  late final Listenable _semanticsChanges = Listenable.merge([
    _positionChanges,
    _interaction.selection,
    _premove,
  ]);

  /// Plays the sound for the change just seen, if it is a move that
  /// notified listeners. Called once per notification, so one move makes
  /// one sound.
  void _playMoveSound() {
    final c = widget.controller;
    final change = c.lastChange;
    if (change is! MoveApplied || change.silent) return;
    _sound.dispatch(classifyMove(change.move, c.status));
  }

  /// The user tried a move that isn't legal.
  void _playIllegal() => _sound.dispatch(SoundEvent.illegal);

  /// Keyboard focus for the board.
  final FocusNode _focusNode = FocusNode(debugLabel: 'chess board');

  /// Keyboard play; its actions go through the same rules as pointer input.
  late final BoardKeyboard _keyboard = BoardKeyboard(
    KeyboardActions(
      orientation: () => widget.orientation,
      tap: _keyTap,
      clearSelection: () {
        final had =
            _interaction.selection.value != null || _premove.value != null;
        _interaction.clear();
        _cancelPremove();
        return had;
      },
      busy: () => _promotion.value != null,
      submitSan: _submitTypedMove,
      navigationLocked: () => widget.readOnly,
      back: () => widget.controller.back(),
      forward: () => widget.controller.forward(),
      toStart: () => widget.controller.goToStart(),
      toEnd: () => widget.controller.goToEnd(),
    ),
  );

  /// Enter or Space on [square]: a whole tap, through the same rules as a
  /// pointer press.
  void _keyTap(Square square) => _activateSquare(square);

  /// Plays a typed move if one legal move matches it and the user may move
  /// that piece. Returns whether it was played.
  bool _submitTypedMove(String san) {
    final played = _playTypedMove(san);
    if (!played) _playIllegal();
    return played;
  }

  bool _playTypedMove(String san) {
    final c = widget.controller;
    if (_promotion.value != null) return false;
    final legal = [
      for (final m in c.legalMoves)
        if (m.san != null) m,
    ];
    final matches = matchTypedMove(san, [
      for (final m in legal)
        (
          san: m.san!,
          from: m.from.name,
          to: m.to.name,
          promotion: m.promotion?.letter,
        ),
    ]);
    if (matches.length != 1) return false;
    final m = legal[matches.single];
    final color = c.pieceAt(m.from)?.color;
    if (color == null || !_interaction.canMove(color)) return false;
    _interaction.clear();
    _cancelPremove();
    return applyUserMove(c, m.from, m.to, promotion: m.promotion);
  }

  /// Queues a premove. Promotion premoves become a queen when played.
  bool _queuePremove(Square from, Square to) {
    final piece = widget.controller.pieceAt(from);
    if (piece == null) return false;
    _premove.value = Premove(from: from, to: to, color: piece.color);
    return true;
  }

  void _cancelPremove() => _premove.value = null;

  /// Plays the queued premove after the opponent's move [id], once every
  /// listener has seen that move: the app's own listeners (an engine, a
  /// clock) get the opponent's move first, then the premove as its own
  /// change.
  void _schedulePremove(int id) {
    final p = _premove.value;
    if (p == null) return;
    scheduleMicrotask(() {
      if (!mounted || widget.controller.changeId != id || _premove.value != p) {
        return;
      }
      _playPremove();
    });
  }

  /// Set while a premove is played, so it lands without its own slide and
  /// leaves the opponent's move animating.
  bool _playingPremove = false;

  /// Plays the queued premove now that it is its side's turn. An illegal
  /// premove is dropped quietly.
  void _playPremove() {
    final p = _premove.value;
    if (p == null) return;
    final c = widget.controller;
    if (c.turn != p.color) return;
    _premove.value = null;
    if (!_interaction.canMove(p.color) || c.pieceAt(p.from)?.color != p.color) {
      return;
    }
    final target = _interaction.resolveTarget(p.from, p.to);
    if (target == null) return;
    _playingPremove = true;
    try {
      applyUserMove(c, p.from, target, promotion: PieceType.queen);
    } finally {
      _playingPremove = false;
    }
  }

  /// Keeps the user's selection, press and drag across the opponent's move
  /// when their piece still stands where it did and can still be moved, so
  /// a premove selection or drag carries on as an ordinary move. Anything
  /// else (undo, loading, the piece taken) drops them.
  void _carryInputOver(Map<Square, Piece> before, {required bool moved}) {
    final c = widget.controller;
    bool kept(Square s) =>
        moved &&
        before[s] != null &&
        before[s] == c.pieceAt(s) &&
        _canDragFrom(s);
    final selected = _interaction.selection.value;
    if (selected != null && kept(selected)) {
      _interaction.revalidate();
    } else {
      _interaction.clear();
    }
    final origin = _pressOrigin;
    final drag = _drag.value;
    if (drag != null && kept(drag.from)) {
      // The squares it can drop on changed with the position.
      if (_lastGeometry case final g?) {
        _updateDropTarget(drag.from, drag.position, g);
      }
      return;
    }
    // A drag from the old position can't land in the new one.
    _cancelDrag();
    if (drag == null && origin != null && kept(origin.$1)) {
      _pressOrigin = origin;
    }
  }

  /// Arrows and circles the user drew.
  final UserAnnotations _userDrawings = UserAnnotations();

  /// The arrow being drawn, or null when not drawing.
  final ValueNotifier<DrawingPreview?> _drawing = ValueNotifier(null);

  AnnotationColors get _annotationColors =>
      widget.effectiveTheme.annotationColors;

  void _onDrawStart(Square square) {
    if (!widget.enableUserAnnotations) return;
    // Drawing takes over from any selection, as on chess sites.
    _interaction.clear();
    _cancelDrag();
    _drawing.value = DrawingPreview(
      from: square,
      to: square,
      color: currentAnnotationColor(_annotationColors),
    );
  }

  void _onDrawUpdate(Offset position, BoardGeometry geometry) {
    final d = _drawing.value;
    if (d == null) return;
    // The color follows the modifier keys, so the preview always shows
    // the color the drawing will land in.
    final next = DrawingPreview(
      from: d.from,
      to: geometry.squareAt(position),
      color: currentAnnotationColor(_annotationColors),
    );
    if (next != d) _drawing.value = next;
  }

  void _onDrawEnd(Offset position, BoardGeometry geometry) {
    final d = _drawing.value;
    _drawing.value = null;
    if (d == null || !widget.enableUserAnnotations) return;
    final to = geometry.squareAt(position);
    if (to == null) return;
    // The color is read when the button lifts, so a modifier pressed
    // mid-drag still counts.
    final color = currentAnnotationColor(_annotationColors);
    if (to == d.from) {
      _userDrawings.toggleCircle(to, color);
      widget.onUserMarksChanged?.call(_userDrawings.marks);
    } else {
      _userDrawings.toggleArrow(d.from, to, color);
      widget.onUserArrowsChanged?.call(_userDrawings.arrows);
    }
  }

  void _onDrawCancel() => _drawing.value = null;

  /// Clears the user's drawings and reports the lists that changed. With
  /// [cancelDrawing], an arrow being drawn is dropped too; a position
  /// change keeps it, since its start square is still on the board.
  ///
  /// Reports made while the framework is building (from `didUpdateWidget`)
  /// wait until after the frame, so an app that calls `setState` in the
  /// callback doesn't trip "setState() called during build".
  void _clearUserDrawings({bool cancelDrawing = false}) {
    if (cancelDrawing) _drawing.value = null;
    final changed = _userDrawings.clear();
    if (!changed.arrows && !changed.marks) return;
    void report() {
      if (!mounted) return;
      if (changed.arrows) widget.onUserArrowsChanged?.call(const []);
      if (changed.marks) widget.onUserMarksChanged?.call(const []);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => report());
    } else {
      report();
    }
  }

  /// What the arrows layer repaints for.
  late final Listenable _arrowsChanges = Listenable.merge([
    _hint,
    _userDrawings,
    _drawing,
  ]);

  /// Clears [_hint] after [ChessBoard.hintTimeout].
  Timer? _hintTimer;

  /// Shows [hint] (or nothing) and restarts its timeout.
  void _showHint(Arrow? hint) {
    _hintTimer?.cancel();
    _hintTimer = null;
    _hint.value = hint;
    final timeout = widget.hintTimeout;
    if (hint != null && timeout != null) {
      _hintTimer = Timer(timeout, _dismissHint);
    }
  }

  /// Hides the hint until the app passes a different one.
  void _dismissHint() => _showHint(null);

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
          _premove,
          _keyboard.focus,
        ]),
        builder: (context, _) {
          final selected = _interaction.selection.value;
          final piece = selected == null
              ? null
              : widget.controller.pieceAt(selected);
          final premoving =
              piece != null && _interaction.canPremove(piece.color);
          final queued = _premove.value;
          return CustomPaint(
            painter: painter(
              BoardHighlights.compute(
                controller: widget.controller,
                selected: selected,
                hover: _hover.value,
                showLastMove: widget.showLastMove,
                theme: theme,
                focus: _keyboard.focus.value,
                premove: queued == null
                    ? null
                    : (from: queued.from, to: queued.to),
                premoveTargets: premoving
                    ? _interaction.targetsFrom(selected!)
                    : null,
              ),
            ),
          );
        },
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
      onPremove: _queuePremove,
      enablePremoves: widget.enablePremoves,
      readOnly: widget.readOnly,
      interactiveSide: widget.interactiveSide,
    );
    _seenChangeId = widget.controller.changeId;
    widget.controller.addListener(_onControllerChanged);
    _draggedFrom.addListener(_syncHiddenSquare);
    _promotion.addListener(_syncHiddenSquare);
    _animation.addListener(_syncHiddenSquare);
    _shownPieces = widget.controller.pieces;
    _showHint(widget.hint);
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
      ..enablePremoves = widget.enablePremoves
      ..revalidate();
    // Turning premoves off, making the board read-only or changing sides
    // drops a queued premove.
    if (_premove.value case final p? when !_interaction.canPremove(p.color)) {
      _cancelPremove();
    }
    if (_drag.value case final d? when !_canDragFrom(d.from)) _cancelDrag();
    _revalidatePromotion();
    if (!widget.enableUserAnnotations && oldWidget.enableUserAnnotations) {
      _clearUserDrawings(cancelDrawing: true);
    }
    if (widget.hint != oldWidget.hint) {
      _showHint(widget.hint);
    } else if (widget.hintTimeout != oldWidget.hintTimeout &&
        _hint.value != null) {
      // Restart (or stop) the timer for the hint already showing.
      _showHint(_hint.value);
    }
    _sound.pack = widget.soundPack;
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
    _dismissHint();
    _clearUserDrawings(cancelDrawing: true);
    _cancelPremove();
    _keyboard.reset();
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
    if (_playingPremove) {
      // The premove lands at once; the user already chose where it goes.
      // The opponent's move keeps sliding in, unless the premove touches
      // its squares (a recapture, say), in which case it lands too.
      final running = _animation.plan;
      if (running != null) {
        final touched = {
          for (final s in Square.values)
            if (before[s] != c.pieceAt(s)) s,
        };
        final animated = {
          for (final m in running.moving) ...[m.from, m.to],
          for (final f in running.fading) f.square,
          for (final a in running.appearing) a.square,
        };
        if (touched.any(animated.contains)) _animation.finish();
      }
      return;
    }
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
      // The notification ends in a move, even if an app listener replied
      // to it before the board heard (the id then jumps by two).
      final lastChange = widget.controller.lastChange;
      final moved = lastChange is MoveApplied && !lastChange.silent;
      _carryInputOver(_shownPieces, moved: moved);
      _cancelPromotion();
      // The hint was advice for the old position, so any change of
      // position retires it: a move, undo, navigation or a new game.
      _dismissHint();
      // User drawings are about the old position too.
      if (widget.clearUserAnnotationsOnMove) _clearUserDrawings();
      _planAnimation(previousId);
      _positionChanges.notify();
      // One sound per notification that ends in a notified move. When an
      // app listener replies to a move before the board hears of it, the
      // reply's sound is the one heard.
      _playMoveSound();
      _announceMove();
      _reportChange();
      if (!mounted || widget.controller.changeId != id) return;
      // The opponent's move arrived: play the queued premove. Any other
      // change (undo, navigation, loading, several changes at once) leaves
      // a position the premove wasn't made for, so it is dropped.
      if (moved) {
        _schedulePremove(id);
      } else {
        _cancelPremove();
      }
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
    return piece != null && _interaction.canSelect(piece.color);
  }

  bool _onPressDown(
    Square square,
    PointerDeviceKind kind, {
    bool fromKeyboard = false,
  }) {
    if (!fromKeyboard) {
      // A pointer user: hide the keyboard cursor. A mouse click also takes
      // focus, so keys work after it on desktop; touch doesn't, so a tap
      // costs no rebuild and doesn't pull focus from the app's text fields.
      _keyboard.hide();
      if (kind == PointerDeviceKind.mouse &&
          widget.enableKeyboard &&
          !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    }
    // A piece still sliding lands at once, so it can be pressed or
    // dragged without showing twice.
    _animation.finish();
    final outcome = _interaction.pressDown(square);
    // Any press that doesn't queue a new premove cancels the queued one,
    // so the user can always take it back with a tap.
    if (outcome != TapOutcome.premoved) _cancelPremove();
    // Only a press that leaves its piece selected can turn into a drag. A
    // press that made a move, or landed on nothing movable, can't.
    final dragsPiece =
        outcome == TapOutcome.selected || outcome == TapOutcome.pressedSelected;
    _pressOrigin = dragsPiece ? (square, kind) : null;
    // A press that moved, or is waiting on the promotion picker, has done
    // its job; holding it doesn't start drawing.
    return outcome != TapOutcome.moved && _promotion.value == null;
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
    _haptics.pickUp();
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
            legal: _interaction.resolveAny(from, square) != null,
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
    final outcome = _interaction.drop(drag.from, target);
    if (_promotion.value == null) _dropping = false;
    switch (outcome) {
      case TapOutcome.moved || TapOutcome.premoved:
        _haptics.drop();
      case TapOutcome.illegal:
        _playIllegal();
      case _:
        break;
    }
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
    _hintTimer?.cancel();
    _hint.dispose();
    _premove.dispose();
    _keyboard.dispose();
    _focusNode.dispose();
    _userDrawings.dispose();
    _drawing.dispose();
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
    return Semantics(
      // Names the board's own node (the keyboard focus target), so moving
      // through it doesn't read an unnamed element.
      label: widget.semanticsLabel,
      container: true,
      explicitChildNodes: true,
      child: _focusable(context, theme, dpr, ambientStyle, ambient),
    );
  }

  Widget _focusable(
    BuildContext context,
    ChessBoardTheme theme,
    double dpr,
    TextStyle ambientStyle,
    Color? ambient,
  ) {
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.enableKeyboard,
      skipTraversal: !widget.enableKeyboard,
      onKeyEvent: (node, event) => widget.enableKeyboard
          ? _keyboard.handle(event)
          : KeyEventResult.ignored,
      onFocusChange: (focused) {
        // The promotion picker takes focus while open; that isn't leaving.
        if (!focused && _promotion.value == null) _keyboard.reset();
      },
      child: _buildBoard(context, theme, dpr, ambientStyle, ambient),
    );
  }

  Widget _buildBoard(
    BuildContext context,
    ChessBoardTheme theme,
    double dpr,
    TextStyle ambientStyle,
    Color? ambient,
  ) {
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
            // Screen readers explore the board through this grid, one node
            // per square. It paints nothing and takes no pointer input; the
            // visual layers above are excluded from semantics.
            Positioned.fill(
              // While the promotion picker is open it is the only thing a
              // screen reader can reach, as for a dialog.
              child: ValueListenableBuilder<_PendingPromotion?>(
                valueListenable: _promotion,
                builder: (context, pending, child) =>
                    ExcludeSemantics(excluding: pending != null, child: child),
                child: BoardSemanticsLayer(
                  geometry: geometry,
                  describe: _describeSquare,
                  listenable: _semanticsChanges,
                  onActivate: widget.readOnly ? null : _activateSquare,
                ),
              ),
            ),
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
            if (widget.marks.any((m) => m.shape == MarkShape.fill))
              Positioned.fill(
                // Tinted squares sit under the pieces, like highlights.
                child: IgnorePointer(
                  child: _whileNotFlipping(
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: BoardMarkFillsPainter(
                          geometry: geometry,
                          marks: widget.marks,
                          theme: theme,
                        ),
                      ),
                    ),
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
              // Arrows, marks and the hint: drawn over the pieces, never
              // taking input.
              child: IgnorePointer(
                child: _whileNotFlipping(
                  RepaintBoundary(
                    child: ListenableBuilder(
                      listenable: _arrowsChanges,
                      builder: (context, _) => CustomPaint(
                        painter: BoardArrowsPainter(
                          geometry: geometry,
                          arrows: widget.arrows,
                          marks: widget.marks,
                          hint: _hint.value,
                          theme: theme,
                          userArrows: _userDrawings.arrows,
                          userMarks: _userDrawings.marks,
                          preview: _drawing.value?.arrow,
                        ),
                      ),
                    ),
                  ),
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
                    drawingEnabled: widget.enableUserAnnotations,
                    onDrawStart: _onDrawStart,
                    onDrawUpdate: (p) => _onDrawUpdate(p, geometry),
                    onDrawEnd: (p) => _onDrawEnd(p, geometry),
                    onDrawCancel: _onDrawCancel,
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
            Positioned(
              left: geometry.boardRect.left,
              width: geometry.boardRect.width,
              // Its bottom edge sits just above the board's bottom edge and
              // it grows upward, so it never hangs over outside labels.
              top: geometry.boardRect.bottom - geometry.squareSize * 0.15,
              child: FractionalTranslation(
                translation: const Offset(0, -1),
                child: IgnorePointer(
                  child: _KeyboardStatus(
                    keyboard: _keyboard,
                    squareSize: geometry.squareSize,
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

/// Shows the move being typed, and a note while in navigation mode, as a
/// small pill near the bottom of the board.
class _KeyboardStatus extends StatelessWidget {
  const _KeyboardStatus({required this.keyboard, required this.squareSize});

  final BoardKeyboard keyboard;
  final double squareSize;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([keyboard.typed, keyboard.navigationMode]),
    builder: (context, _) {
      final typed = keyboard.typed.value;
      final text = typed.isNotEmpty
          ? typed
          : keyboard.navigationMode.value
          ? 'History \u2190 \u2192'
          : null;
      if (text == null) return const SizedBox.shrink();
      return Center(
        child: Semantics(
          liveRegion: true,
          label: typed.isNotEmpty ? 'Typed move $typed' : 'History navigation',
          excludeSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xE6202124),
              borderRadius: BorderRadius.circular(squareSize * 0.2),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: squareSize * 0.25,
                vertical: squareSize * 0.1,
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: const Color(0xFFFFFFFF),
                  fontSize: (squareSize * 0.3).clamp(11.0, 20.0),
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
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
        // The picker, which holds focus inside this scope, sees keys first.
        // Keys it didn't use stop here rather than moving the board's
        // cursor underneath. Escape goes on to the binding above, and Tab
        // leaves, which cancels.
        onKeyEvent: (node, event) =>
            event.logicalKey == LogicalKeyboardKey.tab ||
                event.logicalKey == LogicalKeyboardKey.escape
            ? KeyEventResult.ignored
            : KeyEventResult.skipRemainingHandlers,
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
