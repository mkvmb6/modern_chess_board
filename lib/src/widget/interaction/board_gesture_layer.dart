import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../model/square.dart';
import '../board_geometry.dart';

/// Turns raw pointer input over the board into presses and drags.
///
/// The board acts when a press starts ([onPressDown]), so selection and
/// moves need no wait for the finger to lift. Once the pointer moves past
/// the drag slop, [onDragStart] and then [onDragUpdate] report its position;
/// [onPressUp] reports where it was released and whether it dragged. A
/// press is cancelled ([onPressCancel]) when the platform cancels the
/// pointer or a second finger lands, as in a pinch.
///
/// Only primary presses inside the playing area start a press; other
/// buttons and presses on outside labels are ignored, leaving room for
/// drawing with the secondary button later.
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
  });

  /// Where squares are, in this widget's coordinates.
  final BoardGeometry geometry;

  /// Whether a press on [square] may drag its piece. Decides the arena
  /// claim and the grab cursor.
  final bool Function(Square square) canDragFrom;

  /// Whether a piece is being dragged, for the grabbing cursor.
  final bool dragging;

  /// A press started on a square.
  final void Function(Square square, PointerDeviceKind kind) onPressDown;

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

  @override
  State<BoardGestureLayer> createState() => _BoardGestureLayerState();
}

class _BoardGestureLayerState extends State<BoardGestureLayer> {
  int? _pointer;
  Offset? _downAt;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  bool _dragged = false;

  Offset? _hoverAt;
  bool _hoverGrabbable = false;

  late final _ClaimRecognizer _claim = _ClaimRecognizer(
    shouldClaim: (local) {
      final square = widget.geometry.squareAt(local);
      return square != null && widget.canDragFrom(square);
    },
  );

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
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) {
      // A second finger, as in a pinch: abandon the first press.
      _reset();
      widget.onPressCancel();
      return;
    }
    if (e.buttons != kPrimaryButton) return;
    final square = widget.geometry.squareAt(e.localPosition);
    if (square == null) return;
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _kind = e.kind;
    _dragged = false;
    widget.onPressDown(square, e.kind);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_dragged) {
      widget.onDragUpdate(e.localPosition);
      return;
    }
    if ((e.localPosition - _downAt!).distance > _slop) {
      _dragged = true;
      widget.onDragStart(e.localPosition);
    }
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final dragged = _dragged;
    _reset();
    widget.onPressUp(e.localPosition, dragged: dragged);
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _reset();
    widget.onPressCancel();
  }

  void _onHover(PointerHoverEvent e) {
    _hoverAt = e.localPosition;
    _recheckHover();
  }

  void _onExit(PointerExitEvent e) {
    _hoverAt = null;
    _recheckHover();
  }

  void _recheckHover() {
    final at = _hoverAt;
    final square = at == null ? null : widget.geometry.squareAt(at);
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
        onHover: _onHover,
        onExit: _onExit,
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
class _ClaimRecognizer extends OneSequenceGestureRecognizer {
  _ClaimRecognizer({required this.shouldClaim});

  final bool Function(Offset local) shouldClaim;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) &&
      event.buttons == kPrimaryButton &&
      shouldClaim(event.localPosition);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'chess board press';
}
