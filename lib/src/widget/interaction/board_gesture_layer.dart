import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../model/square.dart';
import '../board_geometry.dart';

/// How long a finger must stay still before a press starts drawing.
const Duration annotationLongPress = Duration(milliseconds: 400);

/// Turns raw pointer input over the board into presses and drags.
///
/// The board acts when a press starts ([onPressDown]), so selection and
/// moves need no wait for the finger to lift. Once the pointer moves past
/// the drag slop, [onDragStart] and then [onDragUpdate] report its position;
/// [onPressUp] reports where it was released and whether it dragged. A
/// press is cancelled ([onPressCancel]) when the platform cancels the
/// pointer or a second finger lands, as in a pinch.
///
/// Only primary presses inside the playing area start a press; presses on
/// outside labels are ignored. When [drawingEnabled], the secondary mouse
/// button draws instead ([onDrawStart], [onDrawUpdate], [onDrawEnd]), and
/// so does a touch held still for [annotationLongPress]; the held press is
/// cancelled first.
///
/// Raw pointer events never enter Flutter's gesture arena, so a scroll view
/// around the board would otherwise scroll while a piece is dragged. The
/// layer therefore claims the arena as soon as a press lands on a piece
/// [canDragFrom] allows. Presses elsewhere are not claimed, so the page
/// still scrolls from empty squares. A side effect is that tap, long-press
/// and swipe gestures of widgets around the board (such as an `InkWell` or
/// a `PageView`) don't fire for presses that start on a movable piece.
///
/// The mouse cursor shows `grab` over pieces that can be dragged and
/// `grabbing` while [dragging].
class BoardGestureLayer extends StatefulWidget {
  /// Creates the gesture layer.
  const BoardGestureLayer({
    super.key,
    required this.geometry,
    required this.canDragFrom,
    required this.dragging,
    required this.onPressDown,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onPressUp,
    required this.onPressCancel,
    this.refresh,
    this.onHoverSquare,
    this.drawingEnabled = false,
    this.onDrawStart,
    this.onDrawUpdate,
    this.onDrawEnd,
    this.onDrawCancel,
  });

  /// Whether right-click and long-press draw annotations.
  final bool drawingEnabled;

  /// Drawing started on a square.
  final ValueChanged<Square>? onDrawStart;

  /// The pointer moved while drawing, at this local position.
  final ValueChanged<Offset>? onDrawUpdate;

  /// Drawing ended at this local position.
  final ValueChanged<Offset>? onDrawEnd;

  /// Drawing was abandoned.
  final VoidCallback? onDrawCancel;

  /// Where squares are, in this widget's coordinates.
  final BoardGeometry geometry;

  /// Whether a press on [square] may drag its piece. Decides the arena
  /// claim and the grab cursor.
  final bool Function(Square square) canDragFrom;

  /// Whether a piece is being dragged, for the grabbing cursor.
  final bool dragging;

  /// A press started on a square. Returns whether holding the press may
  /// still turn it into drawing: false when the press made a move or
  /// opened the promotion picker.
  final bool Function(Square square, PointerDeviceKind kind) onPressDown;

  /// The pointer moved past the drag slop, at this local position.
  final ValueChanged<Offset> onDragStart;

  /// The pointer moved while dragging.
  final ValueChanged<Offset> onDragUpdate;

  /// The press ended at [position]; `dragged` is true if it passed the slop.
  final void Function(Offset position, {required bool dragged}) onPressUp;

  /// The press was abandoned.
  final VoidCallback onPressCancel;

  /// Notifies when the position changes, so the cursor can be rechecked
  /// without waiting for the mouse to move.
  final Listenable? refresh;

  /// Called with the square under a hovering mouse, or null when it leaves
  /// the playing area. Only fires when the square changes.
  final ValueChanged<Square?>? onHoverSquare;

  @override
  State<BoardGestureLayer> createState() => _BoardGestureLayerState();
}

class _BoardGestureLayerState extends State<BoardGestureLayer> {
  int? _pointer;
  Offset? _downAt;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  bool _dragged = false;
  bool _drawing = false;
  Timer? _longPress;

  Offset? _hoverAt;
  bool _hoverGrabbable = false;

  late final _ClaimRecognizer _claim = _ClaimRecognizer(
    shouldClaim: (local) {
      final square = widget.geometry.squareAt(local);
      return square != null && widget.canDragFrom(square);
    },
    mayHold: (event) =>
        widget.drawingEnabled &&
        event.kind != PointerDeviceKind.mouse &&
        widget.geometry.squareAt(event.localPosition) != null,
  );

  /// Whether the browser's context menu is turned off while the mouse is
  /// over the board, so right-click can draw on the web.
  bool _contextMenuOff = false;

