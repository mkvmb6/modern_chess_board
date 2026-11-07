# Implementation tasks: modern_chess_board

Each task is written test-first: write the failing tests, implement, then run `flutter analyze`, `dart format --set-exit-if-changed .` and `flutter test` before ticking the box. `_Req_` refers to `requirements.md` sections; `_Design_` refers to `design.md` sections.

## Phase 0: Scaffold

- [x] 1. Create the package and tooling
  - `flutter create --template=package modern_chess_board` in place. Keep `requirements.md`, `design.md`, `tasks.md`, `svg/`.
  - Pin the dependencies: `chess: 0.8.1`, `flutter_svg: 2.3.2`; dev: `glados: 1.1.7`, `flutter_lints` (latest stable, pinned).
  - Set the SDK constraints, `platforms:` (all 6), `topics:`, `description`, and placeholder `homepage`/`repository`/`issue_tracker`.
  - Add `analysis_options.yaml` with `flutter_lints` plus `public_member_api_docs`.
  - Copy `svg/*.svg` to `assets/pieces/default/` and register it in `pubspec.yaml`.
  - Create `lib/modern_chess_board.dart` as the barrel file and the `src/` folders.
  - Add an `example/` app via `flutter create example`, depending on the package by path.
  - _Req 13, 15. Design 1, 2_

## Phase 1: Model and controller (pure Dart)

- [x] 2. Domain model
  - `Square` (parse, tryParse, constants, all), `PieceType`, `PieceColor`, `Piece`, `BoardMove`, `Arrow`, `SquareMark`, `GameStatus`, `DrawReason`, `GameResult`, `SoundEvent`.
  - Tests: value equality, `tryParse` rejects bad names ("z9", "", "e44", null-like input), property test that random strings never throw.
  - _Req 5, 6. Design 3_

- [x] 3. Controller core
  - Wrap `Chess`. Read API: `fen`, `turn`, check/mate/stalemate/draw with reason, `isGameOver`, `result`, `history`, `pgn`, `pgnHeaders`, `halfMoveCount`, `lastMove`, `legalMovesFrom`, `pieceAt`, `engine`.
  - `move()` matched against verbose move generation (from/to/promotion fields only). `moveSan()`, `undo()`, `reset()`, `loadFen()`, `loadPgn()`.
  - Invalid FEN or PGN returns `false` and leaves state unchanged.
  - The `notify` flag on every action. `lastChange` + `changeId` (`MoveApplied`, `PositionReplaced`, `NavigatedTo`, `silent`).
  - Tests: legal and illegal moves, promotion required and accepted, castling, en passant, each draw type, undo on empty history, notification counts with and without `notify`, batching then `notifyListeners()`.
  - _Req 6. Design 4.2, 4.3_

- [x] 4. History navigation and branching
  - `_line` + `_cursor`, `back`, `forward`, `goTo`, `goToStart`, `goToEnd`, `isViewingHistory`, `allowBranching`.
  - Tests: navigation keeps the line; move while viewing is rejected; branching cuts the line; `undo` only works live; property test that random navigation equals replaying the first N moves.
  - _Req 6. Design 4.1_

- [x] 5. Move classifier and notation
  - `classify()` with the priority game end > promotion > castle > check > capture > move, with en passant counted as capture.
  - `describeMove()` for spoken text. The board widget exposes a `moveAnnouncer` override for localization (task 26).
  - Tests: one known position per event, plus combined cases (promotion with capture and mate gives `gameEnd`; castling with check gives `castle`; en passant gives `capture`). Property test that every random legal move yields exactly one event.
  - _Req 10, 11. Design 4.4, 4.5_

## Phase 2: Theme, pieces, sound

- [x] 6. Theme
  - `ChessBoardTheme` with every color, `copyWith` with clear flags, `==`/`hashCode`, 5 presets.
  - Contrast helper used for automatic label color.
  - Tests: equality, copyWith round trip, clearing optional colors, each preset distinct, legibility on both square colors (contrast for small marks, perceptual distance for tints and arrows, pairwise tint distance), label tone, lerp.
  - _Req 7. Design 6_

- [x] 7. Piece sets
  - `PieceSet` (standard SVG, `svgAssets`, `images`, `builder`), `ChessPieceView`, equality, `precache()`.
  - Tests: incomplete image map throws and lists the missing codes; equality rules; the standard set precaches and renders all 12 SVGs; size and aspect ratio honored; semantics label and opt-out; failed loads retry.
  - _Req 8. Design 7_

- [x] 8. Sound dispatcher and haptics wrapper
  - `ChessSoundPack`, `SilentSoundPack`, `SafeSoundDispatcher`, `BoardHaptics`.
  - Tests: sync throw and async throw are both caught and reported through `FlutterError.onError`, and neither is rethrown; the silent pack does nothing.
  - _Req 10. Design 9_

