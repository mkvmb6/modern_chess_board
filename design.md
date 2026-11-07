# Design: modern_chess_board

This document describes how the package meets `requirements.md`. Section references like (R2) point to requirement sections.

## 1. Key decisions

| Decision | Choice | Reason |
|---|---|---|
| Rules engine | `chess` 0.8.1 (BSD-2, chess.js port) | Legal move generation, SAN, FEN, PGN, undo, all draw rules. `dartchess` was rejected because GPL-3.0 would force GPL on every app using the package. |
| Piece rendering | `flutter_svg` 2.3.2 with the 12 SVGs in `svg/` | The assets only use paths, gradients and clip paths, which `flutter_svg` supports. Vector output stays sharp at any size (R8). |
| State | `ChangeNotifier` controller plus internal widget state | No third-party state library. Apps don't need to wire listeners (R6). |
| Rendering | `CustomPainter` layers inside a `Stack` | Each layer repaints on its own, so selection, hover and drag don't rebuild all 64 squares (R14). |
| Property tests | `glados` 1.1.7 (dev only) | Random legal games, with shrinking on failure. |
| SDK | Dart `^3.11.0`, Flutter `>=3.41.0` | The minimum required by `flutter_svg` 2.3.2. Developed on Flutter 3.47.7. |

Runtime dependencies use caret ranges (`^0.8.1`, `^2.3.2`), because exact pins in a published library cause version conflicts for apps and `pub publish` warns about them. Dev dependencies are pinned exactly.

## 2. Package layout

```
modern_chess_board/
  lib/
    modern_chess_board.dart          # single public import (R13)
    src/
      model/        square.dart, piece.dart, board_move.dart, arrow.dart,
                    square_mark.dart, game_status.dart, sound_event.dart
      controller/   chess_board_controller.dart, history.dart,
                    move_classifier.dart, notation.dart
      theme/        chess_board_theme.dart (with presets), color_math.dart
      pieces/       piece_set.dart (sets, SVG cache, ChessPieceView)
      widget/       chess_board.dart, board_state.dart, board_geometry.dart,
                    interaction/ (tap, drag, premove, annotation_drawing, keyboard)
                    layers/ (squares, highlights, pieces, arrows, labels,
                             drag_feedback, promotion_overlay)
                    animation/ (move_animator.dart, flip_animator.dart)
                    semantics/ (square_semantics.dart, announcer.dart)
      sound/        chess_sound_pack.dart, safe_sound_dispatcher.dart
      haptics/      haptics.dart
  assets/pieces/default/  wK.svg ... bP.svg   # copied from svg/
  example/                                     # demo app (R15)
  test/  unit/ widget/ property/ golden/
```

The public barrel file exports only the public types. Everything else stays under `src/` and is not exported.

## 3. Domain model (`src/model`)

- `Square`: an immutable value object with file (0-7) and rank (0-7). `Square.tryParse('e4')` returns null for bad names, which is how arrows and marks ignore them (R5). Named constants (`Square.e4`) and all 64 squares in a list.
- `PieceType` enum (pawn, knight, bishop, rook, queen, king), `PieceColor` enum (white, black), `Piece(color, type)` with value equality and a `code` such as `wK`.
- `BoardMove`: from, to, optional promotion, plus SAN, captured piece, and flags (castle, en passant, promotion, check, mate) once the move is applied.
- `Arrow(from, to, {color})`, `SquareMark(square, {color, shape: circle|fill})` with `markedSquare`. Both take square names as strings and resolve them safely.
- `GameStatus`: `ongoing`, `checkmate`, `stalemate`, `draw`. A `DrawReason` covers fifty-move, threefold repetition and insufficient material. `GameResult` is `1-0`, `0-1` or `1/2-1/2`.
- `SoundEvent` enum: `move`, `capture`, `check`, `castle`, `promotion`, `gameEnd`, `illegal`.

