import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_chess_board/src/haptics/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    debugDefaultTargetPlatformOverride = null;
  });

  List<Object?> vibrations() => [
    for (final c in calls)
      if (c.method == 'HapticFeedback.vibrate') c.arguments,
  ];

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('pickup clicks and drop taps on ${platform.name}', () async {
      debugDefaultTargetPlatformOverride = platform;
      const haptics = BoardHaptics(enabled: true);
      haptics.pickUp();
      haptics.drop();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations(), [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.lightImpact',
      ]);
    });
  }

  test('nothing happens when disabled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const haptics = BoardHaptics(enabled: false);
    haptics.pickUp();
    haptics.drop();
    await Future<void>.delayed(Duration.zero);
    expect(vibrations(), isEmpty);
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.fuchsia,
  ]) {
    test('nothing happens on ${platform.name}', () async {
      debugDefaultTargetPlatformOverride = platform;
      const haptics = BoardHaptics(enabled: true);
      haptics.pickUp();
      haptics.drop();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations(), isEmpty);
    });
  }

  test('an expected platform failure is ignored silently', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          throw PlatformException(code: 'unavailable');
        });
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    const haptics = BoardHaptics(enabled: true);
    expect(haptics.pickUp, returnsNormally);
    expect(haptics.drop, returnsNormally);
    await Future<void>.delayed(Duration.zero);
    expect(reported, isEmpty);
  });

  test('a missing plugin is ignored silently', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          throw MissingPluginException();
        });
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    const BoardHaptics(enabled: true).pickUp();
    await Future<void>.delayed(Duration.zero);
    expect(reported, isEmpty);
  });
}
