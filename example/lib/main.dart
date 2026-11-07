import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:modern_chess_board/modern_chess_board.dart';

import 'demo_state.dart';
import 'glyph_pieces.dart';
import 'score_sheet.dart';

void main() => runApp(const ExampleApp());

/// Demo app for `modern_chess_board`: a playable board with every option
/// within reach, and the game written down beside it.
class ExampleApp extends StatefulWidget {
  /// Creates the demo app.
  const ExampleApp({super.key, this.state});

  /// The demo state, for tests; a fresh one is made when null.
  final DemoState? state;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final DemoState _state = widget.state ?? DemoState();

  @override
  void dispose() {
    if (widget.state == null) _state.dispose();
    super.dispose();
  }

  /// One app theme per board theme, made once.
  final Map<ChessBoardTheme, ThemeData> _themes = {};

  /// The theme the app was last built with; the app only rebuilds when it
  /// changes, not on every move.
  late ChessBoardTheme _shownTheme = _state.theme;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
  }

  void _onState() {
    if (_state.theme != _shownTheme) {
      setState(() => _shownTheme = _state.theme);
    }
  }

  /// The room takes its color from the board: the theme's dark square,
  /// pushed far toward dark and quiet so the board stays the brightest
  /// thing on screen. Raised surfaces (sheets, menus, dialogs) step a
  /// little lighter from the same color, as dark-mode elevation should.
  ThemeData _themeFor(ChessBoardTheme board) => _themes.putIfAbsent(board, () {
    final seed = HSLColor.fromColor(board.darkSquareColor);
    final neutral = seed.saturation < 0.05;
    HSLColor tone(double lightness) => seed
        .withSaturation((seed.saturation * 0.35).clamp(0.0, 1.0))
        .withLightness(lightness);
    final background = tone(0.12).toColor();
    final scheme =
        ColorScheme.fromSeed(
          seedColor: board.darkSquareColor,
          brightness: Brightness.dark,
          // A grey board gets a grey room, with no stray hue.
          dynamicSchemeVariant: neutral
              ? DynamicSchemeVariant.monochrome
              : DynamicSchemeVariant.tonalSpot,
        ).copyWith(
          surface: background,
          surfaceDim: tone(0.10).toColor(),
          surfaceBright: tone(0.24).toColor(),
          surfaceContainerLowest: tone(0.09).toColor(),
          surfaceContainerLow: tone(0.15).toColor(),
          surfaceContainer: tone(0.17).toColor(),
          surfaceContainerHigh: tone(0.20).toColor(),
          surfaceContainerHighest: tone(0.23).toColor(),
        );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
    );
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Modern Chess Board',
    debugShowCheckedModeBanner: false,
    theme: _themeFor(_shownTheme),
    themeAnimationDuration: const Duration(milliseconds: 300),
    home: DemoPage(state: _state),
  );
}

/// The one screen of the demo.
class DemoPage extends StatelessWidget {
  /// Creates the page for [state].
  const DemoPage({super.key, required this.state});

  /// What the controls change.
  final DemoState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final board = _Board(state: state);
            // Beside the board when there is room across: any landscape
            // window, including a phone turned sideways.
            if (w >= 860 || w > h * 1.15) {
              final roomy = w >= 860 && h >= 560;
              final gap = roomy ? 24.0 : 12.0;
              return Padding(
                padding: EdgeInsets.all(gap),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: Center(child: board)),
                    SizedBox(width: roomy ? 32 : 16),
                    SizedBox(
                      width: roomy ? 360 : (w * 0.42).clamp(240.0, 360.0),
                      child: _SidePanel(state: state, compact: !roomy),
                    ),
                  ],
                ),
              );
            }
            // Stacked: the board takes the width, but leaves the panel
            // enough height for the status, the toolbar and a few moves.
            const panelMin = 200.0;
            final side = (w - 24).clamp(
              120.0,
              (h - 12 - panelMin).clamp(120.0, w),
            );
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: SizedBox.square(dimension: side, child: board),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _SidePanel(state: state, compact: true),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _Board extends StatelessWidget {
  const _Board({required this.state});

  final DemoState state;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ChessBoard(
          controller: state.controller,
          orientation: state.orientation,
          theme: state.theme,
          pieceSet: state.glyphPieces ? glyphPieceSet : PieceSet.standard,
          coordinates: state.coordinates,
          readOnly: state.readOnly,
          interactiveSide: state.interactiveSide,
          enablePremoves: state.premoves,
          autoQueen: state.autoQueen,
          enableHaptics: state.haptics,
          soundPack: ChessSoundPack.callback(state.logSound),
          enableUserAnnotations: state.drawing,
          onUserArrowsChanged: state.onUserArrows,
          onUserMarksChanged: state.onUserMarks,
          arrows: state.arrows,
          marks: state.marks,
          hint: state.hint,
          hintTimeout: const Duration(seconds: 6),
        ),
      ),
    ),
  );
}

