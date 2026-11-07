import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'color_math.dart';

/// The four colors for arrows and circles the user draws on the board.
///
/// Matching common chess sites, the color depends on the modifier keys held
/// while drawing: none for [plain], Shift for [shift], Alt for [alt], and
/// Shift+Alt for [shiftAlt].
@immutable
class AnnotationColors {
  /// Creates a set of annotation colors.
  const AnnotationColors({
    this.plain = const Color(0xCC15781B),
    this.shift = const Color(0xCC882020),
    this.alt = const Color(0xCC003088),
    this.shiftAlt = const Color(0xCCE6C200),
  });

  /// Color with no modifier keys held (green by default).
  final Color plain;

  /// Color with Shift held (red by default).
  final Color shift;

  /// Color with Alt held (blue by default).
  final Color alt;

  /// Color with Shift and Alt held (yellow by default).
  final Color shiftAlt;

  /// All four colors, in the order plain, shift, alt, shiftAlt.
  List<Color> get all => [plain, shift, alt, shiftAlt];

  /// Returns a copy with the given colors replaced.
  AnnotationColors copyWith({
    Color? plain,
    Color? shift,
    Color? alt,
    Color? shiftAlt,
  }) => AnnotationColors(
    plain: plain ?? this.plain,
    shift: shift ?? this.shift,
    alt: alt ?? this.alt,
    shiftAlt: shiftAlt ?? this.shiftAlt,
  );

  @override
  bool operator ==(Object other) =>
      other is AnnotationColors &&
      other.plain == plain &&
      other.shift == shift &&
      other.alt == alt &&
      other.shiftAlt == shiftAlt;

  @override
  int get hashCode => Object.hash(plain, shift, alt, shiftAlt);
}

/// Every color the chess board paints.
///
/// Use one of the presets ([green], [brown], [blue], [purple],
/// [monochrome]) or build your own. Only the two square colors are
/// required; every other color has a default tuned to stay visible on a
/// wide range of boards. Every preset is tested to keep markers,
/// highlights, arrows and labels visible on both square colors.
///
/// ```dart
/// ChessBoard(
///   controller: controller,
///   theme: ChessBoardTheme.brown.copyWith(checkColor: Colors.red),
/// )
/// ```
///
/// Themes are immutable and compare by value.
@immutable
class ChessBoardTheme {
  /// Creates a theme. Only the square colors are required.
  const ChessBoardTheme({
    required this.lightSquareColor,
    required this.darkSquareColor,
    this.selectionColor = const Color(0x8014551E),
    this.lastMoveColor = const Color(0x80FFFF00),
    this.legalMoveColor = const Color(0x47000000),
    this.hoverColor = const Color(0x1F000000),
    this.labelColor,
    this.checkmateColor = const Color(0xB3E53935),
    this.checkColor,
    this.arrowColor = const Color(0xCCFFAA00),
    this.markColor = const Color(0xCCFFAA00),
    this.hintArrowColor = const Color(0xD90D47A1),
    this.dragLegalColor = const Color(0x9914551E),
    this.dragIllegalColor = const Color(0x99E53935),
    this.premoveColor = const Color(0x806A1B9A),
    this.focusColor = const Color(0xFF0D47A1),
    this.annotationColors = const AnnotationColors(),
    this.marginColor,
    this.marginLabelColor,
    this.promotionBackgroundColor = const Color(0xFFFAFAFA),
    this.promotionScrimColor = const Color(0x66000000),
  });

  /// Light squares.
  final Color lightSquareColor;

  /// Dark squares.
  final Color darkSquareColor;

  /// Tint on the square of the selected piece.
  final Color selectionColor;

  /// Tint on the from and to squares of the last move.
  final Color lastMoveColor;

  /// Dots on empty legal destinations and rings on legal captures.
  final Color legalMoveColor;

  /// Subtle tint under the mouse on a legal destination (desktop and web).
  final Color hoverColor;

  /// Coordinate labels inside the board. When null, each label uses a color
  /// that contrasts with the square it sits on; see [labelColorOn].
  final Color? labelColor;

  /// Tint on the checkmated king's square.
  final Color checkmateColor;

  /// Tint on the square of a king in check. Null (the default) turns the
  /// check highlight off. `Color(0x99E53935)` is a good choice.
  final Color? checkColor;

  /// Default color for annotation arrows from the app.
  final Color arrowColor;

  /// Default color for square marks (circles and fills) from the app.
  final Color markColor;

  /// The suggestion (hint) arrow.
  final Color hintArrowColor;

  /// Frame on the square under a dragged piece when the drop is legal.
  final Color dragLegalColor;

  /// Tint on the square under a dragged piece when the drop is illegal.
  final Color dragIllegalColor;

  /// Tint on the from and to squares of a queued premove.
  final Color premoveColor;

  /// Keyboard focus ring.
  final Color focusColor;