All model types are immutable with `==` and `hashCode`.

## 4. Controller (`src/controller`)

`ChessBoardController extends ChangeNotifier` owns one `Chess` instance from the `chess` package.

### 4.1 History model

The controller keeps the full move line separately from the engine:

- `List<BoardMove> _line`: every move played.
- `int _cursor`: the number of moves currently applied to the engine (0 to `_line.length`).

When `_cursor == _line.length`, the board is "live". Navigating backward calls `undo()` on the engine and decrements the cursor. Navigating forward replays `_line[_cursor]`. `_line` stays intact, which gives non-destructive history navigation.

- `undo()` removes the last move from `_line` (destructive) and is only allowed while live.
- A user move while not live is rejected, unless `allowBranching` is true. In that case `_line` is cut at the cursor and the new move is appended.
- `goTo(int ply)`, `back()`, `forward()`, `goToStart()`, `goToEnd()`.
- `isViewingHistory` is true when `_cursor < _line.length`.

### 4.2 Public API

Read access: `fen`, `turn`, `isCheck`, `isCheckmate`, `isStalemate`, `isDraw`, `drawReason`, `isGameOver`, `status`, `result`, `history` (`List<BoardMove>` up to the cursor), `fullLine`, `pgn`, `pgnHeaders`, `halfMoveCount`, `lastMove`, `legalMovesFrom(Square)`, `pieceAt(Square)`, `engine` (raw `Chess`, R6).

Actions: each returns `bool` and takes `{bool notify = true}`:

- `move(from, to, {promotion})` resolves the move against `engine.moves({'verbose': true})`. Matching is on from, to and promotion fields, never on SAN strings. Applies the move if a match is found.
- `moveSan(String san)` checks the SAN against the same verbose move list.
- `undo()`, `reset()`, `loadFen(String)`, `loadPgn(String)`. Loading clears the line. An invalid FEN or PGN is detected before anything changes, so the current game stays untouched.
- `back()`, `forward()`, `goTo(int)`.
- `notifyListeners()` stays public so apps can batch changes and notify once.

### 4.3 Change descriptions

Every notification carries a description of what changed. The board needs it to decide whether to animate and whether to play a sound:

```dart
sealed class BoardChange {}
class MoveApplied extends BoardChange { BoardMove move; MoveSource source; }  // user | code
class NavigatedTo extends BoardChange { int fromPly; int toPly; }
class PositionReplaced extends BoardChange {}  // reset, loadFen, loadPgn, undo
```

`controller.lastChange` holds the most recent change. A `changeId` counter lets the widget tell a new change from a rebuild. Every change carries a `silent` flag, set when `notify: false` was used. A silent move is still recorded as `MoveApplied`, so apps can inspect it, but the board neither animates nor plays sound for any silent change when the app finally calls `notifyListeners()` (R10).

Engine workarounds, discovered while building task 3:

- **PGN** is written and parsed by the controller, not by `package:chess`. The engine's `copy()` shares `Piece` objects, so `pgn()` on a copy corrupted the live board after a promotion. Its `load_pgn` also threw on some input and printed on a bad `FEN` header.
- **FEN loading** adds checks the engine lacks: exactly one king per side, no pawns on back ranks, the side not to move not in check, castling rights only with king and rook at home, and a plausible en passant square.
- **Repetition** uses the controller's own position keys, which include the en passant square only when a capture there is actually legal.
- **Caching**: legal moves, status and draw reason are computed once per position.

### 4.4 Move classification (`move_classifier.dart`)

`SoundEvent classifyMove(BoardMove move, GameStatus status)`, checked in this order: game over, then promotion flag, then castle flag, then check, then capture (en passant included), then normal move. Every game-ending status gives `gameEnd`, including draws by repetition, the fifty-move rule and insufficient material. It is a pure function, so it can be tested exhaustively.

### 4.5 Notation helpers

