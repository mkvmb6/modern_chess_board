# Build a Flutter chess board package (greenfield)

Create a new, publishable Flutter package that provides an interactive, customizable chess board widget. It must support Android, iOS, web, Windows, macOS and Linux. Chess rules (move legality, check, mate, draws, FEN, PGN) may come from an established Dart chess rules library rather than being written from scratch.

You own the architecture, file layout, naming and implementation approach. The requirements below describe behavior and capabilities, not design.

## 1. Board widget

- Renders a standard 8x8 chess board with pieces for the current position.
- Always stays square and sizes itself to the smaller of the available width and height. Works inside unbounded constraints (e.g. a `Column` or scroll view) without throwing, by falling back to a sensible size.
- Configurable orientation: white at the bottom or black at the bottom. Everything (pieces, labels, highlights, arrows, drag indicators, animations) must follow the orientation.
- Changing orientation at runtime animates the flip (respecting the animation duration in section 4).
- Optional starting position supplied as a FEN string, applied only when the board first appears. Changing it later has no effect; use the controller instead. An invalid FEN fails with a clear error, not a crash deep in rendering.
- Read-only mode: users cannot move pieces in any way (no tap selection, no drag, no promotion dialog). Code can still move pieces through the controller, and those moves still animate.
- Interactive side: the app can restrict user interaction to white only, black only, or both (default both). Useful for playing against an engine or online opponent.
- Once the game is over, users cannot make further moves.

## 2. Moving pieces

1. **Tap to move:**
   - Tapping a piece of the side to move selects it.
   - Tapping a legal destination makes the move.
   - Tapping the selected piece again deselects it.
   - Tapping a different piece of the side to move switches the selection.
   - Tapping an illegal destination (empty square or opponent piece) clears the selection without moving.
   - Tapping an empty square or an opponent piece with nothing selected does nothing and must not cause unnecessary rebuilds.
2. **Drag and drop:** drag a piece of the side to move to a destination square. Illegal drops, drops off the board and cancelled drags are rejected and the piece returns to its square.
   - Small pointer movement under a drag threshold counts as a tap, not a drag.
   - Dragging a piece also selects it, so legal-destination markers show during the drag.
   - Starting a drag on a different piece replaces any existing tap selection.

Only legal moves are ever accepted. Legality must come from the rules engine's move generation, not from string matching on move notation.

**Castling:** the user can castle by moving the king two squares. Moving the king onto its own rook also castles (needed for Chess960 later).

**Pawn promotion:** when a pawn reaches the last rank, the user picks queen, rook, bishop or knight before the move completes.

- The picker appears over the promotion square, in the promoting side's piece set, and follows orientation.
- Dismissing the picker (tap outside, back button, Escape) cancels the move and leaves the position unchanged.
- Optional auto-queen setting that skips the picker.
- Apps can supply their own picker widget.

**Callbacks:** the widget reports every successful user move to the app (from, to, promotion, SAN; the resulting FEN is readable from the controller when the callback runs) and reports game end (status, result and draw reason). Moves made through the controller are not reported as user moves.

## 3. Visual feedback

- **Selection:** the selected piece's square is highlighted.
- **Legal destinations:** while a piece is selected, show a small dot on each empty legal square and a ring on each square where it can capture. En passant targets show as captures.
- **Last move:** highlight the from and to squares of the most recent move. On by default, can be turned off. Must not double-tint a square that is also selected.
- **Check and mate:**
  - Highlight the king of the side that has been checkmated.
  - Optionally highlight a king that is in check. Off by default; enabled by giving it a color.
- **Hover (desktop and web):** the square under the mouse shows a subtle highlight when it is a legal destination for the selected piece, and the cursor shows a "grab" state over movable pieces.
- **Drag feedback:**
  - The dragged piece appears slightly enlarged, but never so much that it overflows a square noticeably on small boards.
  - On touch devices, the dragged piece is lifted above the finger so it stays visible.
  - The original square is empty while dragging.
  - The square under the pointer shows a clear "legal" indicator if the piece can move there, and a distinct "illegal" tint if it cannot. The source square shows neither.
  - All drag indicators clear when the drag ends or is cancelled.
  - None of these indicators appear in read-only mode.
  - On desktop, the cursor shows a grabbing state while dragging.

## 4. Move animation