/// The game written down, with what you can do to it.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.state, this.compact = false});

  final DemoState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = state.controller;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          Text('Modern Chess Board', style: text.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Drag or tap to move. Right-click and drag to draw arrows. '
            'With the board focused, type a move such as Nf3.',
            style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
        ],
        Semantics(
          liveRegion: true,
          child: Text(statusLine(c), style: text.titleMedium),
        ),
        const SizedBox(height: 2),
        Text(
          state.soundLog.isEmpty
              ? (compact
                    ? 'Long-press and drag to draw an arrow.'
                    : 'Each move sends one sound event; they show here.')
              : 'Sound: ${state.soundLog.first.name}',
          style: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (compact)
          _Toolbar(state: state, onOptions: () => _showOptions(context))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: state.newGame,
                icon: const Icon(Icons.restart_alt),
                label: const Text('New game'),
              ),
              OutlinedButton.icon(
                onPressed: state.canTakeBack ? state.takeBack : null,
                icon: const Icon(Icons.undo),
                label: const Text('Take back'),
              ),
              OutlinedButton.icon(
                onPressed: state.flip,
                icon: const Icon(Icons.swap_vert),
                label: const Text('Flip board'),
              ),
              OutlinedButton.icon(
                onPressed: state.canHint ? state.askForHint : null,
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('Hint'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showOptions(context),
                icon: const Icon(Icons.tune),
                label: const Text('Options'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Expanded(
          child: ScoreSheet(controller: c, showNavigation: !compact),
        ),
      ],
    );
  }

  void _showOptions(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // A light barrier, so a theme change shows on the board behind.
    barrierColor: const Color(0x33000000),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListenableBuilder(
        listenable: state,
        builder: (context, _) => OptionsSheet(state: state, scroll: scroll),
      ),
    ),
  );
}

