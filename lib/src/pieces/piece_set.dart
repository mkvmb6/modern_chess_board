import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../model/piece.dart';

/// Builds the widget for [piece] at [size] logical pixels square.
typedef PieceWidgetBuilder =
    Widget Function(BuildContext context, Piece piece, double size);

/// The artwork used to draw pieces.
///
/// The package ships [standard], a set of 12 vector pieces. Apps can supply
/// their own:
///
/// * [PieceSet.svgAssets] for a folder of SVG files named `wK.svg` ...
///   `bP.svg`.
/// * [PieceSet.images] for a map of all 12 images, such as PNG assets.
/// * [PieceSet.builder] to draw pieces with any widget.
///
/// Piece sets compare by value, and [precache] loads every piece ahead of
/// time so pieces don't flicker in on first display or after the set
/// changes. The board calls it for you.
///
/// ```dart
/// // SVGs in the app: assets/pieces/neo/wK.svg ... bP.svg
/// const neo = PieceSet.svgAssets('assets/pieces/neo');
///
/// // PNGs, one per piece.
/// final pixel = PieceSet.images({
///   for (final p in Piece.values) p: AssetImage('assets/pixel/${p.code}.png'),
/// });
///
/// // Any widget, such as Unicode glyphs.
/// const glyphs = PieceSet.builder(_glyph, id: 'glyphs');
/// Widget _glyph(BuildContext context, Piece piece, double size) =>
///     Text('...', style: TextStyle(fontSize: size * 0.8));
/// ```
@immutable
abstract class PieceSet {
  /// Const constructor for subclasses.
  const PieceSet();

  /// The vector pieces bundled with this package.
  static const PieceSet standard = _SvgPieceSet(
    'assets/pieces/default',
    package: 'modern_chess_board',
  );

  /// A set of SVG files in [directory], named by piece code: `wK.svg`,
  /// `wQ.svg` ... `bP.svg`. Pass [package] when the files are bundled with
  /// a package rather than the app.
  ///
  /// The SVGs should have a square view box, and shouldn't rely on `<text>`
  /// or `currentColor`: pictures are decoded once and shared by every board.
  /// Sets with the same [directory] (ignoring a trailing `/`) and [package]
  /// are equal.
  const factory PieceSet.svgAssets(String directory, {String? package}) =
      _SvgPieceSet;

  /// A set from images for all 12 pieces.
  ///
  /// Throws an [ArgumentError] naming the missing pieces if [images] doesn't
  /// cover all 12. Sets with equal image providers are equal; `AssetImage`
  /// and `NetworkImage` compare by value.
  factory PieceSet.images(Map<Piece, ImageProvider> images) = _ImagePieceSet;

  /// A set drawn by [builder], which must return a widget [size] logical
  /// pixels square.
  ///
  /// Give an [id] so two sets made from the same artwork compare equal, for
  /// example `id: 'my-pieces'`; without one, a set only equals itself. A set
  /// without an [id] created inside a `build` method counts as a new set on
  /// every rebuild, so the board precaches it again each time; make it
  /// `const`, store it, or give it an [id].
  /// [precache] runs when the board loads the set, for builders that use
  /// images or other assets.
  const factory PieceSet.builder(
    PieceWidgetBuilder builder, {
    Object? id,
    Future<void> Function(BuildContext context)? precache,
  }) = _BuilderPieceSet;

  /// Builds the widget for [piece], [size] logical pixels square.
  ///
  /// The widget has no semantics of its own; [ChessPieceView] adds a label.
  Widget build(BuildContext context, Piece piece, double size);

  /// Loads every piece so later builds draw immediately. Safe to call more
  /// than once; later calls finish quickly.
  Future<void> precache(BuildContext context);
}

/// Shows one chess piece from a [PieceSet], with a screen-reader label such
/// as "white king".
///
/// The board uses this for every piece. Apps can use it too, for example to
/// show captured pieces in the same style.
class ChessPieceView extends StatelessWidget {
  /// Creates a piece view.
  const ChessPieceView({
    super.key,
    required this.piece,
    required this.size,
    this.pieceSet = PieceSet.standard,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  });

  /// The piece to show.
  final Piece piece;

  /// Width and height in logical pixels.
  final double size;

  /// The artwork to use.
  final PieceSet pieceSet;

  /// Overrides the default label, such as "white king".
  final String? semanticsLabel;

  /// Leaves the piece out of the semantics tree, for when a parent already
  /// describes it. The board sets this, because each square's label names
  /// its piece ("e4, white pawn").
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final art = SizedBox.square(
      dimension: size,
      child: pieceSet.build(context, piece, size),
    );
    if (excludeFromSemantics) return ExcludeSemantics(child: art);
    return Semantics(
      label: semanticsLabel ?? piece.label,
      image: true,
      excludeSemantics: true,
      child: art,
    );
  }
}

// ---------------------------------------------------------------------------
// SVG sets
// ---------------------------------------------------------------------------

/// Decoded pictures per SVG set, shared by all boards. Twelve small vector
/// pictures per set, kept for the life of the app.
final Map<_SvgPieceSet, Map<Piece, PictureInfo>> _svgPictures = {};
final Map<_SvgPieceSet, Future<void>> _svgLoads = {};

