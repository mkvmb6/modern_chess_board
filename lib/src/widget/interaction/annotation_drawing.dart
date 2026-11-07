import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../model/annotations.dart';
import '../../model/square.dart';
import '../../theme/chess_board_theme.dart';

/// The color for a user drawing with the given modifier keys held:
/// none is [AnnotationColors.plain], Shift is red, Alt is blue and
/// Shift+Alt is yellow.
Color annotationColorFor(
  AnnotationColors colors, {
  required bool shift,
  required bool alt,
}) => switch ((shift, alt)) {
  (false, false) => colors.plain,
  (true, false) => colors.shift,
  (false, true) => colors.alt,
  (true, true) => colors.shiftAlt,
};

/// The color for the modifier keys held right now.
Color currentAnnotationColor(AnnotationColors colors) {
  final keys = HardwareKeyboard.instance;
  return annotationColorFor(
    colors,
    shift: keys.isShiftPressed,
    alt: keys.isAltPressed,
  );
}

/// Arrows and circles the user has drawn on the board.
///
/// Drawing something that is already there with the same color removes it;
/// drawing it in another color recolors it, as on chess sites. Lists are
/// replaced on every change, never mutated, so listeners and the app's
/// callbacks always get a fresh unmodifiable value.
class UserAnnotations extends ChangeNotifier {
  List<Arrow> _arrows = const [];
  List<SquareMark> _marks = const [];

  /// The arrows drawn so far, oldest first.
  List<Arrow> get arrows => _arrows;

  /// The circled squares, oldest first.
  List<SquareMark> get marks => _marks;

  /// Whether anything is drawn.
  bool get isEmpty => _arrows.isEmpty && _marks.isEmpty;

  /// Adds, recolors or removes the arrow from [from] to [to]. Returns
  /// false (and changes nothing) for a zero-length arrow.
  bool toggleArrow(Square from, Square to, Color color) {
    if (from == to) return false;
    final arrow = Arrow.fromSquares(from, to, color: color);
    final i = _arrows.indexWhere(
      (a) => a.from == arrow.from && a.to == arrow.to,
    );
    final next = [..._arrows];
    if (i < 0) {
      next.add(arrow);
    } else if (next[i].color == color) {
      next.removeAt(i);
    } else {
      next[i] = arrow;
    }
    _arrows = List.unmodifiable(next);
    notifyListeners();
    return true;
  }

  /// Adds, recolors or removes the circle on [square].
  void toggleCircle(Square square, Color color) {
    final mark = SquareMark(square.name, color: color);
    final i = _marks.indexWhere((m) => m.square == mark.square);
    final next = [..._marks];
    if (i < 0) {
      next.add(mark);
    } else if (next[i].color == color) {
      next.removeAt(i);
    } else {
      next[i] = mark;
    }
    _marks = List.unmodifiable(next);
    notifyListeners();
  }

  /// Removes everything. Returns which lists changed, so the board only
  /// reports what actually did.
  ({bool arrows, bool marks}) clear() {
    final changed = (arrows: _arrows.isNotEmpty, marks: _marks.isNotEmpty);
    if (!changed.arrows && !changed.marks) return changed;
    _arrows = const [];
    _marks = const [];
    notifyListeners();
    return changed;
  }
}

/// An arrow being drawn, from where the press started to the square under
/// the pointer now.
@immutable
class DrawingPreview {
  /// Creates a preview.
  const DrawingPreview({
    required this.from,
    required this.to,
    required this.color,
  });

  /// Where drawing started.
  final Square from;

  /// The square under the pointer, or null off the board.
  final Square? to;

  /// The color it will be drawn in.
  final Color color;

  /// The preview as an arrow, or null while it would draw a circle or
  /// nothing.
  Arrow? get arrow {
    final t = to;
    return t == null || t == from
        ? null
        : Arrow.fromSquares(from, t, color: color);
  }

  @override
  bool operator ==(Object other) =>
      other is DrawingPreview &&
      other.from == from &&
      other.to == to &&
      other.color == color;

  @override
  int get hashCode => Object.hash(from, to, color);
}
