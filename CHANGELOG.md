## 0.1.0

First release.

- `ChessBoard` widget with legal-move rules, tap and drag input, castling by moving the king onto its rook, and a promotion picker (or auto-queen, or your own picker).
- `ChessBoardController` for the game: moves in SAN or by square, undo, reset, FEN and PGN load and export, history navigation with optional branching, game status and draw reasons.
- Animated moves, history steps and board flips, all following the platform's reduced-motion setting.
- Highlights for the last move, selection, legal targets, check and checkmate; drag feedback for legal and illegal drops.
- App arrows, square marks and a hint arrow; user-drawn arrows and circles with modifier colors.
- Premoves when playing one side.
- Keyboard play: focus cursor, typed moves, and history navigation.
- Screen-reader support: a label for every square, activate-to-move, and spoken move announcements you can localize.
- Five themes and a full `ChessBoardTheme` for your own; SVG, image or builder piece sets, with original artwork bundled.
- A sound hook that sends one event per move (the package ships no audio) and optional haptics on Android and iOS phones and tablets.
