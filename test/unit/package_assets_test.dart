import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 12 piece codes the default piece set must ship.
const _codes = [
  'wK', 'wQ', 'wR', 'wB', 'wN', 'wP', //
  'bK', 'bQ', 'bR', 'bB', 'bN', 'bP',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('default piece assets', () {
    for (final code in _codes) {
      test('$code.svg is bundled and compiles to a vector picture', () async {
        final source = await rootBundle.loadString(
          'assets/pieces/default/$code.svg',
        );
        expect(source, contains('<svg'));

        // Compiles through flutter_svg's loader. Rendering is verified by the
        // piece set widget tests.
        final loader = SvgStringLoader(source);
        final bytes = await loader.loadBytes(null);
        expect(bytes.lengthInBytes, greaterThan(0));
      });
    }
  });
}
