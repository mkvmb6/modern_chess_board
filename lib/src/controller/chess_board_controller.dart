import 'package:chess/chess.dart' as ch;
import 'package:flutter/foundation.dart';

import '../model/board_move.dart';
import '../model/game_status.dart';
import '../model/piece.dart';
import '../model/square.dart';
import 'board_change.dart';

/// The standard starting position.
const String kInitialFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Owns the game state for a chess board.
///
/// Give the same controller to a `ChessBoard` widget and the board updates
/// itself whenever the controller changes. Every action takes a `notify`
/// flag; pass `notify: false` to batch several changes, then call
/// [notifyListeners] once.
///
/// ```dart
/// final controller = ChessBoardController();
/// controller.move(Square.e2, Square.e4);
/// controller.moveSan('e5');
/// print(controller.fen);
/// ```
class ChessBoardController extends ChangeNotifier {
  /// Creates a controller at [fen], or the standard starting position.
  ///
  /// Throws an [ArgumentError] if [fen] is not a valid, legal position.
  /// See [loadFen] for what counts as legal.
  ///
  /// See [allowBranching] for what happens when a move is made while an
  /// earlier position is shown.
  ChessBoardController({String? fen, bool allowBranching = false})
    : _engine = ch.Chess(),
      _allowBranching = allowBranching {
    if (fen == null) {
      _resetState(kInitialFen);
    } else if (!_load(fen)) {
      throw ArgumentError.value(fen, 'fen', 'Not a valid chess position');
    }
  }

  /// Whether a move made while an earlier position is shown starts a new
  /// branch, discarding the moves after it.
  ///
  /// When false (the default), such moves are rejected: the user has to
  /// return to the latest position first. Changing this notifies listeners,
  /// because it changes whether the board accepts moves.
  bool get allowBranching => _allowBranching;
  set allowBranching(bool value) {
    if (value == _allowBranching) return;
    _allowBranching = value;
    notifyListeners();
  }

  bool _allowBranching;

  ch.Chess _engine;
  String _startFen = kInitialFen;

  // The full game. `_rawLine[i]` is the engine's form of `_line[i]`, kept so
  // navigating forward can replay it. `_positionKeys[i]` identifies the
  // position after `i` moves, so it is one longer than `_line`.
  final List<BoardMove> _line = [];
  final List<ch.Move> _rawLine = [];
  final List<String> _positionKeys = [];

  // Number of moves applied to `_engine`, from 0 to `_line.length`.
  int _cursor = 0;
  final Map<String, String> _headers = {};
  BoardChange _lastChange = const PositionReplaced(silent: true);
  int _changeId = 0;
  _PositionCache? _cache;

  // ---------------------------------------------------------------------
  // Read access
  // ---------------------------------------------------------------------

  /// The underlying rules engine from `package:chess`, for advanced use
  /// such as analysis.
  ///
  /// Treat it as read-only. The controller caches facts about each
  /// position, so changing the engine directly leaves the controller out of
  /// date. If you must change it, call `loadFen(engine.fen)` afterwards to
  /// resync; that starts a new game from the engine's position.
  ch.Chess get engine => _engine;

  /// FEN of the current position.
  String get fen => _position.fen;

  /// FEN of the position the current game started from.
  String get startingFen => _startFen;

  /// The side to move.
  PieceColor get turn => _position.turn;

  /// Whether the side to move is in check (including checkmate).
  bool get isCheck => _position.inCheck;

  /// Whether the side to move is checkmated.
  bool get isCheckmate => status == GameStatus.checkmate;

  /// Whether the side to move is stalemated.
  bool get isStalemate => status == GameStatus.stalemate;

  /// Whether the game is drawn by any rule, including stalemate.
  bool get isDraw => status.isDraw;

  /// Why the game is drawn, or null if it is not.
  ///
  /// Checkmate takes precedence: a mate that also reaches the fifty-move
  /// limit is a win, not a draw.
  DrawReason? get drawReason => _position.drawReason;

  /// Whether no more moves can be played.
  bool get isGameOver => status.isGameOver;

