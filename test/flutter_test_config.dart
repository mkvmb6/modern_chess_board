import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads Roboto (bundled with Flutter's material fonts, copied into
/// test/fonts) as the default test font, so goldens show real glyphs
/// instead of the box-shaped FlutterTest font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('Roboto');
  for (final file in [
    'test/fonts/roboto-medium.ttf',
    'test/fonts/roboto-bold.ttf',
  ]) {
    final bytes = File(file).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  await testMain();
}
