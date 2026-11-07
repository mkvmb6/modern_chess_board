import 'package:flutter/widgets.dart';

import '../../model/square.dart';
import '../../pieces/piece_set.dart';
import '../board_geometry.dart';
import 'move_plan.dart';

/// Runs move animations: one plan at a time, driven by one controller.
///
/// While a plan runs, its destination squares are reported in
/// [hiddenSquares] so the pieces layer leaves them empty and a piece is
/// never drawn twice. Starting a new plan while one is running commits the
/// old one at once, so the board never shows a stale position.
class MoveAnimator extends ChangeNotifier {
  /// Creates an animator that ticks with [vsync].
  MoveAnimator({required TickerProvider vsync})
    : _controller = AnimationController(vsync: vsync) {
    _controller.addStatusListener(_onStatus);
  }

  final AnimationController _controller;

  /// Progress of the running plan, from 0 to 1.
  late final CurvedAnimation progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  late final CurvedAnimation _fadeOutCurve = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.6, curve: Curves.easeOut),
  );

  /// Opacity of captured pieces: gone in the first 60% of the move, so
  /// they don't overlap the arriving piece half-transparently.
  late final Animation<double> fadeOut = ReverseAnimation(_fadeOutCurve);

  /// Opacity of pieces coming back, such as a capture taken back: they
  /// appear in the last 60%, once the piece that took them has moved off.
  late final CurvedAnimation fadeIn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.4, 1, curve: Curves.easeIn),
  );

  /// The running plan, or null.
  MovePlan? get plan => _plan;
  MovePlan? _plan;

  /// Squares the pieces layer must not draw while the plan runs.
  Set<Square> get hiddenSquares => _plan?.animatedSquares ?? const {};

  /// Whether a plan is running.
  bool get isAnimating => _plan != null;

  /// Plays [plan] over [duration]. A zero duration, or an empty plan, ends
  /// any running animation and shows the final position at once.
  void play(MovePlan plan, Duration duration) {
    finish();
    if (plan.isEmpty || duration == Duration.zero) return;
    _plan = plan;
    _controller
      ..duration = duration
      ..forward(from: 0);
    notifyListeners();
  }

  /// Ends the running animation and shows the final position.
  void finish() {
    if (_plan == null) return;
    _plan = null;
    _controller.stop();
    _controller.value = 0;
    notifyListeners();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) finish();
  }

  @override
  void dispose() {
    progress.dispose();
    _fadeOutCurve.dispose();
    fadeIn.dispose();
    _controller.dispose();
    super.dispose();
  }
}

/// Draws the pieces of the running animation: sliding pieces and captured
/// pieces fading out. Takes no input.
class MoveAnimationLayer extends StatelessWidget {
  /// Creates the layer.
  const MoveAnimationLayer({
    super.key,
    required this.animator,
    required this.geometry,
    required this.pieceSet,
    this.flip,
    this.flipClockwise = true,
  });

  /// Progress of a board flip, so a move made mid-flip turns with the
  /// other pieces. Null or 1 when not flipping.
  final Animation<double>? flip;

  /// Which way the board turns during [flip].
  final bool flipClockwise;

  /// The animator to follow.
  final MoveAnimator animator;

  /// Where squares are.
  final BoardGeometry geometry;

  /// The artwork, or null while loading.
  final PieceSet? pieceSet;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      // The outer builder follows the plan starting and ending; only while
      // one runs does the inner one follow every frame (and the flip).
      child: ListenableBuilder(
        listenable: animator,
        builder: (context, _) => animator.plan == null || pieceSet == null
            ? const SizedBox.expand()
            : _frames(),
      ),
    ),
  );

  Widget _frames() => ListenableBuilder(
    listenable: Listenable.merge([animator.progress, ?flip]),
    builder: (context, _) {
      final plan = animator.plan;
      final set = pieceSet;
      if (plan == null || set == null) return const SizedBox.expand();
      final t = animator.progress.value;
      final size = geometry.squareSize;
      final turn = flip?.value ?? 1;
      // A square, or a point between squares, as drawn mid-flip.
      Rect at(Offset center) => Rect.fromCenter(
        center: geometry.flipPoint(center, turn, clockwise: flipClockwise),
        width: size,
        height: size,
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          // Captured pieces fade under the arriving piece.
          for (final fade in plan.fading)
            Positioned.fromRect(
              rect: at(geometry.squareCenter(fade.square)),
              child: FadeTransition(
                opacity: animator.fadeOut,
                child: ChessPieceView(
                  piece: fade.piece,
                  size: size,
                  pieceSet: set,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          // Pieces coming back, such as a capture being taken back.
          for (final appear in plan.appearing)
            Positioned.fromRect(
              rect: at(geometry.squareCenter(appear.square)),
              child: FadeTransition(
                opacity: animator.fadeIn,
                child: ChessPieceView(
                  piece: appear.piece,
                  size: size,
                  pieceSet: set,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          for (final slide in plan.moving)
            Positioned.fromRect(
              rect: at(
                Offset.lerp(
                  geometry.squareCenter(slide.from),
                  geometry.squareCenter(slide.to),
                  t,
                )!,
              ),
              child: ChessPieceView(
                piece: slide.piece,
                size: size,
                pieceSet: set,
                excludeFromSemantics: true,
              ),
            ),
        ],
      );
    },
  );
}

/// The duration to animate with: [requested], or zero when the platform
/// asks for reduced motion.
Duration effectiveAnimationDuration(BuildContext context, Duration requested) {
  final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return reduce ? Duration.zero : requested;
}