  void _setContextMenuOff(bool off) {
    if (!kIsWeb || off == _contextMenuOff) return;
    _contextMenuOff = off;
    off
        ? BrowserContextMenu.disableContextMenu()
        : BrowserContextMenu.enableContextMenu();
  }

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_recheckHover);
  }

  @override
  void didUpdateWidget(BoardGestureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refresh != widget.refresh) {
      oldWidget.refresh?.removeListener(_recheckHover);
      widget.refresh?.addListener(_recheckHover);
    }
    _recheckHover();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_recheckHover);
    _longPress?.cancel();
    _setContextMenuOff(false);
    super.dispose();
  }

  /// A drag starts sooner with precise pointers; on touch, a finger needs
  /// more room to tell a tap from a drag. A mouse's own hit slop (about a
  /// pixel) would turn a slightly jittery click into a drag.
  double get _slop => _kind == PointerDeviceKind.touch ? kTouchSlop : 6;

  void _reset() {
    _pointer = null;
    _downAt = null;
    _dragged = false;
    _drawing = false;
    _longPress?.cancel();
    _longPress = null;
  }

  void _startDrawing(Square square) {
    _longPress?.cancel();
    _longPress = null;
    _drawing = true;
    widget.onDrawStart?.call(square);
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) {
      // A second finger, as in a pinch: abandon the first press.
      final drawing = _drawing;
      _reset();
      drawing ? widget.onDrawCancel?.call() : widget.onPressCancel();
      return;
    }
    final square = widget.geometry.squareAt(e.localPosition);
    if (square == null) return;
    if (e.buttons == kSecondaryMouseButton && widget.drawingEnabled) {
      _pointer = e.pointer;
      _downAt = e.localPosition;
      _kind = e.kind;
      _startDrawing(square);
      return;
    }
    if (e.buttons != kPrimaryButton) return;
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _kind = e.kind;
    _dragged = false;
    final mayDraw = widget.onPressDown(square, e.kind);
    if (mayDraw && widget.drawingEnabled && e.kind != PointerDeviceKind.mouse) {
      // A finger held still turns the press into drawing. It takes the
      // gesture arena then, so an enclosing scroll view stops scrolling;
      // if the scroll view already won, the press stays a scroll.
      _longPress = Timer(annotationLongPress, () {
        _longPress = null;
        if (!mounted || _pointer != e.pointer || _dragged) return;
        if (!widget.drawingEnabled || !_claim.claim(e.pointer)) return;
        widget.onPressCancel();
        _startDrawing(square);
      });
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_drawing) {
      widget.onDrawUpdate?.call(e.localPosition);
      return;
    }
    if (_dragged) {
      widget.onDragUpdate(e.localPosition);
      return;
    }
    if ((e.localPosition - _downAt!).distance > _slop) {
      _dragged = true;
      _longPress?.cancel();
      _longPress = null;
      widget.onDragStart(e.localPosition);
    }
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    if (_drawing) {
      _reset();
      widget.onDrawEnd?.call(e.localPosition);
      return;
    }
    final dragged = _dragged;
    _reset();
    widget.onPressUp(e.localPosition, dragged: dragged);
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    final drawing = _drawing;
    _reset();
    drawing ? widget.onDrawCancel?.call() : widget.onPressCancel();
  }

  void _onHover(PointerHoverEvent e) {
    _hoverAt = e.localPosition;
    _recheckHover();
  }

  void _onExit(PointerExitEvent e) {
    _hoverAt = null;
    _recheckHover();
  }

  Square? _hoverSquare;

  /// Reports a new hover square. During a build (for example after a flip
  /// or resize moved the squares under a resting mouse) the report waits
  /// until after the frame, because the listener rebuilds other widgets.
  void _reportHover(Square? square) {
    final callback = widget.onHoverSquare;
    if (callback == null) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hoverSquare == square) callback(square);
      });
    } else {
      callback(square);
    }
  }

  void _recheckHover() {
    final at = _hoverAt;
    final square = at == null ? null : widget.geometry.squareAt(at);
    if (square != _hoverSquare) {
      _hoverSquare = square;
      _reportHover(square);
    }
    final grabbable = square != null && widget.canDragFrom(square);
    if (grabbable != _hoverGrabbable && mounted) {
      setState(() => _hoverGrabbable = grabbable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cursor = widget.dragging
        ? SystemMouseCursors.grabbing
        : _hoverGrabbable
        ? SystemMouseCursors.grab
        : MouseCursor.defer;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _ClaimRecognizer:
            GestureRecognizerFactoryWithHandlers<_ClaimRecognizer>(
              () => _claim,
              (_) {},
            ),
      },
      child: MouseRegion(
        cursor: cursor,
        onEnter: (_) => _setContextMenuOff(widget.drawingEnabled),
        onHover: _onHover,
        onExit: (e) {
          _setContextMenuOff(false);
          _onExit(e);
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onCancel,
        ),
      ),
    );
  }
}

/// Wins the gesture arena at once for presses [shouldClaim] accepts, so
/// enclosing scroll views and other gestures give way to a piece drag.
///
/// Other touch presses that [mayHold] allows enter the arena undecided:
/// [claim] wins it later (when a long press starts drawing), and lifting
/// the finger gives it up, so taps and scrolls around the board still work.
class _ClaimRecognizer extends OneSequenceGestureRecognizer {
  _ClaimRecognizer({required this.shouldClaim, required this.mayHold});

  final bool Function(Offset local) shouldClaim;
  final bool Function(PointerDownEvent event) mayHold;

  /// Pointers in the arena, not yet decided.
  final Set<int> _held = {};

  /// Pointers whose arena this recognizer won.
  final Set<int> _won = {};

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) &&
      event.buttons == kPrimaryButton &&
      (shouldClaim(event.localPosition) || mayHold(event));

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (shouldClaim(event.localPosition)) {
      resolvePointer(event.pointer, GestureDisposition.accepted);
    } else {
      _held.add(event.pointer);
    }
  }

  /// Takes the arena for [pointer]. Returns false if another gesture, such
  /// as a scroll, already won it.
  bool claim(int pointer) {
    if (_won.contains(pointer)) return true;
    if (!_held.contains(pointer)) return false;
    resolvePointer(pointer, GestureDisposition.accepted);
    return _won.contains(pointer);
  }

  @override
  void acceptGesture(int pointer) {
    _held.remove(pointer);
    _won.add(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _held.remove(pointer);
    _won.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_held.contains(event.pointer)) {
        resolvePointer(event.pointer, GestureDisposition.rejected);
      }
      _won.remove(event.pointer);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'chess board press';
}