`notation.dart` has `describeMove(move, {drawReason})`, which turns a move into spoken English such as "White knight to f3, check", "White knight from b1 to d2" (when SAN disambiguates), or "White castles kingside", for screen-reader announcements (R11). A checking move that also draws keeps both: "..., check, draw by threefold repetition".

## 5. Widget architecture (`src/widget`)

### 5.1 Public widget

```dart
ChessBoard({
  required ChessBoardController controller,
  BoardOrientation orientation = white,
  String? initialFen,
  bool readOnly = false,
  InteractiveSide interactiveSide = both,
  ChessBoardTheme theme = ChessBoardTheme.green,
  Color? lightSquareColor, Color? darkSquareColor, Color? checkmateColor,
  PieceSet pieceSet = PieceSet.standard,
  CoordinateMode coordinates = inside,
  Duration animationDuration = 150ms,
  bool showLastMove = true,
  List<Arrow> arrows = const [], List<SquareMark> marks = const [],
  Arrow? hint, Duration? hintTimeout,
  bool enableUserAnnotations = true, bool clearUserAnnotationsOnMove = true,
  ValueChanged<List<Arrow>>? onUserArrowsChanged, ...onUserMarksChanged,
  bool enablePremoves = false,
  bool autoQueen = false, PromotionPickerBuilder? promotionPickerBuilder,
  ChessSoundPack soundPack = const SilentSoundPack(),
  bool enableHaptics = false,
  bool enableKeyboard = true, FocusNode? focusNode,
  void Function(BoardMove)? onMove, void Function(GameStatus, GameResult)? onGameEnd,
})
```

An `initialFen` is applied once, in `initState`, through `controller.loadFen(notify: false)`, and only when the controller is still untouched: no changes yet and at the standard start. Remounting the board, or giving the same controller to a second board, therefore never wipes a game in progress. An invalid value triggers an `ArgumentError` with the bad FEN in the message every time. Later changes to `initialFen` are ignored, as R1 requires. `ChessBoardController(fen: ...)` is the preferred way to start from a position.

Labels inherit the app font family from `DefaultTextStyle`; size, weight 600 and line height are the board's own. Outside labels use the ambient text colour at 72% opacity unless the theme sets a margin colour. Flutter's red "missing Material" debug style is detected and never copied. Golden tests load Roboto from `test/fonts` in `flutter_test_config.dart` and are tagged `golden`. They are generated on Windows; other OSes run `flutter test --exclude-tags golden`.

### 5.2 Layout and geometry

`BoardLayout` sizes the board with a small custom render box. The side is `min(maxWidth, maxHeight)`. If only one side is bounded it uses that one, and if neither is bounded it uses `fallbackSize` (320 by default). Under loose constraints the widget is exactly the square, so it never takes space from siblings in a `Flexible` or `Stack`. Under tight non-square constraints it fills them and centres the square. The render box answers intrinsic queries itself, so the board works inside `IntrinsicHeight` next to a move list. `BoardMetrics.forSide` then splits the side up. With `CoordinateMode.outside`, the label font is `max(9, side * 0.022)`, scaled by the app text scale but capped at 4% of the side. The margin is `font * 1.6`, capped at 20% of the side, and the playing area is `side - 2 * margin`, so the whole widget still fits (R9). Inside labels are `max(9, square * 0.18)`, scaled and capped at a third of a square. On boards too small for readable 9px labels (about 100px or less), `showLabels` is false and no margin is reserved.

`BoardGeometry(size, orientation, origin)` is the only place that maps squares to pixel offsets and pixel offsets back to squares. Every layer uses it, which is how all of them follow orientation (R1). Positions are exact logical pixels; painters handle device-pixel seams, for example by filling the board with the light colour and painting dark squares on top. During a flip animation, `flipOrigin(square, t)` moves each piece along an arc as the board turns half a circle around its centre. Pieces stay upright and keep their distance from the centre, so they never pile up in the middle; labels cross-fade.

