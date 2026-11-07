import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../model/square.dart';
import '../board_geometry.dart';

/// Turns raw pointer input over the board into presses on squares.
///
/// The board acts when a press starts ([onPressDown]), so selection and
/// moves need no wait for the finger to lift. [onPressUp] reports whether
/// the pointer travelled further than the touch slop, which later decides
/// between a tap and a drag. A press is cancelled ([onPressCancel]) when the
/// platform cancels the pointer or a second finger lands, as in a pinch.
///
/// Only primary presses inside the playing area start a press; other
/// buttons and presses on outside labels are ignored, leaving room for
/// drawing with the secondary button later.
///
/// A raw [Listener] is used instead of gesture recognizers so tap, drag,
/// right-click and long-press can be told apart in one place, with no
/// gesture-arena delay before the board responds.
class BoardGestureLayer extends StatefulWidget {
  /// Creates the gesture layer.
  const BoardGestureLayer({
    super.key,
    required this.geometry,
    required this.onPressDown,
    required this.onPressUp,
    required this.onPressCancel,
  });

  /// Where squares are, in this widget's coordinates.
  final BoardGeometry geometry;

  /// A press started on a square.
  final ValueChanged<Square> onPressDown;

  /// The press ended; `dragged` is true if the pointer moved past the slop.
  final void Function({required bool dragged}) onPressUp;

  /// The press was abandoned.
  final VoidCallback onPressCancel;

  @override
  State<BoardGestureLayer> createState() => _BoardGestureLayerState();
}

class _BoardGestureLayerState extends State<BoardGestureLayer> {
  int? _pointer;
  Offset? _downAt;
  bool _dragged = false;

  // The same tolerance for every pointer kind. A mouse's precise hit slop is
  // about one pixel, which would turn a slightly jittery click into a drag.
  static const double _tapSlop = kTouchSlop;

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
    _dragged = false;
    widget.onPressDown(square);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer || _dragged) return;
    if ((e.localPosition - _downAt!).distance > _tapSlop) _dragged = true;
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final dragged = _dragged;
    _reset();
    widget.onPressUp(dragged: dragged);
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _reset();
    widget.onPressCancel();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onCancel,
  );
}
