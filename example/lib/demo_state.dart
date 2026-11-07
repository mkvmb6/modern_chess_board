import 'dart:async';
import 'dart:math';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

/// Who plays which side in the demo.
enum Opponent {
  /// One person plays both sides on this device.
  none('Both sides'),

  /// The user plays white; the app answers with random moves.
  randomBlack('White vs. random'),

  /// The user plays black; the app opens with random moves.
  randomWhite('Black vs. random');

  const Opponent(this.label);

  /// Shown in the picker.
  final String label;
}

/// Everything the demo's controls change, in one place so the board, the
/// score sheet and the controls stay in step.
class DemoState extends ChangeNotifier {
  /// Creates the demo with a fresh game.
  DemoState({
    Random? random,
    this.opponentDelay = const Duration(milliseconds: 450),
  }) : _random = random ?? Random() {
    controller.addListener(_onGameChanged);
  }

  final Random _random;

  /// How long the random opponent "thinks" before moving.
  final Duration opponentDelay;

  /// The game.
  final ChessBoardController controller = ChessBoardController();

  /// The most recent sound events, newest first, for the event log.
  final List<SoundEvent> soundLog = [];

  Timer? _opponentTimer;

  // ---- appearance ---------------------------------------------------------

  ChessBoardTheme _theme = ChessBoardTheme.green;
  ChessBoardTheme get theme => _theme;
  set theme(ChessBoardTheme value) => _set(() => _theme = value);

  bool _glyphPieces = false;

  /// Whether pieces are drawn with the font's chess glyphs instead of the
  /// package's artwork, to show a custom piece set.
  bool get glyphPieces => _glyphPieces;
  set glyphPieces(bool value) => _set(() => _glyphPieces = value);

  CoordinateMode _coordinates = CoordinateMode.inside;
  CoordinateMode get coordinates => _coordinates;
  set coordinates(CoordinateMode value) => _set(() => _coordinates = value);

  BoardOrientation _orientation = BoardOrientation.white;
  BoardOrientation get orientation => _orientation;

  /// Turns the board around.
  void flip() => _set(
    () => _orientation = _orientation == BoardOrientation.white
        ? BoardOrientation.black
        : BoardOrientation.white,
  );

  // ---- play ---------------------------------------------------------------

  Opponent _opponent = Opponent.none;
  Opponent get opponent => _opponent;
  set opponent(Opponent value) {
    _set(() {
      _opponent = value;
      _sideOverride = null;
      // Face the side being played.
      if (value == Opponent.randomWhite) {
        _orientation = BoardOrientation.black;
      } else if (value == Opponent.randomBlack) {
        _orientation = BoardOrientation.white;
      }
    });
    _maybeScheduleOpponent();
  }

  bool _readOnly = false;
  bool get readOnly => _readOnly;
  set readOnly(bool value) => _set(() => _readOnly = value);

  bool _premoves = true;

  /// Whether premoves are on. They take effect against the random
  /// opponent, where the user plays one side.
  bool get premoves => _premoves;
  set premoves(bool value) => _set(() => _premoves = value);

  bool _autoQueen = false;
  bool get autoQueen => _autoQueen;
  set autoQueen(bool value) => _set(() => _autoQueen = value);

  bool _haptics = true;
  bool get haptics => _haptics;
  set haptics(bool value) => _set(() => _haptics = value);

  InteractiveSide? _sideOverride;

  /// The side the user may move. Follows the opponent choice unless set
  /// directly, to show every [InteractiveSide] value.
  InteractiveSide get interactiveSide =>
      _sideOverride ??
      switch (_opponent) {
        Opponent.none => InteractiveSide.both,
        Opponent.randomBlack => InteractiveSide.white,
        Opponent.randomWhite => InteractiveSide.black,
      };
  set interactiveSide(InteractiveSide value) {
    _set(() => _sideOverride = value);
    _maybeScheduleOpponent();
  }

  bool _drawing = true;

  /// Whether the user can draw arrows and circles.
  bool get drawing => _drawing;
  set drawing(bool value) => _set(() {
    _drawing = value;
    if (!value) _userArrows = 0;
  });

  int _userArrows = 0;
  int _userCircles = 0;

  /// How many arrows and circles the user has drawn, from the board's
  /// callbacks.
  String get drawingsSummary => switch ((_userArrows, _userCircles)) {
    (0, 0) => 'Nothing drawn',
    (final a, 0) => '$a ${a == 1 ? 'arrow' : 'arrows'} drawn',
    (0, final c) => '$c ${c == 1 ? 'circle' : 'circles'} drawn',
    (final a, final c) =>
      '$a ${a == 1 ? 'arrow' : 'arrows'}, '
          '$c ${c == 1 ? 'circle' : 'circles'} drawn',
  };

  /// Called by the board when the user's arrows change.
  void onUserArrows(List<Arrow> arrows) =>
      _set(() => _userArrows = arrows.length);

  /// Called by the board when the user's circles change.
  void onUserMarks(List<SquareMark> marks) =>
      _set(() => _userCircles = marks.length);

  // ---- annotations --------------------------------------------------------

  bool _showIdeas = false;

  /// Whether the demo shows sample arrows and marks for the position.
  bool get showIdeas => _showIdeas;
  set showIdeas(bool value) => _set(() => _showIdeas = value);

  Arrow? _hint;

