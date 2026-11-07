import 'package:flutter/widgets.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

/// A piece set drawn with the chess symbols in Unicode, to show how an app
/// supplies its own artwork with [PieceSet.builder].
///
/// Every piece uses the filled glyph, colored white or near-black with a
/// contrasting outline, so white pieces read on light squares too. How the
/// glyphs look depends on the system's fonts (Segoe UI Symbol on Windows);
/// an app shipping this would bundle a font with the chess symbols.
final PieceSet glyphPieceSet = PieceSet.builder(_buildGlyph, id: 'glyphs');

const _glyphs = {
  PieceType.king: '♚',
  PieceType.queen: '♛',
  PieceType.rook: '♜',
  PieceType.bishop: '♝',
  PieceType.knight: '♞',
  PieceType.pawn: '♟',
};

Widget _buildGlyph(BuildContext context, Piece piece, double size) {
  final white = piece.color == PieceColor.white;
  final glyph = _glyphs[piece.type]!;
  final fontSize = size * 0.82;
  TextStyle style(Paint? foreground, Color? color) => TextStyle(
    fontSize: fontSize,
    height: 1,
    color: color,
    foreground: foreground,
    fontFamilyFallback: const ['Segoe UI Symbol', 'Noto Sans Symbols 2'],
  );
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = size * 0.05
    ..strokeJoin = StrokeJoin.round
    ..color = white ? const Color(0xFF202124) : const Color(0xFFF5F5F5);
  return SizedBox.square(
    dimension: size,
    child: Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // U+FE0E asks for the text, not the emoji, form of the glyph.
          Text('$glyph︎', style: style(outline, null)),
          Text(
            '$glyph︎',
            style: style(
              null,
              white ? const Color(0xFFFAFAFA) : const Color(0xFF202124),
            ),
          ),
        ],
      ),
    ),
  );
}