class _SvgPieceSet extends PieceSet {
  const _SvgPieceSet(this.directory, {this.package});

  final String directory;
  final String? package;

  /// [directory] without a trailing slash, so `'a/'` and `'a'` match.
  String get _dir => directory.endsWith('/')
      ? directory.substring(0, directory.length - 1)
      : directory;

  String _path(Piece piece) => '$_dir/${piece.code}.svg';

  @override
  Widget build(BuildContext context, Piece piece, double size) {
    final picture = _svgPictures[this]?[piece];
    if (picture != null) {
      return SizedBox.square(dimension: size, child: _PictureView(picture));
    }
    // Not precached yet, for example when used outside a board: let
    // flutter_svg load it. The board always precaches first.
    return SvgPicture.asset(
      _path(piece),
      package: package,
      width: size,
      height: size,
      excludeFromSemantics: true,
    );
  }

  @override
  Future<void> precache(BuildContext context) {
    if (_svgPictures.containsKey(this)) return SynchronousFuture(null);
    return _svgLoads[this] ??= () async {
      try {
        final entries = await Future.wait([
          for (final piece in Piece.values)
            vg
                .loadPicture(
                  SvgAssetLoader(_path(piece), packageName: package),
                  context.mounted ? context : null,
                )
                .then((info) => MapEntry(piece, info)),
        ]);
        _svgPictures[this] = Map.fromEntries(entries);
      } finally {
        // Drop the pending entry so a failed load can be retried.
        _svgLoads.remove(this)?.ignore();
      }
    }();
  }

  @override
  bool operator ==(Object other) =>
      other is _SvgPieceSet && other._dir == _dir && other.package == package;

  @override
  int get hashCode => Object.hash(_dir, package);

  @override
  String toString() =>
      'PieceSet.svgAssets($directory'
      '${package == null ? '' : ', package: $package'})';
}

/// Paints a decoded vector picture scaled to fit its box, keeping its
/// aspect ratio and centered (like `BoxFit.contain`). Scaling a vector
/// picture on the canvas keeps it sharp at any size and pixel density.
class _PictureView extends LeafRenderObjectWidget {
  const _PictureView(this.info);

  final PictureInfo info;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPicture(info);

  @override
  void updateRenderObject(BuildContext context, _RenderPicture renderObject) {
    renderObject.info = info;
  }
}

class _RenderPicture extends RenderBox {
  _RenderPicture(this._info);

  PictureInfo _info;
  set info(PictureInfo value) {
    if (identical(value, _info)) return;
    _info = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrainSizeAndAttemptToPreserveAspectRatio(_info.size);

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = _info.size;
    if (source.isEmpty || size.isEmpty) return;
    final scale = math.min(
      size.width / source.width,
      size.height / source.height,
    );
    final dx = (size.width - source.width * scale) / 2;
    final dy = (size.height - source.height * scale) / 2;
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx + dx, offset.dy + dy);
    canvas.scale(scale, scale);
    canvas.drawPicture(_info.picture);
    canvas.restore();
  }
}

// ---------------------------------------------------------------------------
// Image sets
// ---------------------------------------------------------------------------

class _ImagePieceSet extends PieceSet {
  _ImagePieceSet(Map<Piece, ImageProvider> images)
    : images = Map.unmodifiable(images) {
    final missing = [
      for (final piece in Piece.values)
        if (!images.containsKey(piece)) piece.code,
    ];
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'A piece set needs all 12 pieces; missing: ${missing.join(', ')}',
      );
    }
  }

  final Map<Piece, ImageProvider> images;

  @override
  Widget build(BuildContext context, Piece piece, double size) => Image(
    image: images[piece]!,
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    excludeFromSemantics: true,
  );

  @override
  Future<void> precache(BuildContext context) => Future.wait([
    for (final image in images.values) precacheImage(image, context),
  ]);

  @override
  bool operator ==(Object other) =>
      other is _ImagePieceSet && mapEquals(other.images, images);

  @override
  int get hashCode =>
      Object.hashAll([for (final piece in Piece.values) images[piece]]);
}

// ---------------------------------------------------------------------------
// Builder sets
// ---------------------------------------------------------------------------

class _BuilderPieceSet extends PieceSet {
  const _BuilderPieceSet(
    this.builder, {
    this.id,
    Future<void> Function(BuildContext context)? precache,
  }) : _precache = precache;

  final PieceWidgetBuilder builder;
  final Object? id;
  final Future<void> Function(BuildContext context)? _precache;

  @override
  Widget build(BuildContext context, Piece piece, double size) =>
      builder(context, piece, size);

  @override
  Future<void> precache(BuildContext context) =>
      _precache?.call(context) ?? SynchronousFuture(null);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return id != null && other is _BuilderPieceSet && other.id == id;
  }

  @override
  int get hashCode => id?.hashCode ?? identityHashCode(this);
}

/// For tests: forgets every decoded SVG set.
@visibleForTesting
void debugClearPieceCache() {
  for (final pictures in _svgPictures.values) {
    for (final info in pictures.values) {
      info.picture.dispose();
    }
  }
  _svgPictures.clear();
  _svgLoads.clear();
}

/// Whether [set] has every piece decoded and ready to draw.
@visibleForTesting
bool debugIsPrecached(PieceSet set) => _svgPictures.containsKey(set);