  /// The state of the game in the current position.
  GameStatus get status => _position.status;

  /// The result of the game, or [GameResult.ongoing].
  GameResult get result => switch (status) {
    GameStatus.ongoing => GameResult.ongoing,
    GameStatus.checkmate =>
      turn == PieceColor.white ? GameResult.blackWins : GameResult.whiteWins,
    GameStatus.stalemate || GameStatus.draw => GameResult.draw,
  };

  /// The moves leading to the position shown, oldest first.
  ///
  /// While [isViewingHistory], this stops at the viewed position; see
  /// [fullLine] for every move played.
  List<BoardMove> get history => List.unmodifiable(_line.take(_cursor));

  /// Every move played in the game, including moves after the viewed
  /// position.
  List<BoardMove> get fullLine => List.unmodifiable(_line);

  /// The move that led to the position shown, or null at the start.
  BoardMove? get lastMove => _cursor == 0 ? null : _line[_cursor - 1];

  /// Number of half-moves played in the game, including any after the
  /// position shown. Same as the length of [fullLine]; see [ply] for the
  /// position shown.
  int get halfMoveCount => _line.length;

  /// The ply being shown: 0 for the starting position, up to the length of
  /// [fullLine] for the latest position.
  int get ply => _cursor;

  /// Whether an earlier position is shown, with later moves still in
  /// [fullLine].
  ///
  /// While true, moves are rejected unless [allowBranching] is
  /// set, and [undo] does nothing.
  bool get isViewingHistory => _cursor < _line.length;

  /// Whether [back] would move to an earlier position.
  bool get canGoBack => _cursor > 0;

  /// Whether [forward] would move to a later position.
  bool get canGoForward => _cursor < _line.length;

  /// Headers included in [pgn], such as `White` or `Event`.
  ///
  /// Cleared by [reset] and [loadFen], and replaced by [loadPgn]. The
  /// `SetUp` and `FEN` headers are managed automatically and never appear
  /// here.
  Map<String, String> get pgnHeaders => Map.unmodifiable(_headers);

  /// Sets a PGN header. A null [value] removes it.
  ///
  /// [key] must be letters, digits and underscores, and cannot be `SetUp`
  /// or `FEN`, which follow [startingFen]. Throws an [ArgumentError]
  /// otherwise. Headers don't affect the position, so this never notifies
  /// listeners.
  void setPgnHeader(String key, String? value) {
    if (!_headerKey.hasMatch(key) || key == 'SetUp' || key == 'FEN') {
      throw ArgumentError.value(key, 'key', 'Not a settable PGN header');
    }
    if (value == null) {
      _headers.remove(key);
    } else {
      _headers[key] = value;
    }
  }

  /// The game in Portable Game Notation, with [pgnHeaders].
  ///
  /// Always contains [fullLine], whichever position is shown. Games that
  /// don't start from the standard position get `SetUp` and
  /// `FEN` headers. When the game is over and no `Result` header was set,
  /// the result is filled in automatically.
  String get pgn => _writePgn();

  /// All legal moves in the current position, with SAN and flags.
  List<BoardMove> get legalMoves => _position.legalMoves;

  /// Legal moves for the piece on [square]; empty if there are none.
  List<BoardMove> legalMovesFrom(Square square) =>
      _position.movesFrom[square] ?? const [];

  /// The piece on [square], or null if it is empty.
  Piece? pieceAt(Square square) => _position.pieces[square];

  /// Every piece on the board, keyed by square.
  Map<Square, Piece> get pieces => _position.pieces;

  /// The most recent change to the game state.
  BoardChange get lastChange => _lastChange;

