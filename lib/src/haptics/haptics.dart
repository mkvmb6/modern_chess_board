import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Light haptic feedback for picking up and dropping pieces.
///
/// Only acts on Android and iOS, and only when [enabled]. Expected platform
/// failures, such as a device without a vibration motor or a missing
/// plugin in tests, are ignored; anything else is reported through
/// [FlutterError.reportError].
@immutable
class BoardHaptics {
  /// Creates haptics that act only when [enabled].
  const BoardHaptics({required this.enabled});

  /// Whether feedback is given.
  final bool enabled;

  bool get _active =>
      enabled &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// A short click when a piece is picked up.
  void pickUp() {
    if (_active) _guard(HapticFeedback.selectionClick());
  }

  /// A light tap when a piece is dropped and the move is made.
  void drop() {
    if (_active) _guard(HapticFeedback.lightImpact());
  }

  static void _guard(Future<void> call) {
    call.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (error is PlatformException || error is MissingPluginException) {
          return;
        }
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'modern_chess_board',
            context: ErrorDescription('while giving haptic feedback'),
          ),
        );
      },
    );
  }
}
