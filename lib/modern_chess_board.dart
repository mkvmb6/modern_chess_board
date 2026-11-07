/// An interactive, customizable chess board widget.
///
/// Import this library to get everything needed to show a board and drive
/// it from a controller:
///
/// ```dart
/// import 'package:modern_chess_board/modern_chess_board.dart';
/// ```
///
/// The underlying rules engine, `package:chess`, also defines `Piece`,
/// `PieceType`, `Color` and `Move`. If you use the engine directly through
/// the controller, import it with a prefix to avoid name clashes:
///
/// ```dart
/// import 'package:chess/chess.dart' as chess;
/// ```
library;

export 'src/controller/board_change.dart'
    show BoardChange, MoveApplied, MoveSource, NavigatedTo, PositionReplaced;
export 'src/controller/chess_board_controller.dart'
    show ChessBoardController, kInitialFen;
export 'src/model/annotations.dart' show Arrow, MarkShape, SquareMark;
export 'src/model/board_move.dart' show BoardMove, CastleSide;
export 'src/model/game_status.dart'
    show DrawReason, GameResult, GameStatus, SoundEvent;
export 'src/model/piece.dart' show Piece, PieceColor, PieceType;
export 'src/model/square.dart' show Square;
export 'src/pieces/piece_set.dart'
    show ChessPieceView, PieceSet, PieceWidgetBuilder;
export 'src/sound/chess_sound_pack.dart' show ChessSoundPack, SilentSoundPack;
export 'src/theme/chess_board_theme.dart'
    show AnnotationColors, ChessBoardTheme;