### 5.3 Layer stack (bottom to top)

1. `SquaresLayer`: square colors. Repaints only when the theme or size changes.
2. `HighlightLayer`: last move, selection, check/mate tint, premove, hover, keyboard focus and legal-move dots and rings. It does not tint a square twice: if a square is both selected and part of the last move, only the selection color is painted.
3. `LabelsLayer`, inside mode: label color comes from the theme, or contrasts with the square under it. Font size is `max(9, squareSize * 0.18)`.
4. `PiecesLayer`: one `Positioned` + `RepaintBoundary` per piece, keyed by an identity that persists across moves. Pieces being dragged or animated are excluded.
5. `AnimationLayer`: pieces in flight and fading captured pieces.
6. `ArrowsLayer`: app arrows, user-drawn arrows, then the hint, all wrapped in `IgnorePointer`. App arrows have solid shafts and filled triangle heads. The hint has a dashed shaft, an open chevron head, and the theme's hint color.
7. `DragFeedbackLayer`: legal/illegal tint under the pointer. Never shown on the source square, and never in read-only mode.
8. `GestureLayer`: a transparent `Listener` + `MouseRegion` covering the whole board.
9. `PromotionOverlay`: shown only while a promotion is pending.

Ephemeral state (selection, drag, hover, focus, premove, pending promotion) lives in `ValueNotifier`s, and each layer only listens to the notifiers it needs. A tap on an empty square with nothing selected leaves every notifier unchanged, so nothing rebuilds (R2).

### 5.4 Interaction state machine

All pointer input is handled with a raw `Listener`, so tap, drag, right-click and long-press can be told apart in one place:

```
idle
  └ pointer down on movable piece → pressed(piece)
pressed
  ├ moves > kTouchSlop          → dragging (selection = piece)
  ├ up without moving           → tap-select logic
  └ long-press timer (touch)    → drawing (annotation)
dragging
  ├ up on legal square          → apply (no animation) / promotion picker
  ├ up elsewhere / off board    → cancel, piece snaps back
  └ pointer cancel              → cancel
secondary button down (mouse) → drawing
```

The board acts when a press starts, as chess sites do, so nothing waits for the finger to lift. Pressing a movable piece selects it; pressing a legal destination makes the move; pressing another movable piece switches the selection; pressing anything else clears it. Pressing the already-selected piece deselects it on release, unless the press became a drag. The same tap tolerance (`kTouchSlop`) is used for every pointer kind, because the mouse's precise slop would turn a slightly jittery click into a drag. A second finger cancels the press. These rules follow R2 exactly and live in `BoardInteraction`, apart from the widget, so they are tested directly. The legal move list for each square is built once per position from `engine.moves({'verbose': true})` and cached, keyed by FEN (R14).

A user can move when all of these hold:

- the board is not read-only
- the game is not over
- the controller is live (or branching is enabled)
- the piece's color is in `interactiveSide`
- the piece's color is the side to move, or premoves are on and it isn't

**Drag visuals:**

- The floating piece is drawn at `min(1.15, 1 + 4 / squareSize * 2)` scale, so it barely grows on small boards.
- On touch devices it is lifted by half a square, so its lower edge still overlaps the square under the finger. The drop target is the square under the finger, as on every chess app; targeting the drawn piece would make the back rank unreachable on phones.
- The cursor is `SystemMouseCursors.grabbing` while dragging and `grab` while hovering over a movable piece.

**Promotion:**

- A pawn move to the last rank sets `pendingPromotion`. The overlay shows four pieces in a column starting at the promotion square, toward the board's center, in the board's orientation.
- Tapping outside, pressing Escape, or pressing Back (through `PopScope`) cancels it.
- With `autoQueen`, the overlay is skipped.
- `promotionPickerBuilder(context, color, onSelect, onCancel)` replaces the default overlay.

