import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 12 piece codes the default piece set must ship.
const _codes = [
  'wK', 'wQ', 'wR', 'wB', 'wN', 'wP', //
  'bK', 'bQ', 'bR', 'bB', 'bN', 'bP',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Apps load package assets under the `packages/<name>/` prefix. This
  // test runs from a consuming app, so it proves that path works.
  for (final code in _codes) {
    test('$code.svg loads from a consuming app', () async {
      final source = await rootBundle.loadString(
        'packages/modern_chess_board/assets/pieces/default/$code.svg',
      );
      expect(source, contains('<svg'));
    });
  }
}