  /// A counter that increases on every change, notified or not.
  ///
  /// The board compares it to tell a new change apart from a rebuild.
  int get changeId => _changeId;

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  /// Plays the move from [from] to [to], with [promotion] for a pawn
  /// reaching the last rank.
  ///
  /// The move is checked against the rules engine's legal move list.
  /// Returns true if it was legal and applied. Moves are rejected once the
  /// game is over, including after a draw by rule. A pawn move to the last
  /// rank without [promotion] is rejected. [promotion] is ignored for moves
  /// that don't promote, so apps can always pass their preferred piece.
  bool move(
    Square from,
    Square to, {
    PieceType? promotion,
    bool notify = true,
  }) => _move(from, to, promotion, MoveSource.code, notify);

  /// Plays a move given in standard algebraic notation, such as `Nf3`,
  /// `exd5`, `O-O` or `e8=Q`.
  ///
  /// Check and annotation suffixes (`+`, `#`, `!`, `?`) and the `=` in
  /// promotions are optional, and castling may be written with zeros
  /// (`0-0`). Returns true if the move was legal and applied.
  bool moveSan(String san, {bool notify = true}) {
    final m = _matchSan(_engine, _position.raw, san);
    if (m == null) return false;
    return _apply(m, MoveSource.code, notify);
  }

  /// Takes back the last move, removing it from the game.
  ///
  /// Returns false, and does nothing, if no moves have been played or an
  /// earlier position is shown ([isViewingHistory]). To look back without
  /// removing moves, use [back].
  bool undo({bool notify = true}) {
    if (_line.isEmpty || isViewingHistory) return false;
    _engine.undo_move();
    _invalidate();
    _line.removeLast();
    _rawLine.removeLast();
    _positionKeys.removeLast();
    _cursor--;
    _changed(PositionReplaced(silent: !notify), notify);
    return true;
  }

  /// Shows the previous position, keeping later moves. Returns false at
  /// the start of the game.
  bool back({bool notify = true}) =>
      canGoBack && goTo(_cursor - 1, notify: notify);

  /// Shows the next position in [fullLine]. Returns false at the latest
  /// position.
  bool forward({bool notify = true}) =>
      canGoForward && goTo(_cursor + 1, notify: notify);

  /// Shows the starting position, keeping every move.
  bool goToStart({bool notify = true}) => goTo(0, notify: notify);

  /// Shows the latest position.
  bool goToEnd({bool notify = true}) => goTo(_line.length, notify: notify);

  /// Shows the position after [ply] moves of [fullLine].
  ///
  /// Returns false, and does nothing, if that position is already shown.
  /// Throws a [RangeError] if [ply] is not between 0 and the length of
  /// [fullLine].
  bool goTo(int ply, {bool notify = true}) {
    RangeError.checkValueInInterval(ply, 0, _line.length, 'ply');
    if (ply == _cursor) return false;
    final from = _cursor;
    _seek(ply);
    _changed(NavigatedTo(fromPly: from, toPly: ply, silent: !notify), notify);
    return true;
  }

  /// Starts a new game from the standard starting position.
  void reset({bool notify = true}) {
    _engine = ch.Chess();
    _headers.clear();
    _resetState(kInitialFen);
    _changed(PositionReplaced(silent: !notify), notify);
  }

  /// Starts a new game from [fen].
  ///
  /// Returns false, and leaves the current game unchanged, if [fen] is
  /// malformed or describes an impossible position. Rejected positions
  /// include: not exactly one king per side, pawns on the first or last
  /// rank, the side not to move being in check, castling rights without the
  /// king and rook on their home squares, and an en passant square that no
  /// double pawn push could have produced.
  bool loadFen(String fen, {bool notify = true}) {
    if (!_load(fen)) return false;
    _headers.clear();
    _changed(PositionReplaced(silent: !notify), notify);
    return true;
  }