**Castling:** a king move of two files, or onto a friendly rook, is mapped to the engine's castling move when one is legal. `BoardInteraction.resolveTarget` does the mapping for taps, drops and (later) keyboard and premove input. When the king is selected, a legal castle wins over switching the selection to the rook. Chess960 follow-up: return the `BoardMove` rather than a square, because there the castling square can be an ordinary king move or the king's own square.

### 5.5 Premoves

- Allowed when `enablePremoves` is on, `interactiveSide` is a single color, and that color is not to move.
- Premove destinations are a relaxed pseudo-legal set: the move is computed on a copy of the engine with the turn flipped, so it ignores whose turn it is but keeps piece movement geometry.
- One premove is stored and painted with `theme.premoveColor`. Tapping anywhere that is not a valid premove destination cancels it.
- On `MoveApplied(source: code)`, after the animation is scheduled, the board calls `controller.move(...)` with the premove. If it is illegal, the premove is discarded silently.

### 5.6 User annotations

- Drawing works with the secondary mouse button, or with a long press of about 400 ms on touch. Dragging draws an arrow; releasing on the starting square toggles a circle.
- Modifier keys pick the color: none is green, Shift is red, Alt is blue, and Shift+Alt is yellow. All four colors come from the theme.
- Drawing an existing arrow or circle again removes it.
- The board reports changes through the callbacks. If `clearUserAnnotationsOnMove` is true, user annotations are cleared on every `MoveApplied`.

### 5.7 Animation (`move_animator.dart`)

- One `AnimationController` drives every piece in flight.
- On `MoveApplied(source: code)` or a tap-made user move, the animator is given a move plan (the moving pieces plus fading captured pieces). Castling yields two moving pieces: king and rook.
- Drag moves produce an empty plan.
- On `NavigatedTo`, the plan is computed by diffing the piece maps of the two positions. Diffs that look like single moves animate; anything else snaps into place.
- A new change arriving mid-animation calls `controller.value = 1`, commits the current plan, then starts the next one.
- Pieces in flight are excluded from `PiecesLayer`, so a piece never shows up twice (R4).
- The effective duration is `MediaQuery.disableAnimations ? zero : animationDuration`. Zero skips the animator entirely.
- A flip animation uses its own controller with the same duration rules.

### 5.8 Hint arrow

The widget state holds `_activeHint`. On `didUpdateWidget`:

- a different `hint` replaces the active one and restarts `hintTimeout`
- a null `hint` clears it

On any `MoveApplied`, `_activeHint` is cleared. The cleared hint is remembered by identity, so the same value passed in again isn't shown again until the app sets a new one. The hint never touches `arrows` (R5).

### 5.9 Controller swap

In `didUpdateWidget`, when `oldWidget.controller != widget.controller`, the board:

- removes the old listener and adds the new one
- clears selection, drag, premove, pending promotion and user annotations
- finishes the animation and clears the hint
- rebuilds from the new FEN

### 5.10 Keyboard

- Keyboard handling is a `Focus` with `onKeyEvent`, enabled when `enableKeyboard` is on and the platform is desktop or web. A focus ring is painted in the highlight layer.
- Arrow keys move the focus cursor, flipped for black orientation. Enter and Space act like a tap on the focused square. Escape clears the selection.
- While the board is in navigation mode (toggled with `N`, or whenever it is read-only), left and right arrows call `controller.back()` and `controller.forward()`.
- Typing a SAN string followed by Enter calls `moveSan`.

## 6. Theming (`src/theme`)

`ChessBoardTheme` is `@immutable` and holds every color in R7, plus hover, premove, focus, app arrow and mark defaults, the four user-annotation colors, the outside-label margin and its labels, and the promotion picker background and scrim. It provides value `==` and `hashCode`, `copyWith`, and `lerp` for animated theme changes.

Optional colors (`checkColor`, `labelColor`) are cleared through sentinel flags:

