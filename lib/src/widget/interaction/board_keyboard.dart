import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../model/square.dart';
import '../board_geometry.dart';

/// What keyboard input asks the board to do. The board supplies these, so
/// keys go through the same rules as pointer input.
class KeyboardActions {
  /// Creates the actions.
  const KeyboardActions({
    required this.orientation,
    required this.tap,
    required this.clearSelection,
    required this.busy,
    required this.submitSan,
    required this.navigationLocked,
    required this.back,
    required this.forward,
    required this.toStart,
    required this.toEnd,
  });

  /// The board's current orientation, for arrow directions.
  final BoardOrientation Function() orientation;

  /// Acts like a tap on [square].
  final void Function(Square square) tap;

  /// Clears the selection (and anything else Escape should close).
  /// Returns whether there was anything to clear, so an unused Escape
  /// reaches the app.
  final bool Function() clearSelection;

  /// Whether another part of the board (the promotion picker) has the
  /// keys right now.
  final bool Function() busy;

  /// Plays the move written in SAN. Returns whether it was played.
  final bool Function(String san) submitSan;

  /// Whether the board only navigates history (for example, read-only).
  final bool Function() navigationLocked;

  /// Steps back through history.
  final VoidCallback back;

  /// Steps forward through history.
  final VoidCallback forward;

  /// Jumps to the start of the game.
  final VoidCallback toStart;

  /// Jumps to the latest position.
  final VoidCallback toEnd;
}

/// The legal moves a typed [text] means, from the moves' [sans].
///
/// Matching ignores check marks, annotations and `=`, accepts castling with
/// zeros or a lowercase o, and accepts a from-to coordinate move such as
/// `e2e4` or `e7e8q`. Letter case is forgiven: a lowercase piece letter
/// (`nf3`, `qh5`) still finds the piece move. Where case matters, `b` means
/// the b-file and `B` the bishop, as in `bxc3` and `Bxc3`; a lowercase `b`
/// only falls back to the bishop when no pawn move matches.
List<int> matchTypedMove(
  String text,
  List<({String san, String from, String to, String? promotion})> moves,
) {
  final wanted = normalizeTypedSan(text);
  if (wanted.isEmpty) return const [];
  List<int> where(bool Function(String san) test) => [
    for (final (i, m) in moves.indexed)
      if (test(normalizeTypedSan(m.san))) i,
  ];
  // Exact, then a coordinate move, then ignoring case.
  final exact = where((s) => s == wanted);
  if (exact.isNotEmpty) return exact;
  final coord = RegExp(
    r'^([a-h][1-8])-?([a-h][1-8])([qrbn])?$',
  ).firstMatch(wanted.toLowerCase());
  if (coord != null) {
    return [
      for (final (i, m) in moves.indexed)
        if (m.from == coord[1] &&
            m.to == coord[2] &&
            (m.promotion ?? '') ==
                (coord[3] ?? (m.promotion == null ? '' : 'q')))
          i,
    ];
  }
  final lower = wanted.toLowerCase();
  final loose = where((s) => s.toLowerCase() == lower);
  if (loose.length <= 1) return loose;
  // `bxc3` and `Bxc3` both match ignoring case: the pawn wins.
  final pawns = [
    for (final i in loose)
      if (!RegExp('^[KQRBN]').hasMatch(moves[i].san)) i,
  ];
  return pawns.isNotEmpty ? pawns : loose;
}

/// [san] as compared when matching a typed move: without check marks,
/// annotations or `=`, and with castling written with letters.
String normalizeTypedSan(String san) => san
    .trim()
    .replaceAll('0', 'O')
    .replaceAll('o', 'O')
    .replaceAll('=', '')
    .replaceAll(RegExp(r'[+#!?]+$'), '');

/// Characters kept in a typed move: letters, digits and the SAN signs.
/// Nothing is silently dropped, so a mistyped move is rejected and stays on
/// screen for correction rather than turning into a different move.
final _sanChar = RegExp(r'^[A-Za-z0-9=+#\-]$');

/// Keyboard play: a focus cursor moved with the arrow keys, Enter or Space
/// to act on the focused square, Escape to clear, typed moves in SAN, and a
/// navigation mode (Shift+H) in which left and right step through history.
///
/// The cursor stays hidden until a key is pressed, so pointer and touch
/// users never see it, and a pointer press hides it again.
class BoardKeyboard {
  /// Creates keyboard handling that acts through [actions].
  BoardKeyboard(this.actions);

  /// What keys do.
  KeyboardActions actions;