  /// Colors for arrows and circles drawn by the user.
  final AnnotationColors annotationColors;

  /// Background of the label margin in outside coordinate mode. When null,
  /// the margin is transparent and shows whatever is behind the board.
  final Color? marginColor;

  /// Labels in the outside coordinate margin. When null, see
  /// [marginLabelColorOn].
  final Color? marginLabelColor;

  /// Background behind the pieces in the promotion picker.
  final Color promotionBackgroundColor;

  /// Dimming laid over the board while the promotion picker is open.
  final Color promotionScrimColor;

  /// The classic green board, used by default.
  static const green = ChessBoardTheme(
    lightSquareColor: Color(0xFFEEEED2),
    darkSquareColor: Color(0xFF769656),
  );

  /// Warm brown, like a wooden board.
  static const brown = ChessBoardTheme(
    lightSquareColor: Color(0xFFF0D9B5),
    darkSquareColor: Color(0xFFB58863),
  );

  /// Cool blue-gray.
  static const blue = ChessBoardTheme(
    lightSquareColor: Color(0xFFDEE3E6),
    darkSquareColor: Color(0xFF8CA2AD),
  );

  /// Soft purple. The hint arrow is teal here, because blue blends into the
  /// violet dark squares.
  static const purple = ChessBoardTheme(
    lightSquareColor: Color(0xFFF0F1F0),
    darkSquareColor: Color(0xFF8476BA),
    hintArrowColor: Color(0xCC00897B),
  );

  /// Grayscale squares. The last move is a neutral gray tint to match;
  /// selection, check, hints and drag feedback keep their colors so they
  /// stay easy to tell apart.
  static const monochrome = ChessBoardTheme(
    lightSquareColor: Color(0xFFE9E9E9),
    darkSquareColor: Color(0xFF9B9B9B),
    lastMoveColor: Color(0x47000000),
  );

  /// The theme used when none is given: [green].
  static const defaultTheme = green;

  /// All presets in a stable order, for theme pickers.
  static const List<ChessBoardTheme> presets = [
    green,
    brown,
    blue,
    purple,
    monochrome,
  ];

  /// The label color for a light or dark square in inside coordinate mode.
  ///
  /// Returns [labelColor] when set. Otherwise uses the opposite square's
  /// color, the common chess-site look, made a little lighter or darker if
  /// needed so it reaches a contrast ratio of at least 3 against the square.
  Color labelColorOn({required bool lightSquare}) {
    if (labelColor case final c?) return c;
    final square = lightSquare ? lightSquareColor : darkSquareColor;
    final opposite = lightSquare ? darkSquareColor : lightSquareColor;
    return readableOn(square, opposite);
  }

  /// The label color in outside coordinate mode, where [behind] is the
  /// opaque color behind the board.
  ///
  /// Returns [marginLabelColor] when set. Otherwise uses the dark square
  /// color, made readable against the margin ([marginColor] over [behind]).
  Color marginLabelColorOn(Color behind) {
    if (marginLabelColor case final c?) return c;
    final background = over(marginColor ?? const Color(0x00000000), behind);
    return readableOn(background, darkSquareColor);
  }

  /// Returns a copy with the given colors replaced.
  ///
  /// [labelColor], [checkColor], [marginColor] and [marginLabelColor] are
  /// optional; set the matching `clear...` flag to unset one. A clear flag
  /// wins over a value passed in the same call.
  ChessBoardTheme copyWith({
    Color? lightSquareColor,
    Color? darkSquareColor,
    Color? selectionColor,
    Color? lastMoveColor,
    Color? legalMoveColor,
    Color? hoverColor,
    Color? labelColor,
    bool clearLabelColor = false,
    Color? checkmateColor,
    Color? checkColor,
    bool clearCheckColor = false,
    Color? arrowColor,
    Color? markColor,
    Color? hintArrowColor,
    Color? dragLegalColor,
    Color? dragIllegalColor,
    Color? premoveColor,
    Color? focusColor,
    AnnotationColors? annotationColors,
    Color? marginColor,
    bool clearMarginColor = false,
    Color? marginLabelColor,
    bool clearMarginLabelColor = false,
    Color? promotionBackgroundColor,
    Color? promotionScrimColor,
  }) => ChessBoardTheme(
    lightSquareColor: lightSquareColor ?? this.lightSquareColor,
    darkSquareColor: darkSquareColor ?? this.darkSquareColor,
    selectionColor: selectionColor ?? this.selectionColor,
    lastMoveColor: lastMoveColor ?? this.lastMoveColor,
    legalMoveColor: legalMoveColor ?? this.legalMoveColor,
    hoverColor: hoverColor ?? this.hoverColor,
    labelColor: clearLabelColor ? null : labelColor ?? this.labelColor,
    checkmateColor: checkmateColor ?? this.checkmateColor,
    checkColor: clearCheckColor ? null : checkColor ?? this.checkColor,
    arrowColor: arrowColor ?? this.arrowColor,
    markColor: markColor ?? this.markColor,
    hintArrowColor: hintArrowColor ?? this.hintArrowColor,
    dragLegalColor: dragLegalColor ?? this.dragLegalColor,
    dragIllegalColor: dragIllegalColor ?? this.dragIllegalColor,
    premoveColor: premoveColor ?? this.premoveColor,
    focusColor: focusColor ?? this.focusColor,
    annotationColors: annotationColors ?? this.annotationColors,
    marginColor: clearMarginColor ? null : marginColor ?? this.marginColor,
    marginLabelColor: clearMarginLabelColor
        ? null
        : marginLabelColor ?? this.marginLabelColor,
    promotionBackgroundColor:
        promotionBackgroundColor ?? this.promotionBackgroundColor,
    promotionScrimColor: promotionScrimColor ?? this.promotionScrimColor,
  );