## Phase 3: Static board

- [x] 9. Geometry and layout
  - `BoardGeometry` (square to offset and offset to square, both orientations, flip interpolation). `LayoutBuilder` sizing with an unbounded-constraint fallback.
  - Tests: round trip of all 64 squares in both orientations; widget is square under wide, tall and unbounded constraints.
  - _Req 1, 9. Design 5.2_

- [x] 10. Squares, pieces and labels layers
  - `ChessBoard` widget with defaults, `initialFen` applied once (invalid throws `ArgumentError`), `SquaresLayer`, `PiecesLayer`, `LabelsLayer` (inside, outside, none), theme shortcut parameters, piece preloading without flicker.
  - Tests: the start position renders 32 pieces in the right squares in both orientations; a later `initialFen` change is ignored; all three label modes at 400 px and 120 px with font size ≥ 9; outside mode fits the constraints; shortcut colors override the theme.
  - Golden tests: 5 themes x 3 label modes.
  - _Req 1, 7, 8, 9. Design 5.1, 5.3, 8_

- [x] 11. Controller listening and swap
  - Listen to the controller and rebuild on change. On swap, unhook the old controller and reset all ephemeral state.
  - Tests: `controller.move()` updates the board with no app wiring; swapping controllers shows the new game and listens only to it; a fresh swapped-in controller gets `initialFen`. Clearing selection, drag, promotion, animation, hint, drawings and premoves on a swap is tested in the tasks that add that state (12, 13, 14, 19, 20, 21, 22, 23), all through one `_resetEphemeralState()`.
  - _Req 6. Design 5.9_

## Phase 4: Interaction

- [x] 12. Pointer state machine and tap to move
  - Raw `Listener` state machine, selection notifier, legal-move cache per FEN, movability rules (read-only, game over, history view, interactive side, turn).
  - Tests: every tap rule in R2; tapping an empty square with nothing selected causes no rebuild (`debugBuildCount`); read-only, game over, history view and interactive side each block moves while code moves still work; a controller swap clears the selection.
  - _Req 1, 2. Design 5.4_

- [x] 13. Drag and drop
  - Drag threshold, floating piece (scale cap, touch lift), empty source square, drop legal/illegal/off board/cancel, grab and grabbing cursors. Claim the gesture arena once a press starts on a movable piece, so a board inside a scroll view never scrolls during a drag (raw `Listener` events never enter the arena).
  - Tests: a movement below the threshold counts as a tap; an illegal drop snaps back with the position unchanged; dragging replaces the tap selection; the source square is empty during the drag; scale ≤ 1.15 and overflow ≤ 4 px at 120 px board; cursor values from `MouseRegion`; a controller swap cancels an in-progress drag.
  - _Req 2, 3. Design 5.4_

- [x] 14. Promotion
  - Default overlay positioned and oriented, cancel paths (outside tap, Escape, back), `autoQueen`, `promotionPickerBuilder`.
  - Tests: the picker appears by tap and by drag; each of the 4 choices applies; each cancel path leaves the FEN unchanged; auto-queen skips the picker; the custom builder is used; a controller swap closes a pending picker.
  - _Req 2. Design 5.4_

- [x] 15. Castling input
  - King two squares, and king onto its own rook.
  - Tests: both inputs castle on both sides for both colors; the rook ends up on the right square.
  - _Req 2. Design 5.4_

- [x] 16. Callbacks
  - `onMove` for user moves only, `onGameEnd` once per game end.
  - Tests: code moves don't fire `onMove`; mate by tap fires `onGameEnd` once with the right result.
  - _Req 2_

## Phase 5: Visual feedback

- [x] 17. Highlight layer
  - Chess960 follow-up: take the castling rook square from the castling rights rather than the a/h file.
  - Selection, legal dots and rings (en passant as a ring), last move with the no-double-tint rule, `showLastMove`, checkmate tint, optional check tint, hover on desktop. While the king is selected, also ring its own rook when castling on that side is legal, so the king-onto-rook tap is visible beforehand.
  - Tests: painted colors per square checked through a test hook on the painter's input model; selection over the last move uses only the selection color; check tint is off by default and on when a color is given.
  - _Req 3. Design 5.3_

- [x] 18. Drag feedback layer
  - Legal/illegal tint under the pointer, none on the source square, cleared on end or cancel, hidden when read-only. Judge legality with `BoardInteraction.resolveTarget`, so dragging the king over its own rook shows the castling square as legal.
  - Tests: each of those four rules.
  - _Req 3_

## Phase 6: Animation

- [x] 19. Move animator
  - Plans for tap and code moves, castling (king + rook), captured piece fade, no plan for drags, interrupt-and-commit, `disableAnimations`, zero duration.
  - Tests: frame by frame at 0/50/100% the moving piece appears exactly once; a drag move has no in-flight piece; a second move mid-flight ends at the right final FEN; zero duration and reduced motion settle in one pump; a controller swap ends a running animation.
  - _Req 4. Design 5.7_