  /// Loads a game from Portable Game Notation, replacing the current game
  /// and [pgnHeaders].
  ///
  /// Comments, variations, numeric annotation glyphs and move numbers are
  /// skipped. Returns false, and leaves the current game unchanged, if [pgn]
  /// is empty, has an invalid `FEN` header, or contains an illegal move.
  bool loadPgn(String pgn, {bool notify = true}) {
    final parsed = _parsePgn(pgn);
    if (parsed == null) return false;

    final startFen = parsed.headers['FEN'] ?? kInitialFen;
    final replay = ch.Chess();
    if (!_isLegalPosition(startFen, into: replay)) return false;

    final moves = <BoardMove>[];
    final rawMoves = <ch.Move>[];
    var raw = replay.generate_moves();
    final keys = [_repetitionKey(replay, raw)];
    for (final token in parsed.moves) {
      final m = _matchSan(replay, raw, token);
      if (m == null) return false;
      moves.add(_describe(replay, m));
      rawMoves.add(m);
      replay.make_move(m);
      raw = replay.generate_moves();
      keys.add(_repetitionKey(replay, raw));
    }

    _engine = replay;
    _startFen = replay.history.isEmpty ? replay.fen : _normalizedFen(startFen);
    _invalidate();
    _line
      ..clear()
      ..addAll(moves);
    _rawLine
      ..clear()
      ..addAll(rawMoves);
    _cursor = moves.length;
    _positionKeys
      ..clear()
      ..addAll(keys);
    _headers
      ..clear()
      ..addAll({
        for (final MapEntry(:key, :value) in parsed.headers.entries)
          if (key != 'SetUp' &&
              key != 'FEN' &&
              !(key == 'Result' && value == '*'))
            key: value,
      });
    _changed(PositionReplaced(silent: !notify), notify);
    return true;
  }

  /// Notifies listeners, such as the board, that the game state changed.
  ///
  /// Call this after a batch of actions made with `notify: false`.
  @override
  // Made public on purpose so apps can batch changes.
  // ignore: unnecessary_overrides
  void notifyListeners() => super.notifyListeners();

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  _PositionCache get _position => _cache ??= _PositionCache(this);

  bool _move(
    Square from,
    Square to,
    PieceType? promotion,
    MoveSource source,
    bool notify,
  ) {
    // Early exit before searching moves; _apply checks this again for
    // moves that reach it by other routes, such as moveSan.
    if (isViewingHistory && !_allowBranching) return false;
    for (final m in _position.raw) {
      if (m.fromAlgebraic != from.name || m.toAlgebraic != to.name) continue;
      if (m.promotion == null || m.promotion!.name == promotion?.letter) {
        return _apply(m, source, notify);
      }
    }
    return false;
  }

  bool _apply(ch.Move m, MoveSource source, bool notify) {
    // The engine still generates moves after a draw by rule (repetition,
    // fifty moves, insufficient material), but the game is over.
    if (isGameOver) return false;
    final discarded = _line.length - _cursor;
    if (discarded > 0) {
      if (!_allowBranching) return false;
      // Start a new branch: drop the moves after the shown position.
      _line.removeRange(_cursor, _line.length);
      _rawLine.removeRange(_cursor, _rawLine.length);
      _positionKeys.removeRange(_cursor + 1, _positionKeys.length);
    }
    final applied = _describe(_engine, m);
    _engine.make_move(m);
    _invalidate();
    _line.add(applied);
    _rawLine.add(m);
    _cursor++;
    _positionKeys.add(_position.repetitionKey);
    _changed(
      MoveApplied(
        applied,
        source: source,
        silent: !notify,
        discardedPlies: discarded,
      ),
      notify,
    );
    return true;
  }

  bool _load(String fen) {
    final candidate = ch.Chess();
    if (!_isLegalPosition(fen, into: candidate)) return false;
    _engine = candidate;
    _resetState(candidate.fen);
    return true;
  }

  void _resetState(String startFen) {
    _startFen = startFen;
    _invalidate();
    _line.clear();
    _rawLine.clear();
    _cursor = 0;
    _positionKeys
      ..clear()
      ..add(_position.repetitionKey);
  }

  /// Moves the engine to the position after [ply] moves without recording
  /// a change. Moves are replayed from [_rawLine], so this never consults
  /// the move generator.
  void _seek(int ply) {
    if (ply == _cursor) return; // Keep the cache when nothing moves.
    while (_cursor > ply) {
      _engine.undo_move();
      _cursor--;
    }
    while (_cursor < ply) {
      _engine.make_move(_rawLine[_cursor]);
      _cursor++;
    }
    _invalidate();
  }