/// One row of icon buttons for small screens: game actions and stepping
/// through moves, as on chess apps.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state, required this.onOptions});

  final DemoState state;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final c = state.controller;
    // Seven 48px targets need 336px; narrower screens tighten them, but
    // never below the 40px a finger needs.
    return LayoutBuilder(
      builder: (context, constraints) => IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: Size.square(
              (constraints.maxWidth / 7).clamp(40.0, 48.0),
            ),
            fixedSize: Size.square(
              (constraints.maxWidth / 7).clamp(40.0, 48.0),
            ),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Options',
              onPressed: onOptions,
              icon: const Icon(Icons.tune),
            ),
            IconButton(
              tooltip: 'New game',
              onPressed: state.newGame,
              icon: const Icon(Icons.restart_alt),
            ),
            IconButton(
              tooltip: 'Flip board',
              onPressed: state.flip,
              icon: const Icon(Icons.swap_vert),
            ),
            IconButton(
              tooltip: 'Take back',
              onPressed: state.canTakeBack ? state.takeBack : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Hint',
              onPressed: state.canHint ? state.askForHint : null,
              icon: const Icon(Icons.lightbulb_outline),
            ),
            IconButton(
              tooltip: 'Previous move',
              onPressed: c.canGoBack ? c.back : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next move',
              onPressed: c.canGoForward ? c.forward : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every option, grouped by what it changes.
class OptionsSheet extends StatelessWidget {
  /// Creates the sheet.
  const OptionsSheet({super.key, required this.state, this.scroll});

  /// What the options change.
  final DemoState state;

  /// The sheet's scroll controller.
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Text(
        label,
        style: text.titleSmall!.copyWith(color: scheme.primary),
      ),
    );

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        heading('Look'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (name, t) in [
                ('Green', ChessBoardTheme.green),
                ('Brown', ChessBoardTheme.brown),
                ('Blue', ChessBoardTheme.blue),
                ('Purple', ChessBoardTheme.purple),
                ('Grey', ChessBoardTheme.monochrome),
              ])
                _ThemeSwatch(
                  name: name,
                  theme: t,
                  selected: state.theme == t,
                  onTap: () => state.theme = t,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Draw pieces with font glyphs'),
          subtitle: const Text(
            'A custom piece set made with PieceSet.builder; the look '
            "depends on your system's fonts",
          ),
          value: state.glyphPieces,
          onChanged: (v) => state.glyphPieces = v,
        ),
        // The label sits above the control: three segments don't fit
        // beside a label on a phone.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coordinates', style: text.bodyLarge),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<CoordinateMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: CoordinateMode.inside,
                      label: Text('Inside'),
                    ),
                    ButtonSegment(
                      value: CoordinateMode.outside,
                      label: Text('Outside'),
                    ),
                    ButtonSegment(
                      value: CoordinateMode.none,
                      label: Text('Off'),
                    ),
                  ],
                  selected: {state.coordinates},
                  onSelectionChanged: (s) => state.coordinates = s.single,
                ),
              ),
            ],
          ),
        ),
        heading('Play'),
        ListTile(
          title: const Text('Opponent'),
          trailing: DropdownButton<Opponent>(
            value: state.opponent,
            underline: const SizedBox(),
            onChanged: (o) => state.opponent = o!,
            items: [
              for (final o in Opponent.values)
                DropdownMenuItem(value: o, child: Text(o.label)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You move', style: text.bodyLarge),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<InteractiveSide>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: InteractiveSide.both,
                      label: Text('Both'),
                    ),
                    ButtonSegment(
                      value: InteractiveSide.white,
                      label: Text('White'),
                    ),
                    ButtonSegment(
                      value: InteractiveSide.black,
                      label: Text('Black'),
                    ),
                    ButtonSegment(
                      value: InteractiveSide.none,
                      label: Text('Neither'),
                    ),
                  ],
                  selected: {state.interactiveSide},
                  onSelectionChanged: (s) => state.interactiveSide = s.single,
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('Premoves'),
          subtitle: const Text(
            'Against the opponent, queue your next move during its turn',
          ),
          value: state.premoves,
          onChanged: (v) => state.premoves = v,
        ),
        SwitchListTile(
          title: const Text('Always promote to a queen'),
          value: state.autoQueen,
          onChanged: (v) => state.autoQueen = v,
        ),
        SwitchListTile(
          title: const Text('Read-only'),
          subtitle: const Text(
            'Watch only; arrow keys still step through moves',
          ),
          value: state.readOnly,
          onChanged: (v) => state.readOnly = v,
        ),
        SwitchListTile(
          title: const Text('Haptic feedback'),
          subtitle: const Text('On phones and tablets'),
          value: state.haptics,
          onChanged: (v) => state.haptics = v,
        ),
        heading('Ideas'),
        SwitchListTile(
          title: const Text('Show sample arrows and marks'),
          subtitle: const Text(
            'An arrow for a legal move, and the centre squares marked by '
            'who holds them',
          ),
          value: state.showIdeas,
          onChanged: (v) => state.showIdeas = v,
        ),
        SwitchListTile(
          title: const Text('Let me draw arrows and circles'),
          subtitle: Text(
            'Right-click or long-press and drag; Shift, Alt and Shift+Alt '
            'pick colors. ${state.drawingsSummary}.',
          ),
          value: state.drawing,
          onChanged: (v) => state.drawing = v,
        ),
        heading('Position'),
        ListTile(
          title: const Text('Load a FEN or PGN'),
          trailing: const Icon(Icons.file_open_outlined),
          onTap: () => _load(context),
        ),
        ListTile(
          title: const Text('Copy this game as PGN'),
          trailing: const Icon(Icons.copy),
          onTap: () {
            final messenger = ScaffoldMessenger.of(context);
            Clipboard.setData(ClipboardData(text: state.controller.pgn));
            Navigator.of(context).pop();
            messenger.showSnackBar(const SnackBar(content: Text('PGN copied')));
          },
        ),
        heading('Sound events'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            state.soundLog.isEmpty
                ? 'The board sends one sound event per move. Make a move to '
                      'see them here.'
                : state.soundLog.map((e) => e.name).join(', '),
            style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Future<void> _load(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final loaded = await showDialog<bool>(
      context: context,
      builder: (context) => _LoadDialog(load: state.loadAny),
    );
    if (loaded != true) return;
    // Close the options too, so the new position (and the message) show.
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Position loaded')));
  }
}

/// A tiny two-square sample of a board theme.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.name,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final ChessBoardTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name board',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Column(
                    children: [
                      for (final row in [true, false])
                        Expanded(
                          child: Row(
                            // Without stretch, the empty squares would
                            // collapse to zero height.
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final light in [row, !row])
                                Expanded(
                                  child: ColoredBox(
                                    color: light
                                        ? theme.lightSquareColor
                                        : theme.darkSquareColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(name, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a FEN or PGN. Owns its text field's controller, so it lives as
/// long as the dialog does, including while the dialog animates away.
class _LoadDialog extends StatefulWidget {
  const _LoadDialog({required this.load});

  /// Loads the text; returns whether it could.
  final bool Function(String text) load;

  @override
  State<_LoadDialog> createState() => _LoadDialogState();
}

class _LoadDialogState extends State<_LoadDialog> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste a FEN or a PGN first.');
      return;
    }
    if (widget.load(text)) {
      Navigator.pop(context, true);
    } else {
      setState(
        () => _error =
            "This board can't read that as a FEN or a PGN. Check it and "
            'try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Load a position'),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _input,
        autofocus: true,
        minLines: 2,
        maxLines: 8,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          hintText: 'Paste a FEN, or a whole game in PGN',
          errorText: _error,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Load')),
    ],
  );
}