- [ ] 20. Flip animation and history-navigation animation
  - Animated orientation change; navigation diffs animate single moves and snap other changes.
  - Tests: midway through a flip, positions are interpolated and the final state matches the black orientation; `back()` animates the reverse of the last move; a controller swap ends a flip or history animation.
  - _Req 1, 6. Design 5.2, 5.7_

## Phase 7: Arrows and annotations

- [ ] 21. App arrows, marks and hint
  - Arrows layer under `IgnorePointer`, distinct hint style, hint lifecycle (cleared on move by user or code, cleared when the app sets null, replaced by a new hint, timeout), bad squares ignored.
  - Tests: taps go through arrows; arrows redraw after a list change and after a flip; each hint dismissal rule (timeout via `tester.pump(duration)`); `arrows` is never changed by the board; `Arrow('z9','e4')` doesn't crash; a controller swap clears the hint.
  - _Req 5. Design 5.8_

- [ ] 22. User-drawn annotations
  - Right-click and long-press drawing, circle toggle, modifier colors, callbacks, clear on move with an opt-out.
  - Tests: draw arrow, draw again removes it; circle toggle; Shift gives the red color; long press on touch; cleared after a move unless opted out; disabled when `enableUserAnnotations` is false; a controller swap clears user drawings.
  - _Req 5. Design 5.6_

## Phase 8: Advanced input

- [ ] 23. Premoves
  - A premove reports `onMove` when it is played, not when it is queued.
  - Queue by tap or drag on the opponent's turn, premove highlight, cancel, auto-play on the opponent's move, silent discard if illegal. Split `BoardInteraction.canMove` into a selectable check (no turn check when premoves are on) and a can-move-now check, with premove destinations as a second source of targets. Premove destinations also resolve king-onto-rook to castling.
  - Tests: queue, cancel, play when legal, discard when illegal, unavailable when `interactiveSide` is both or premoves are off; a controller swap drops a queued premove.
  - _Req 12. Design 5.5_

- [ ] 24. Keyboard play
  - Focus, focus cursor (orientation-aware), Enter/Space, Escape, navigation mode with left/right, SAN entry. Enter/Space go through `BoardInteraction.tap`, so they use the same rules and `resolveTarget` as pointer input.
  - Tests: `sendKeyEvent` sequences that play e2e4; Escape clears; left arrow in navigation mode calls `back()`; typing `Nf3` plus Enter moves.
  - _Req 11. Design 5.10_

## Phase 9: Sound, haptics, accessibility wiring

- [ ] 25. Wire sound and haptics into the board
  - One event per successful move, `illegal` on rejected input, none on undo, reset, load, navigation or silent changes; haptics on pickup and drop.
  - Tests: a recording sound pack checks the event sequence across a scripted game; a throwing pack doesn't break play; haptics calls captured through the `SystemChannels.platform` mock.
  - _Req 10. Design 9_

- [ ] 26. Semantics
  - Semantics grid with labels, selected state, legal hint, activate-to-move, announcements, text scaling. Activation goes through `BoardInteraction.tap`, the same rules as pointer presses; the full-board gesture `Listener` does not handle screen-reader taps.
  - Tests: `find.bySemanticsLabel('e4, white pawn')` after 1.e4; `tester.semantics.tap` plays a move; announcement captured through the `SystemChannels.accessibility` mock; text scale 2.0 keeps labels inside their squares.
  - _Req 11. Design 10_

## Phase 10: Hardening

- [ ] 27. Property-based end-to-end tests
  - Random legal games played through widget taps and drags in random orientations; after each move, the rendered piece map equals the controller FEN.
  - _Req 15. Design 12_

- [ ] 28. Performance pass
  - Check `RepaintBoundary` placement and `shouldRepaint`; run the example in profile mode on an Android device and record frame times for drag and animation.
  - _Req 14. Design 11_

## Phase 11: Deliverables

- [ ] 29. Example app
  - Theme, piece set and label switchers; debug sound pack logging events; flip, undo, reset and load-FEN buttons; arrows, marks and hint demo (with timeout); read-only and interactive-side toggles; move list with history navigation and PGN load; user annotations; premoves against a random-move opponent; keyboard play; haptics toggle; game-over status.
  - Smoke widget test for the example.
  - _Req 15_

- [ ] 30. Docs and publishing checks
  - README with usage examples for every feature and a screenshot/GIF; CHANGELOG `0.1.0`; LICENSE (MIT unless you choose otherwise) plus the asset license note; dartdoc on all public API.
  - Final gate: `flutter analyze` clean, `dart format --set-exit-if-changed .`, `flutter test`, `dart pub publish --dry-run` with no warnings.
  - _Req 13, 15_