  /// Must be called after every change to [_engine].
  void _invalidate() => _cache = null;

  void _changed(BoardChange change, bool notify) {
    _lastChange = change;
    _changeId++;
    if (notify) notifyListeners();
  }

  String _writePgn() {
    // The result belongs to the end of the game, not the shown position.
    final shown = _cursor;
    _seek(_line.length);
    final endResult = isGameOver ? result : null;
    _seek(shown);

    final headers = <String, String>{
      ..._headers,
      if (!_headers.containsKey('Result') && endResult != null)
        'Result': endResult.pgn,
      if (_startFen != kInitialFen) ...{'SetUp': '1', 'FEN': _startFen},
    };
    final out = StringBuffer();
    for (final MapEntry(:key, :value) in headers.entries) {
      out.writeln('[$key "${_escapePgnValue(value)}"]');
    }
    if (headers.isNotEmpty) out.writeln();

    final fields = _startFen.split(' ');
    var moveNumber = int.tryParse(fields[5]) ?? 1;
    var whiteToMove = fields[1] == 'w';
    final tokens = <String>[];
    for (final (i, m) in _line.indexed) {
      if (whiteToMove) {
        tokens.add('$moveNumber.');
      } else if (i == 0) {
        tokens.add('$moveNumber...');
      }
      tokens.add(m.san!);
      if (!whiteToMove) moveNumber++;
      whiteToMove = !whiteToMove;
    }
    tokens.add(headers['Result'] ?? '*');

    // Wrap movetext below 80 columns, as the PGN export format asks.
    var lineLength = 0;
    for (final token in tokens) {
      if (lineLength > 0 && lineLength + 1 + token.length > 79) {
        out.writeln();
        lineLength = 0;
      }
      if (lineLength > 0) {
        out.write(' ');
        lineLength++;
      }
      out.write(token);
      lineLength += token.length;
    }
    return out.toString();
  }
}

/// Plays a move on behalf of the user. Used by the board widget, not part
/// of the public API.
bool applyUserMove(
  ChessBoardController controller,
  Square from,
  Square to, {
  PieceType? promotion,
}) => controller._move(from, to, promotion, MoveSource.user, true);

/// Lazily computed facts about one position. Discarded on every change.
class _PositionCache {
  _PositionCache(this._c) : _engine = _c._engine;

  final ChessBoardController _c;
  final ch.Chess _engine;

  /// Legal moves in the engine's own format, generated once per position.
  late final List<ch.Move> raw = _engine.generate_moves();

  late final String fen = _engine.fen;

  late final PieceColor turn = _engine.turn == ch.Color.WHITE
      ? PieceColor.white
      : PieceColor.black;

  late final bool inCheck = _engine.in_check;

  late final String repetitionKey = _repetitionKey(_engine, raw);

  late final List<BoardMove> legalMoves = List.unmodifiable([
    for (final m in raw) _describe(_engine, m),
  ]);

  late final Map<Square, List<BoardMove>> movesFrom = () {
    final map = <Square, List<BoardMove>>{};
    for (final m in legalMoves) {
      (map[m.from] ??= []).add(m);
    }
    return {
      for (final MapEntry(:key, :value) in map.entries)
        key: List<BoardMove>.unmodifiable(value),
    };
  }();

  late final Map<Square, Piece> pieces = Map.unmodifiable({
    for (final square in Square.values)
      if (_engine.get(square.name) case final p?) square: _piece(p),
  });

  late final DrawReason? drawReason = _computeDrawReason();

  late final GameStatus status = raw.isEmpty
      ? (inCheck ? GameStatus.checkmate : GameStatus.stalemate)
      : (drawReason == null ? GameStatus.ongoing : GameStatus.draw);

