// The 64 square constants are self-describing, so they are exempt from doc
// comments. Every other member is documented.
// ignore_for_file: public_member_api_docs

/// One of the 64 squares of a chess board.
///
/// Squares are ordered a1, b1, ... h1, a2, ... h8, so [index] is
/// `rank * 8 + file`. Use [Square.tryParse] for names that come from user
/// input or app data; it returns null instead of throwing.
enum Square {
  // Listed in rank-major order so `index == rank * 8 + file`.
  // dart format off
  a1, b1, c1, d1, e1, f1, g1, h1,
  a2, b2, c2, d2, e2, f2, g2, h2,
  a3, b3, c3, d3, e3, f3, g3, h3,
  a4, b4, c4, d4, e4, f4, g4, h4,
  a5, b5, c5, d5, e5, f5, g5, h5,
  a6, b6, c6, d6, e6, f6, g6, h6,
  a7, b7, c7, d7, e7, f7, g7, h7,
  a8, b8, c8, d8, e8, f8, g8, h8;
  // dart format on

  /// File from 0 (a) to 7 (h).
  int get file => index % 8;

  /// Rank from 0 (rank 1) to 7 (rank 8).
  int get rank => index ~/ 8;

  /// Whether this is a light square. a1 is dark.
  bool get isLight => (file + rank).isOdd;

  /// The file letter, `a` to `h`.
  String get fileName => String.fromCharCode(_a + file);

  /// The rank digit, `1` to `8`.
  String get rankName => '${rank + 1}';

  /// The square at [file] and [rank], both 0 to 7.
  ///
  /// Throws a [RangeError] when either is out of range.
  static Square at(int file, int rank) {
    RangeError.checkValueInInterval(file, 0, 7, 'file');
    RangeError.checkValueInInterval(rank, 0, 7, 'rank');
    return values[rank * 8 + file];
  }

  /// Parses an algebraic name such as `e4` (case-insensitive).
  ///
  /// Throws a [FormatException] for anything else.
  static Square parse(String name) {
    final square = tryParse(name);
    if (square == null) {
      throw FormatException('Not a square name', name);
    }
    return square;
  }

  /// Parses an algebraic name such as `e4` (case-insensitive), returning
  /// null for null, empty or malformed input.
  static Square? tryParse(String? name) {
    if (name == null || name.length != 2) return null;
    // Compare ASCII code units directly so look-alike Unicode letters
    // never match. `| 0x20` lower-cases ASCII letters only.
    final c = name.codeUnitAt(0);
    if (c > 0x7f) return null;
    final f = (c | 0x20) - _a;
    final r = name.codeUnitAt(1) - _one;
    if (f < 0 || f > 7 || r < 0 || r > 7) return null;
    return values[r * 8 + f];
  }

  @override
  String toString() => name;
}

const int _a = 0x61; // 'a'
const int _one = 0x31; // '1'