  /// The square under the focus cursor, or null while it is hidden.
  final ValueNotifier<Square?> focus = ValueNotifier(null);

  /// The move typed so far.
  final ValueNotifier<String> typed = ValueNotifier('');

  /// Whether left and right step through history. Toggled with Shift+H;
  /// plain letters always type a move.
  final ValueNotifier<bool> navigationMode = ValueNotifier(false);

  bool get _navigating => navigationMode.value || actions.navigationLocked();

  /// Where the cursor first appears: the e-file, second rank from the side
  /// at the bottom, where the first move is usually made.
  Square _start() =>
      actions.orientation() == BoardOrientation.white ? Square.e2 : Square.e7;

  /// Hides the cursor and drops typed text, as when a pointer is used.
  void hide() {
    focus.value = null;
    typed.value = '';
  }

  /// Forgets everything, as when the board loses focus or gets a new game.
  void reset() {
    hide();
    navigationMode.value = false;
  }

  /// Handles a key. Returns whether it was used, so unused keys (such as
  /// Tab) keep their usual meaning.
  KeyEventResult handle(KeyEvent event) {
    if (event is KeyUpEvent || actions.busy()) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    // History navigation mode: the one shortcut of the board's own. A
    // letter can't toggle it, because letters type moves ("nf3").
    if (key == LogicalKeyboardKey.keyH &&
        keys.isShiftPressed &&
        !keys.isControlPressed &&
        !keys.isMetaPressed &&
        !keys.isAltPressed &&
        typed.value.isEmpty &&
        event is KeyDownEvent &&
        !actions.navigationLocked()) {
      navigationMode.value = !navigationMode.value;
      return KeyEventResult.handled;
    }
    // Keys with Ctrl, Cmd or Alt, or Shift with an arrow, are the app's
    // (copy, find, browser back, selection) and pass through.
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final locked = actions.navigationLocked();

    if (_navigating) {
      switch (key) {
        case LogicalKeyboardKey.arrowLeft:
          actions.back();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          actions.forward();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.home:
          actions.toStart();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.end:
          actions.toEnd();
          return KeyEventResult.handled;
      }
    }

    // A read-only board only navigates: the cursor, typing and Enter have
    // nothing to do there, and arrow keys keep scrolling the page.
    if (locked) return KeyEventResult.ignored;

    final step = keys.isShiftPressed ? null : _arrowStep(key);
    if (step != null) {
      final current = focus.value;
      if (current == null) {
        focus.value = _start();
      } else {
        final (df, dr) = actions.orientation() == BoardOrientation.white
            ? step
            : (-step.$1, -step.$2);
        final file = (current.file + df).clamp(0, 7);
        final rank = (current.rank + dr).clamp(0, 7);
        focus.value = Square.at(file, rank);
      }
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent && key != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }

    switch (key) {
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        if (typed.value.isNotEmpty) {
          // A rejected move stays, so it can be corrected.
          if (actions.submitSan(typed.value)) typed.value = '';
          return KeyEventResult.handled;
        }
        _activate();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _activate();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (typed.value.isNotEmpty) {
          typed.value = '';
          return KeyEventResult.handled;
        }
        if (actions.clearSelection()) return KeyEventResult.handled;
        if (focus.value != null) {
          focus.value = null;
          return KeyEventResult.handled;
        }
        // Nothing to close: let the app use Escape.
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.backspace:
        final t = typed.value;
        if (t.isEmpty) return KeyEventResult.ignored;
        typed.value = t.substring(0, t.length - 1);
        return KeyEventResult.handled;
    }

    final ch = event.character;
    if (ch == null || ch.length != 1) return KeyEventResult.ignored;
    // A space or Enter is handled above; other characters start a move only
    // if they could begin one, so stray keys don't pop the typing pill.
    if (_sanChar.hasMatch(ch) && typed.value.length < 10) {
      typed.value += ch;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activate() {
    final square = focus.value;
    if (square == null) {
      focus.value = _start();
      return;
    }
    actions.tap(square);
  }

  /// The step an arrow key takes, as seen with white at the bottom.
  (int, int)? _arrowStep(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowUp => (0, 1),
    LogicalKeyboardKey.arrowDown => (0, -1),
    LogicalKeyboardKey.arrowLeft => (-1, 0),
    LogicalKeyboardKey.arrowRight => (1, 0),
    _ => null,
  };

  /// Releases the notifiers.
  void dispose() {
    focus.dispose();
    typed.dispose();
    navigationMode.dispose();
  }
}