  DrawReason? _computeDrawReason() {
    if (raw.isEmpty) return inCheck ? null : DrawReason.stalemate;
    if (_engine.insufficient_material) return DrawReason.insufficientMaterial;
    // Only positions up to the one shown count towards repetition.
    final keys = _c._positionKeys.take(_c._cursor + 1);
    final current = keys.last;
    if (keys.where((k) => k == current).length >= 3) {
      return DrawReason.threefoldRepetition;
    }
    if (_engine.half_moves >= 100) return DrawReason.fiftyMoveRule;
    return null;
  }
}

/// Builds a [BoardMove] for [m], which must be legal in [engine]'s current
/// position. Leaves [engine] unchanged.
BoardMove _describe(ch.Chess engine, ch.Move m) {
  final san = engine.move_to_san(m);
  final color = m.color == ch.Color.WHITE ? PieceColor.white : PieceColor.black;
  final flags = m.flags;
  return BoardMove(
    from: Square.parse(m.fromAlgebraic),
    to: Square.parse(m.toAlgebraic),
    promotion: m.promotion == null ? null : _type(m.promotion!),
    piece: Piece(color, _type(m.piece)),
    san: san,
    captured: m.captured == null
        ? null
        : Piece(color.opposite, _type(m.captured!)),
    castle: (flags & ch.Chess.BITS_KSIDE_CASTLE) != 0
        ? CastleSide.kingside
        : (flags & ch.Chess.BITS_QSIDE_CASTLE) != 0
        ? CastleSide.queenside
        : null,
    isEnPassant: (flags & ch.Chess.BITS_EP_CAPTURE) != 0,
    isCheck: san.endsWith('+') || san.endsWith('#'),
    isCheckmate: san.endsWith('#'),
  );
}

PieceType _type(ch.PieceType t) => PieceType.fromLetter(t.name)!;

Piece _piece(ch.Piece p) => Piece(
  p.color == ch.Color.WHITE ? PieceColor.white : PieceColor.black,
  _type(p.type),
);

/// Identifies a position for the repetition rule: placement, side to move,
/// castling rights, and the en passant square only when an en passant
/// capture is actually possible (as FIDE rules require).
String _repetitionKey(ch.Chess engine, List<ch.Move> raw) {
  final f = engine.fen.split(' ');
  final epPossible = raw.any((m) => (m.flags & ch.Chess.BITS_EP_CAPTURE) != 0);
  return '${f[0]} ${f[1]} ${f[2]} ${epPossible ? f[3] : '-'}';
}

/// Finds the legal move in [raw] that [san] describes, or null.
ch.Move? _matchSan(ch.Chess engine, List<ch.Move> raw, String san) {
  final wanted = _normalizeSan(san);
  if (wanted.isEmpty) return null;
  // Only compute SAN for moves to the named square. Castling names no square.
  final target = _lastSquare.allMatches(wanted).lastOrNull?.group(0);
  for (final m in raw) {
    if (target != null && m.toAlgebraic != target) continue;
    if (_normalizeSan(engine.move_to_san(m)) == wanted) return m;
  }
  return null;
}

final _lastSquare = RegExp('[a-h][1-8]');

String _normalizeSan(String san) => san
    .trim()
    .replaceAll('0', 'O')
    .replaceAll('=', '')
    .replaceAll(RegExp(r'[+#!?]+$'), '');