  /// The suggestion arrow, if any. It disappears on the next move or after
  /// its timeout; ask again for another.
  Arrow? get hint => _hint;

  /// Whether a hint can be asked for now: it is the user's turn in a live
  /// game.
  bool get canHint =>
      _isUsersTurn && !controller.isGameOver && !controller.isViewingHistory;

  /// Shows a random legal move for the side to move as a hint.
  void askForHint() {
    if (!canHint) return;
    final moves = controller.legalMoves;
    // Pick one that differs from the hint showing (or just dismissed), so
    // asking again always shows something.
    final options = [
      for (final m in moves)
        if (_hint == null ||
            m.from.name != _hint!.from ||
            m.to.name != _hint!.to)
          m,
    ];
    final pool = options.isEmpty ? moves : options;
    final m = pool[_random.nextInt(pool.length)];
    _set(() => _hint = Arrow.fromSquares(m.from, m.to));
  }

  /// Sample annotation arrows: one legal move for each side from the
  /// position shown, so they always make sense.
  List<Arrow> get arrows {
    if (!_showIdeas) return const [];
    final moves = controller.legalMoves;
    final mine = moves.isEmpty ? null : moves[controller.ply % moves.length];
    return [
      if (mine != null)
        Arrow.fromSquares(mine.from, mine.to, color: const Color(0xCC2E7D32)),
    ];
  }

  /// Sample marks: the centre squares, ringed or tinted by who holds them.
  List<SquareMark> get marks {
    if (!_showIdeas) return const [];
    return [
      for (final s in [Square.d4, Square.e4, Square.d5, Square.e5])
        switch (controller.pieceAt(s)) {
          null => SquareMark(s.name),
          final p => SquareMark(
            s.name,
            shape: MarkShape.fill,
            color: p.color == PieceColor.white
                ? const Color(0x4DFFFFFF)
                : const Color(0x4D000000),
          ),
        },
    ];
  }

  // ---- game actions -------------------------------------------------------

  /// Starts again from the initial position.
  void newGame() {
    _opponentTimer?.cancel();
    controller.reset();
    _hint = null;
    soundLog.clear();
    notifyListeners();
    _maybeScheduleOpponent();
  }

  /// Whether [takeBack] would do anything: there is a move by the user to
  /// take back, and the latest position is shown.
  bool get canTakeBack {
    if (controller.isViewingHistory) return false;
    final n = controller.halfMoveCount;
    if (_opponent == Opponent.none) return n > 0;
    // Against the opponent, a take-back removes the user's last move (and
    // the reply to it), so the user must have moved at least once.
    final userMovedFirst = interactiveSide.allows(_startingTurn);
    return userMovedFirst ? n >= 1 : n >= 2;
  }

  PieceColor get _startingTurn => controller.startingFen.split(' ')[1] == 'b'
      ? PieceColor.black
      : PieceColor.white;

  /// Takes back a move, or two against the opponent so it's the user's
  /// turn again.
  void takeBack() {
    if (!canTakeBack) return;
    _opponentTimer?.cancel();
    controller.undo();
    if (_opponent != Opponent.none && !_isUsersTurn) controller.undo();
    notifyListeners();
    _maybeScheduleOpponent();
  }

  /// Loads a FEN, or failing that a PGN. Returns false, changing nothing,
  /// if it is neither.
  bool loadAny(String text) {
    final t = text.trim();
    if (ChessBoardController.isValidFen(t)) return loadFen(t);
    return loadPgn(t);
  }

  /// Loads [fen]. Returns false, changing nothing, if it isn't valid.
  bool loadFen(String fen) {
    final ok = controller.loadFen(fen.trim());
    if (ok) {
      _hint = null;
      notifyListeners();
      _maybeScheduleOpponent();
    }
    return ok;
  }

  /// Loads a game in PGN. Returns false, changing nothing, if it can't be
  /// read.
  bool loadPgn(String pgn) {
    final ok = controller.loadPgn(pgn.trim());
    if (ok) {
      _hint = null;
      notifyListeners();
    }
    return ok;
  }

  /// Records a sound event for the log.
  void logSound(SoundEvent event) {
    soundLog.insert(0, event);
    if (soundLog.length > 6) soundLog.removeLast();
    notifyListeners();
  }

  // ---- the random opponent -------------------------------------------------

  bool get _isUsersTurn => interactiveSide.allows(controller.turn);

  void _onGameChanged() {
    // A new position: the board has already retired the hint.
    _hint = null;
    notifyListeners();
    _maybeScheduleOpponent();
  }

  void _maybeScheduleOpponent() {
    if (_opponent == Opponent.none ||
        _isUsersTurn ||
        controller.isGameOver ||
        controller.isViewingHistory ||
        (_opponentTimer?.isActive ?? false)) {
      return;
    }
    _opponentTimer = Timer(opponentDelay, () {
      if (_opponent == Opponent.none ||
          _isUsersTurn ||
          controller.isViewingHistory) {
        return;
      }
      final moves = controller.legalMoves;
      if (moves.isEmpty || controller.isGameOver) return;
      final m = moves[_random.nextInt(moves.length)];
      controller.move(m.from, m.to, promotion: m.promotion);
    });
  }

  void _set(VoidCallback change) {
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    _opponentTimer?.cancel();
    controller
      ..removeListener(_onGameChanged)
      ..dispose();
    super.dispose();
  }
}