```dart
theme.copyWith(clearCheckColor: true)
```

This is explicit and avoids the ambiguity of a nullable-of-nullable parameter.

Presets: `green` (the default), `brown`, `blue`, `purple`, `monochrome`. Each one gets a golden test, plus legibility tests on both square colors, using two measures. Small marks (legal dots, drag frame, focus ring) need a luminance contrast of at least 1.6. Whole-square tints and arrows are measured by perceptual distance (CIE76 delta E), because a hue shift such as yellow over cream is visible even at low luminance contrast: at least 15 for tints, 25 for arrows, and 12 between any two highlight tints so they never look alike. Automatic labels need contrast 3 and keep the opposite square's tone where possible. The purple preset uses a teal hint arrow, because blue blends into its violet dark squares.

`resolveTheme(widget)` applies the shortcut parameters on top of the theme. Theme changes only repaint the layers; ephemeral state is untouched (R7).

## 7. Piece sets (`src/pieces`)

```dart
abstract class PieceSet {
  Widget build(BuildContext context, Piece piece, double size);
  Future<void> precache(BuildContext context);
  static const PieceSet standard = PieceSet.svgAssets(
      'assets/pieces/default', package: 'modern_chess_board');
  const factory PieceSet.svgAssets(String directory, {String? package});
  factory PieceSet.images(Map<Piece, ImageProvider> images);
  const factory PieceSet.builder(PieceWidgetBuilder builder,
      {Object? id, Future<void> Function(BuildContext)? precache});
}

class ChessPieceView extends StatelessWidget { /* piece + label */ }
```

This replaces an earlier `fromMap(Map<Piece, Widget Function(double)>)` plan. Widget closures could neither be precached nor compared by value, while these three constructors can.

- `svgAssets` covers the common case of a folder of piece files. A trailing `/` on the directory is ignored for both paths and equality.
- `images` checks the map when it is built. An incomplete map throws an `ArgumentError` naming the missing codes, for example "missing: wQ, bN".
- Equality: SVG sets compare by directory and package, image sets by their providers, and builder sets by `id`, falling back to identity. The standard set is a const singleton.
- Precaching SVG sets: `precache` decodes all 12 SVGs with `vg.loadPicture` into a shared cache. The cache lives for the whole app; it is 12 small pictures per set. If one piece fails, the whole set fails, and the set can be retried later.
  - After that, `build` paints the decoded picture directly. It scales the whole picture by one factor, centres it like `BoxFit.contain`, and stays inside the `size` it is given.
  - Before precaching finishes, `build` falls back to `SvgPicture.asset`.
  - Because pictures are shared by every board, custom SVGs must not depend on `<text>` or `currentColor`.
- Precaching image sets uses `precacheImage`, and builder sets run an optional hook.
- When the board precaches: in `didChangeDependencies` and whenever `pieceSet` changes. Until the new set is ready, the board keeps showing the previous one, so pieces don't flicker (R8).
- Semantics: `ChessPieceView` labels the piece, for example "white king". The board passes `excludeFromSemantics: true`, because each square's own label already names its piece ("e4, white pawn"), so nothing is read twice (R11).

**The provided SVGs:**

- They are 100x100, about 105 KB in total, and use only paths, linear and radial gradients, and clip paths.
- They are copied unchanged into `assets/pieces/default/`. Gradient IDs are already unique per piece (prefixed with `wK-` and so on), so no conflicts arise.
- The `<title>` and `aria-label` attributes are ignored by `flutter_svg`; semantics come from the widget.
- They are the package author's own work and ship under the package's MIT license.

## 8. Labels

- `inside`: file letters on the bottom row, rank numbers on the left column, in the corners of the edge squares.
- `outside`: labels centered in the margins, on the bottom and left only.
- `none`: no labels and zero margin.

All three modes go through `BoardGeometry`, so they follow orientation.

