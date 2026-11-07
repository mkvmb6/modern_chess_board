/// The state of the game in the current position.
enum GameStatus {
  /// The game continues.
  ongoing,

  /// The side to move is checkmated.
  checkmate,

  /// The side to move has no legal moves and is not in check.
  stalemate,

  /// The game is drawn by rule. See [DrawReason].
  draw;

  /// Whether no more moves can be played.
  bool get isGameOver => this != ongoing;

  /// Whether the game ended in a draw. True for [stalemate] as well as
  /// [draw], since stalemate is a draw.
  bool get isDraw => this == stalemate || this == draw;
}

/// Why a game ended in a draw.
///
/// When the game status is [GameStatus.stalemate], the draw reason is
/// [DrawReason.stalemate].
enum DrawReason {
  /// The side to move has no legal moves and is not in check.
  stalemate,

  /// Fifty moves by each side without a capture or pawn move.
  fiftyMoveRule,

  /// The same position occurred three times.
  threefoldRepetition,

  /// Neither side has enough material to checkmate.
  insufficientMaterial,
}

/// The outcome of a game.
enum GameResult {
  /// White won.
  whiteWins('1-0'),

  /// Black won.
  blackWins('0-1'),

  /// The game was drawn.
  draw('1/2-1/2'),

  /// The game is not over.
  ongoing('*');

  const GameResult(this.pgn);

  /// The PGN result token.
  final String pgn;
}

/// A sound the board asks the app to play.
///
/// Each successful move produces exactly one event, chosen in this priority
/// order: [gameEnd], [promotion], [castle], [check], [capture], [move].
enum SoundEvent {
  /// A quiet move.
  move,

  /// A capture, including en passant.
  capture,

  /// A move that gives check.
  check,

  /// A castling move.
  castle,

  /// A pawn promotion.
  promotion,

  /// A move that ends the game (mate or draw).
  gameEnd,

  /// The user tried an illegal move.
  illegal,
}