  /// Interpolates between two themes, for animated theme changes.
  ///
  /// Optional colors fade from or to transparent when only one side sets
  /// them, and are null only when both sides are.
  static ChessBoardTheme lerp(ChessBoardTheme a, ChessBoardTheme b, double t) {
    if (identical(a, b)) return a;
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    Color? o(Color? x, Color? y) => Color.lerp(x, y, t);
    final ann = AnnotationColors(
      plain: c(a.annotationColors.plain, b.annotationColors.plain),
      shift: c(a.annotationColors.shift, b.annotationColors.shift),
      alt: c(a.annotationColors.alt, b.annotationColors.alt),
      shiftAlt: c(a.annotationColors.shiftAlt, b.annotationColors.shiftAlt),
    );
    return ChessBoardTheme(
      lightSquareColor: c(a.lightSquareColor, b.lightSquareColor),
      darkSquareColor: c(a.darkSquareColor, b.darkSquareColor),
      selectionColor: c(a.selectionColor, b.selectionColor),
      lastMoveColor: c(a.lastMoveColor, b.lastMoveColor),
      legalMoveColor: c(a.legalMoveColor, b.legalMoveColor),
      hoverColor: c(a.hoverColor, b.hoverColor),
      labelColor: o(a.labelColor, b.labelColor),
      checkmateColor: c(a.checkmateColor, b.checkmateColor),
      checkColor: o(a.checkColor, b.checkColor),
      arrowColor: c(a.arrowColor, b.arrowColor),
      markColor: c(a.markColor, b.markColor),
      hintArrowColor: c(a.hintArrowColor, b.hintArrowColor),
      dragLegalColor: c(a.dragLegalColor, b.dragLegalColor),
      dragIllegalColor: c(a.dragIllegalColor, b.dragIllegalColor),
      premoveColor: c(a.premoveColor, b.premoveColor),
      focusColor: c(a.focusColor, b.focusColor),
      annotationColors: ann,
      marginColor: o(a.marginColor, b.marginColor),
      marginLabelColor: o(a.marginLabelColor, b.marginLabelColor),
      promotionBackgroundColor: c(
        a.promotionBackgroundColor,
        b.promotionBackgroundColor,
      ),
      promotionScrimColor: c(a.promotionScrimColor, b.promotionScrimColor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChessBoardTheme &&
      other.lightSquareColor == lightSquareColor &&
      other.darkSquareColor == darkSquareColor &&
      other.selectionColor == selectionColor &&
      other.lastMoveColor == lastMoveColor &&
      other.legalMoveColor == legalMoveColor &&
      other.hoverColor == hoverColor &&
      other.labelColor == labelColor &&
      other.checkmateColor == checkmateColor &&
      other.checkColor == checkColor &&
      other.arrowColor == arrowColor &&
      other.markColor == markColor &&
      other.hintArrowColor == hintArrowColor &&
      other.dragLegalColor == dragLegalColor &&
      other.dragIllegalColor == dragIllegalColor &&
      other.premoveColor == premoveColor &&
      other.focusColor == focusColor &&
      other.annotationColors == annotationColors &&
      other.marginColor == marginColor &&
      other.marginLabelColor == marginLabelColor &&
      other.promotionBackgroundColor == promotionBackgroundColor &&
      other.promotionScrimColor == promotionScrimColor;

  @override
  int get hashCode => Object.hashAll([
    lightSquareColor,
    darkSquareColor,
    selectionColor,
    lastMoveColor,
    legalMoveColor,
    hoverColor,
    labelColor,
    checkmateColor,
    checkColor,
    arrowColor,
    markColor,
    hintArrowColor,
    dragLegalColor,
    dragIllegalColor,
    premoveColor,
    focusColor,
    annotationColors,
    marginColor,
    marginLabelColor,
    promotionBackgroundColor,
    promotionScrimColor,
  ]);
}