## 9. Sound and haptics

```dart
abstract class ChessSoundPack { FutureOr<void> play(SoundEvent event); }
class SilentSoundPack extends ChessSoundPack { ... }  // default
// ChessSoundPack.callback((event) => ...) for quick setups.
```

`SafeSoundDispatcher.dispatch(event)` behaves like this:

- It calls `pack.play` inside `try`. If the call returns a `Future`, it listens for its error. The call runs in the caller's zone, not a private error zone: Dart never passes errors between error zones, so a private zone would hang packs that await a player created earlier. Errors in work a pack starts without returning it go to the app's `PlatformDispatcher.onError`.
- Errors are reported through `FlutterError.reportError` with the library name `modern_chess_board`, and are never rethrown.
- Exactly one event is sent per successful move, triggered by `MoveApplied` with `silent == false`. `illegal` is sent for rejected user drops and taps on an illegal destination while a piece is selected.
- No event is sent for `PositionReplaced` or `NavigatedTo` (R10).

Haptics: `HapticFeedback.selectionClick()` on pickup and `lightImpact()` on drop, only when `enableHaptics` is on and the platform is Android or iOS.

## 10. Accessibility

- Each square is `Semantics(label: 'e4, white pawn', button: true, selected: isSelected, hint: isLegalTarget ? 'legal move' : null, onTap: ...)`, built in a separate semantics-only grid. That grid sits under the visual layers and is excluded from painting, so it is cheap.
- Activating a square runs the same tap logic, so screen-reader users can move pieces (R11).
- After each `MoveApplied`, the board calls `SemanticsService.announce(moveAnnouncer(move, drawReason), textDirection)`. `moveAnnouncer` is a widget parameter, `String Function(BoardMove, DrawReason?)`, that defaults to `describeMove`, so apps can localize announcements.
- Label text uses `MediaQuery.textScalerOf(context)`, clamped so that labels never overflow the square or margin.

## 11. Performance notes

- Legal moves are cached per FEN.
- Layers use `RepaintBoundary`. Painters implement `shouldRepaint` by value comparison.
- Pieces are keyed widgets inside a single `Stack`. The drag and animation layers are updated through `ValueListenableBuilder`, not `setState` on the whole board.
- Profile-mode frame checks are done manually in the example app on Android (see tasks).

## 12. Testing strategy

| Kind | Tooling | Covers |
|---|---|---|
| Unit | `flutter_test` | Square parsing, classifier priority table, controller actions, history and branching, notify flags, theme equality/copyWith/contrast, piece set validation, notation text, safe sound dispatch |
| Widget | `flutter_test` with `tester.startGesture`, `sendKeyEvent`, `pumpAndSettle` | Tap/drag flows, threshold, cancel, promotion, interactive side, game-over lock, highlights, animations (frame-by-frame piece counts), arrows/hint dismissal (including the fake-async timeout), labels at 120 px, controller swap, keyboard, premoves, annotations, semantics labels and announcements |
| Property | `glados` | Random legal games played through both the controller and widget taps, where the rendered piece map must equal the FEN after each move; random history navigation equals a replay; the classifier always returns exactly one event; random `Square.tryParse` input never throws |
| Golden | `matchesGoldenFile` | 5 themes x 3 label modes, plus a mid-game position with arrows, hint, marks and highlights. Goldens are generated on one platform (Windows) and tagged `golden`, so CI on other OSes can skip them. |

Rebuild counting: a test-only `debugBuildCount` hook (stripped by `assert`) verifies that an idle tap triggers no rebuild.

## 13. Open questions

1. **SVG license.** Resolved: the pieces in `svg/` were created by the package author (AI-assisted) and ship under the package's MIT license.
2. **Package name and repository URL** for the pubspec (`homepage`, `repository`, `issue_tracker`). I'm assuming `modern_chess_board`, with the URLs left as placeholders until you provide them.