- Moves made by tapping, or from code through the controller, animate smoothly from the origin square to the destination square.
- Castling animates both king and rook. Captured pieces fade out rather than vanishing.
- Drag-and-drop moves do not animate, because the user has already "moved" the piece.
- The animation duration is configurable, with a short default (around 150ms). A duration of zero turns animation off.
- When the platform requests reduced motion, animations are turned off.
- The moving piece must never appear twice (at the origin and in flight) during the animation.
- A new move arriving mid-animation finishes the current animation immediately and starts the next one. The board never shows a stale position.

## 5. Arrows and square marks

- **Annotation arrows:** the app can supply a list of arrows, each from one square to another, with an optional color per arrow (a translucent default color). Arrows are drawn on top of the board, must not block touches, and must redraw correctly when the list or orientation changes.
- **Square marks:** the app can supply circled or tinted squares with optional colors, following the same rules as annotation arrows.
- **Hint arrow:** the app can supply a single suggestion arrow (e.g. from an engine).
  - It must look clearly different from annotation arrows: different default color, and a different line and arrowhead style.
  - It disappears automatically on the next successful move, whether made by the user or from code.
  - It disappears when the app clears it, and a new hint replaces the old one.
  - It optionally disappears after a given duration, even if no move is made.
  - It never changes the app's annotation arrow list.
- **User-drawn annotations:** users draw arrows by right-click-dragging (desktop) or long-press-dragging (touch), and circle a square by right-clicking or long-pressing it. Drawing the same arrow or circle again removes it. Modifier keys pick colors. The board reports changes to the app, and user drawings clear on the next move unless the app opts out.
- Bad square names in arrows or marks must not crash the board; they are ignored and logged in debug builds.

## 6. Controller

Provide a controller object that owns the game state and that the app uses to read and change it. The board must update itself automatically when the controller changes, without the app wiring up listeners.

**Read access:**

- Current FEN
- Side to move
- In check, checkmate, stalemate, draw (fifty-move, threefold repetition, insufficient material), and game over, with the reason
- Move history (SAN and from/to for each move)
- PGN, including headers the app can set
- Number of half-moves played
- Legal moves for a given square

**Actions:**

- Make a move (from, to, optional promotion piece). Returns whether it was legal and applied.
- Make a move from SAN (e.g. "Nf3"), validated through the rules engine.
- Undo the last move. Does nothing if there are no moves.
- Reset to the starting position.
- Load a position from FEN. Invalid FEN returns failure and leaves the current game unchanged.
- Load a game from PGN.

**History navigation:** the app can step backward and forward through played moves, or jump to any move, without losing the moves after it. While viewing an earlier position, the board shows that position with its last-move highlight, user moves are disabled (or optionally branch the game, by app choice), and navigation animates like a normal move.

**Other requirements:**

- Every action has an option to skip notifying the board, so apps can batch several changes and notify once.
- The underlying rules engine stays reachable for advanced use.
- If the app swaps in a different controller, the board clears any selection, running animation, hint and user drawings, and shows the new game.
- The controller is usable without a widget (e.g. in pure Dart tests).

## 7. Theming

- One theme object holds every color the board paints:
  - Light and dark squares
  - Selection
  - Last-move highlight
  - Legal-destination markers
  - Hover highlight
  - Coordinate labels
  - Checkmate tint and optional check tint
  - Annotation arrow default and hint arrow
  - Drag legal and illegal indicators
- Ship at least five presets: classic green (the default), brown/wood, blue, purple and monochrome. Every preset keeps legal markers, highlights and labels visible against both square colors.
- Themes are immutable, comparable by value, and support "copy with changes", including setting optional colors back to unset.
- Also offer simple per-color shortcut parameters on the widget for light squares, dark squares and the checkmate tint. When provided, they override the theme.
- If no label color is set, labels use a color that contrasts with the square they sit on.
- Changing the theme at runtime does not reset selection, drag or animation state.

## 8. Piece sets

- Ship a default set of 12 piece images (6 types x 2 colors) inside the package. Prefer vector assets so pieces stay sharp at any board size and pixel density. Assets must have a license compatible with publishing.
- Apps can supply their own piece set, either by giving a map of all 12 images or by providing a builder function. An incomplete map must fail with a clear error naming the missing pieces.
- Piece sets are comparable by value.
- Piece images are preloaded so pieces don't flicker in on first display or after the set changes.

## 9. Coordinate labels

Three modes:

- **Inside (default):** rank and file labels drawn inside the edge squares.
- **Outside:** labels drawn in margins around the board. The playing area stays square, and the whole widget (board plus margins) still fits the available space.
- **None:** no labels and no margin.

Labels follow orientation and stay readable on very small boards (minimum font size of about 9px).

## 10. Sound hook

- The package ships no audio and does not depend on an audio plugin. The app supplies an object that receives a sound event and plays whatever it likes.
- Each successful move sends exactly one event, picked in this priority order: game end > promotion > castling > check > capture > normal move. En passant counts as a capture.
- Illegal drop or move attempts by the user send a distinct "illegal" event.
- No events are sent for undo, reset, FEN load, history navigation, or actions where notification was skipped.
- The default plays nothing.
- Errors from the app's sound code, whether thrown immediately or later (async), are caught and logged and never break the board.
- **Haptics:** optional light haptic feedback on piece pickup and drop on mobile, off by default.

## 11. Accessibility

- Every square exposes a screen-reader label with its name and contents (e.g. "e4, white pawn" or "e4, empty").
- Pieces expose descriptive labels.
- Selected and legal-destination states are exposed to screen readers (e.g. "e4, empty, legal move").
- Screen readers can make moves with the standard activate gesture, using the same tap-to-move flow.
- After each move, the board announces it in words (e.g. "White knight to f3, check").
- Text and labels respect the platform text scale without breaking the layout.
- **Keyboard play:** on desktop and web, the board is focusable, arrow keys move a focus cursor across squares, Enter/Space selects and moves, Escape clears selection, and left/right arrows navigate history when the board is not in move-entry focus. Typing a move in SAN is an optional extra.

## 12. Premoves

- When the interactive side is restricted to one color, the user can queue a move while it is the opponent's turn, by tap or drag.
- A queued premove is shown with its own highlight color (in the theme) and can be cancelled by tapping anywhere off a legal premove destination.
- When the opponent's move arrives, the premove is played immediately if it is legal, otherwise it is silently discarded.
- Premoves are off by default.

## 13. Compatibility and API hygiene

- Expose a single public import that includes everything apps need, and keep internals private.
- All options have sensible defaults, so the simplest usage needs only a controller.
- Public API is documented with dartdoc, and `dart pub publish --dry-run` passes with no warnings.
- State the minimum supported Flutter and Dart SDK versions in the pubspec.

## 14. Performance

- Selecting, hovering, dragging and animating must not rebuild every square; only the affected layers repaint.
- Drag and animation stay smooth (no dropped frames in profile mode on a mid-range device) at any board size.
- Legal moves are computed once per position, not per frame.

## 15. Deliverables

- The package, with pubspec metadata (description, homepage, repository, issue tracker, topics, platforms), a license, a README with usage examples for every feature and a screenshot or GIF, and a CHANGELOG.
- An example app that demonstrates every feature, including:
  - Switching themes
  - Switching piece sets
  - Switching label modes
  - A debug sound pack that logs events
  - Flip, undo, reset and load-FEN buttons
  - Arrows, square marks and a hint arrow
  - Read-only mode and interactive-side restriction
  - Move list and game-over status
  - History navigation (back, forward, jump to move) and PGN load
  - User-drawn arrows and circles
  - Premoves against a simple random-move opponent
  - Keyboard play, haptics toggle and animated flip
- Tests:
  - Unit, widget and property-based (randomized) tests covering every requirement above.
  - Specifically: move legality, tap and drag flows (including drag threshold and cancelled drags), promotion (including cancel and auto-queen), interactive-side and game-over lockout, highlights, check/mate tints, animation behavior (including interrupted animations and reduced motion), arrow, mark and hint behavior (all dismissal rules), theme presets and equality, piece set rendering and errors, all three label modes including narrow boards, sound classification and priority, no sound on undo/reset/load, error-safe sound handling (sync and async), accessibility labels and announcements, controller notification behavior, controller swap, history navigation (including disabled moves and branching), PGN load, user-drawn annotations (toggle, colors, clear on move), premoves (queue, cancel, play, discard), keyboard play, castling by king-onto-rook, haptics, and animated flip.
  - Property-based tests play random legal games and check that the board's position always matches the controller's FEN.
  - Golden tests for each theme preset and label mode.
- The code must pass `flutter analyze` with no issues and be formatted with `dart format`.

## Out of scope

Chess clocks, engine integration, online play, Chess960 setup, and variants. The API should not prevent apps from building these on top.
