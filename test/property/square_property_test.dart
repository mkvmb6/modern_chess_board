import 'package:glados/glados.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

// Near-miss square characters, upper case, digits, noise, and non-ASCII
// look-alikes (accented letters, dotted I, Kelvin sign, full-width digit,
// and both halves of a surrogate pair).
const _alphabet =
    'abcdefghijxyzABCDEFGHI0123456789 -=+#éİ\u212A\uFF11\uD83D\uDE00';

void main() {
  Glados(any.stringOf(_alphabet)).test('Square.tryParse never throws', (s) {
    final result = Square.tryParse(s);
    if (result != null) {
      expect(result.name, s.toLowerCase());
    }
  });

  Glados2(any.stringOf(_alphabet), any.stringOf(_alphabet)).test(
    'Arrow with random names never throws and is valid only for two squares',
    (from, to) {
      final arrow = Arrow(from, to);
      final a = Square.tryParse(from);
      final b = Square.tryParse(to);
      expect(arrow.fromSquare, a);
      expect(arrow.toSquare, b);
      expect(arrow.isValid, a != null && b != null && a != b);
    },
  );

  Glados2(any.intInRange(0, 8), any.intInRange(0, 8)).test(
    'Square.at round-trips through its name',
    (file, rank) {
      final square = Square.at(file, rank);
      expect(Square.parse(square.name), square);
      expect(Square.parse(square.name.toUpperCase()), square);
    },
  );
}