/// Validates [fen] and loads it into [into]. Returns false, leaving [into]
/// in an unspecified state, if the FEN is malformed or the position is
/// impossible. See [ChessBoardController.loadFen].
bool _isLegalPosition(String fen, {required ch.Chess into}) {
  final normalized = _normalizedFen(fen);
  // validate_fen checks the syntax; load() would print on failure.
  if (ch.Chess.validate_fen(normalized)['valid'] != true) return false;
  if (!into.load(normalized, check_validity: false)) return false;

  Piece? at(int file, int rank) {
    final p = into.get(Square.at(file, rank).name);
    return p == null ? null : _piece(p);
  }

  var whiteKings = 0;
  var blackKings = 0;
  for (final square in Square.values) {
    final p = at(square.file, square.rank);
    if (p == null) continue;
    if (p == Piece.whiteKing) whiteKings++;
    if (p == Piece.blackKing) blackKings++;
    final backRank = square.rank == 0 || square.rank == 7;
    if (p.type == PieceType.pawn && backRank) return false;
  }
  if (whiteKings != 1 || blackKings != 1) return false;

  // The side that just moved must not be left in check.
  final whiteToMove = into.turn == ch.Color.WHITE;
  if (into.king_attacked(whiteToMove ? ch.Color.BLACK : ch.Color.WHITE)) {
    return false;
  }

  // Castling rights need the king and rook on their home squares.
  final fields = normalized.split(' ');
  for (final right in fields[2].split('')) {
    final ok = switch (right) {
      '-' => true,
      'K' => at(4, 0) == Piece.whiteKing && at(7, 0) == Piece.whiteRook,
      'Q' => at(4, 0) == Piece.whiteKing && at(0, 0) == Piece.whiteRook,
      'k' => at(4, 7) == Piece.blackKing && at(7, 7) == Piece.blackRook,
      'q' => at(4, 7) == Piece.blackKing && at(0, 7) == Piece.blackRook,
      _ => false,
    };
    if (!ok) return false;
  }

  // An en passant square must sit behind a pawn that just double-pushed.
  if (fields[3] != '-') {
    final ep = Square.tryParse(fields[3]);
    if (ep == null) return false;
    final (epRank, pawnRank, originRank, pusher) = whiteToMove
        ? (5, 4, 6, Piece.blackPawn)
        : (2, 3, 1, Piece.whitePawn);
    if (ep.rank != epRank ||
        at(ep.file, pawnRank) != pusher ||
        at(ep.file, epRank) != null ||
        at(ep.file, originRank) != null) {
      return false;
    }
  }
  return true;
}

/// Trims [fen] and collapses runs of whitespace to single spaces.
String _normalizedFen(String fen) => fen.trim().split(RegExp(r'\s+')).join(' ');

final _headerKey = RegExp(r'^[A-Za-z0-9_]+$');

String _escapePgnValue(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll(RegExp(r'[\r\n]+'), ' ');

/// Headers and SAN move tokens read from a PGN string.
typedef _ParsedPgn = ({Map<String, String> headers, List<String> moves});

final _headerLine = RegExp(
  r'^\s*\[\s*([A-Za-z0-9_]+)\s+"((?:[^"\\]|\\.)*)"\s*\]\s*$',
);
const _results = {'1-0', '0-1', '1/2-1/2', '*'};

/// Parses [pgn] into headers and SAN tokens, or returns null if it holds
/// neither headers nor moves.
_ParsedPgn? _parsePgn(String pgn) {
  final headers = <String, String>{};
  final movetext = StringBuffer();
  var inMovetext = false;
  for (final line in pgn.split(RegExp(r'\r?\n'))) {
    if (line.startsWith('%')) continue; // PGN escape line.
    final header = inMovetext ? null : _headerLine.firstMatch(line);
    if (header != null) {
      headers[header.group(1)!] = header
          .group(2)!
          .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
    } else if (line.trim().isNotEmpty) {
      inMovetext = true;
      movetext.writeln(line);
    }
  }

  var text = movetext.toString();
  text = text.replaceAll(RegExp(r'\{[^}]*\}'), ' '); // {comments}
  text = text.replaceAll(RegExp(r';[^\n]*'), ' '); // ; comments
  final variation = RegExp(r'\([^()]*\)');
  while (variation.hasMatch(text)) {
    text = text.replaceAll(variation, ' '); // (nested) variations
  }
  text = text.replaceAll(RegExp(r'\$\d+'), ' '); // NAGs
  text = text.replaceAll(RegExp(r'\d+\.+'), ' '); // move numbers

  final tokens = text
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !RegExp(r'^\.+$').hasMatch(t))
      .where((t) => t != 'e.p.')
      .toList();
  if (headers.isEmpty && tokens.isEmpty) return null;
  return (
    headers: headers,
    moves: [
      for (final t in tokens)
        if (!_results.contains(t)) t,
    ],
  );
}
