import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../controller/chess_board_controller.dart';
import '../pieces/piece_set.dart';
import '../theme/chess_board_theme.dart';
import 'board_geometry.dart';
import 'layers/labels_layer.dart';
import 'layers/pieces_layer.dart';
import 'layers/squares_layer.dart';

/// An interactive chess board.
///
/// The simplest board needs only a controller:
///
/// ```dart
/// final controller = ChessBoardController();
///
/// ChessBoard(controller: controller)
/// ```
///
/// The board is always square, sized to the smaller of the available width
/// and height, and updates itself whenever the controller changes.
class ChessBoard extends StatefulWidget {
  /// Creates a chess board.
  const ChessBoard({
    super.key,
    required this.controller,
    this.orientation = BoardOrientation.white,
    this.initialFen,
    this.theme = ChessBoardTheme.defaultTheme,
    this.lightSquareColor,
    this.darkSquareColor,
    this.checkmateColor,
    this.pieceSet = PieceSet.standard,
    this.coordinates = CoordinateMode.inside,
  });

  /// The game shown on the board.
  final ChessBoardController controller;

  /// Which color is at the bottom.
  final BoardOrientation orientation;

  /// A position to load into [controller] when the board first appears.
  ///
  /// Applied once; changing it later has no effect, so use the controller
  /// to change the position afterwards. Throws an [ArgumentError] when the
  /// board first builds if the FEN is not a valid position.
  final String? initialFen;

  /// Every color the board paints. Defaults to the green preset.
  final ChessBoardTheme theme;

  /// Overrides [ChessBoardTheme.lightSquareColor].
  final Color? lightSquareColor;

  /// Overrides [ChessBoardTheme.darkSquareColor].
  final Color? darkSquareColor;

  /// Overrides [ChessBoardTheme.checkmateColor].
  final Color? checkmateColor;

  /// The piece artwork.
  final PieceSet pieceSet;

  /// Where coordinate labels go.
  final CoordinateMode coordinates;

  /// The theme with the shortcut color parameters applied.
  ChessBoardTheme get effectiveTheme =>
      lightSquareColor == null &&
          darkSquareColor == null &&
          checkmateColor == null
      ? theme
      : theme.copyWith(
          lightSquareColor: lightSquareColor,
          darkSquareColor: darkSquareColor,
          checkmateColor: checkmateColor,
        );

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  /// The set currently drawn. Stays on the previous set while a new one
  /// loads, and is null only before the first set is ready.
  PieceSet? _shownSet;

  /// The set being loaded, to ignore results that arrive after a newer
  /// request.
  PieceSet? _loadingSet;

  @override
  void initState() {
    super.initState();
    _applyInitialFen();
  }

  /// Loads [ChessBoard.initialFen] into a controller that hasn't been used
  /// yet. A controller with moves played or a position loaded is left
  /// alone, so remounting the board (tabs, lists, route changes) or giving
  /// the same controller to a second board never wipes a game in progress.
  void _applyInitialFen() {
    final fen = widget.initialFen;
    if (fen == null) return;
    final c = widget.controller;
    final untouched = c.changeId == 0 && c.startingFen == kInitialFen;
    if (!untouched) {
      // Still validate, so a bad value fails the same way every time.
      if (!ChessBoardController.isValidFen(fen)) _throwBadFen(fen);
      return;
    }
    if (!c.loadFen(fen, notify: false)) _throwBadFen(fen);
  }

  Never _throwBadFen(String fen) => throw ArgumentError.value(
    fen,
    'initialFen',
    'Not a valid chess position',
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shownSet == null && _loadingSet == null) _load(widget.pieceSet);
  }

  @override
  void didUpdateWidget(ChessBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pieceSet != oldWidget.pieceSet &&
        widget.pieceSet != _loadingSet) {
      _load(widget.pieceSet);
    }
  }

  void _load(PieceSet set) {
    _loadingSet = set;
    final future = set.precache(context);
    void show() {
      if (!mounted || _loadingSet != set) return;
      _loadingSet = null;
      if (_shownSet != set) setState(() => _shownSet = set);
    }

    if (future is SynchronousFuture) {
      // Already loaded: show it in this frame, without a rebuild.
      _loadingSet = null;
      _shownSet = set;
      return;
    }
    future.then(
      (_) => show(),
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'modern_chess_board',
            context: ErrorDescription('while loading the piece set $set'),
          ),
        );
        // Show the set anyway; pieces load on demand.
        show();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.effectiveTheme;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final ambientStyle = DefaultTextStyle.of(context).style;
    // Without a Material ancestor, the ambient style is Flutter's red
    // "missing Material" debug style; never let that tint the labels.
    final ambient = _isFallbackStyle(ambientStyle) ? null : ambientStyle.color;
    return BoardLayout(
      coordinates: widget.coordinates,
      builder: (context, metrics) {
        final geometry = metrics.geometry(widget.orientation);
        final labels = layoutBoardLabels(
          metrics: metrics,
          orientation: widget.orientation,
          theme: theme,
          ambientTextColor: ambient,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: BoardSquaresPainter(
                    geometry: geometry,
                    lightColor: theme.lightSquareColor,
                    darkColor: theme.darkSquareColor,
                    devicePixelRatio: dpr,
                  ),
                ),
              ),
            ),
            if (labels.isNotEmpty)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: BoardLabelsPainter(
                      labels: labels,
                      // Inherit the app's font family; size, weight and
                      // line height are the board's. Colors come per label.
                      style:
                          (_isFallbackStyle(ambientStyle)
                                  ? const TextStyle()
                                  : ambientStyle)
                              .merge(
                                TextStyle(
                                  fontSize: metrics.labelFontSize,
                                  fontWeight: FontWeight.w600,
                                  height: 1,
                                  letterSpacing: 0,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                      marginColor: theme.marginColor,
                      metrics: metrics,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: PiecesLayer(
                controller: widget.controller,
                geometry: geometry,
                pieceSet: _shownSet,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Whether [style] is the red debug style Flutter uses for text with no
/// Material ancestor. That style marks a missing ancestor; it is never a
/// color the app chose for its text.
bool _isFallbackStyle(TextStyle style) =>
    style.color == const Color(0xD0FF0000) &&
    style.decoration == TextDecoration.underline;
