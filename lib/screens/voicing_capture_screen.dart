import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/note_player.dart';
import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';
import '../theory/fretboard.dart';
import '../theory/music_theory.dart';
import '../theory/voicings.dart';
import '../ui/responsive.dart';
import '../widgets/fretboard_view.dart' show FretboardLabels, TwinDotMode;
import '../widgets/instrument_surface.dart';
import '../widgets/rotate_hint_banner.dart';

/// Build one voicing — play the shape, say which note is its root, name it.
/// Doubles as the edit screen.
///
/// Notes **latch**: a tap or a MIDI note-on toggles a key on, and the shape
/// stays put when you let go, so you can build a voicing bigger than your hand
/// and take as long as you like over it. Playing the same note again removes
/// it.
///
/// Pops the finished [VoicingSpec], or null on cancel. Saving belongs to the
/// collection screen, so this screen never touches storage.
class VoicingCaptureScreen extends StatefulWidget {
  const VoicingCaptureScreen({
    super.key,
    required this.midi,
    this.existing,
    this.others = const [],
  });

  final MidiService midi;

  /// The voicing being edited, or null when building a new one.
  final VoicingSpec? existing;

  /// The rest of the collection — read only to warn about a duplicate shape.
  final List<VoicingSpec> others;

  @override
  State<VoicingCaptureScreen> createState() => _VoicingCaptureScreenState();
}

class _VoicingCaptureScreenState extends State<VoicingCaptureScreen> {
  final Set<int> _notes = {};

  /// The shape as cells, on guitar. A tapped note has to stay on the string
  /// it was tapped on, and a MIDI number cannot say which that was — inside a
  /// five-fret box a note can sit on two strings at once. [_notes] is derived
  /// from this whenever it changes, so everything downstream (the readout,
  /// the formula, the save) is unchanged.
  final Set<FretPosition> _cells = {};

  /// The window on the neck. Drills slide theirs to follow the round; capture
  /// has no round to follow, so it opens at the nut and the player moves it.
  FretBox _box = const FretBox(0);

  final TextEditingController _name = TextEditingController();
  final NotePlayer _player = NotePlayer();
  StreamSubscription<MidiNoteEvent>? _midiSub;
  QuizSettings? _settings;
  bool _noteSound = true;
  Instrument _instrument = Instrument.piano;
  bool _leftHanded = false;
  TwinDotMode _twinMode = TwinDotMode.primaryAndGhost;
  FretboardLabels _fretLabels = const FretboardLabels();

  /// The root the user tapped. Null means "follow the bass" — the default
  /// tracks the lowest played note until they pick one themselves, so a
  /// root-position shape needs no tap at all.
  int? _pickedRootPc;

  static const double _keyboardOctaves = 3;

  /// Room for the fret-window control above a portrait guitar board.
  static const double _boxSliderHeight = 36;

  /// Room for the same control standing beside a landscape neck. A neck lying
  /// flat is already short — spending 36 of its ~164 points on a row above it
  /// left barely 12 points per string — so there it goes down the left edge,
  /// outside the board, alongside the string letters.
  static const double _boxStepperWidth = 46;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    final existing = widget.existing;
    if (existing != null) {
      _notes.addAll(existing.playableNotes());
      _pickedRootPc = existing.rootPc;
      _name.text = existing.name;
    }
    _midiSub = widget.midi.noteStream.listen((e) {
      if (e.isOn) _toggle(e.note);
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final settings = await QuizSettings.load();
    final sound = await settings.noteSoundEnabled();
    final instrument = await settings.instrument();
    final leftHanded = await settings.leftHanded();
    final twinMode = await settings.guitarTwinMode();
    final fretLabels = await settings.fretboardLabels();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _noteSound = sound;
      _instrument = instrument;
      _leftHanded = leftHanded;
      _twinMode = twinMode;
      _fretLabels = fretLabels;
      // The instrument arrives after initState has loaded any existing
      // shape, so the neck is seeded here rather than there.
      _seedCells();
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _midiSub?.cancel();
    _name.dispose();
    _player.dispose();
    super.dispose();
  }

  // ---- Shape state -------------------------------------------------------

  List<int> get _sorted => [..._notes]..sort();

  int get _rootPc => _pickedRootPc ?? (_notes.isEmpty ? 0 : _sorted.first % 12);

  List<int> get _offsets => offsetsFrom(_sorted, _rootPc);

  /// Two notes is the floor — one note isn't a voicing, it's a note.
  bool get _canSave => _notes.length >= 2 && _name.text.trim().isNotEmpty;

  bool get _onGuitar => _instrument == Instrument.guitar;

  /// Put an already-saved shape on the neck when the screen opens on guitar.
  /// Nothing to do when it cannot be held — the board simply starts empty and
  /// the piano readout below still shows what the voicing is.
  void _seedCells() {
    if (!_onGuitar || _notes.isEmpty) return;
    final shape = fit(_sorted);
    if (shape == null) return;
    _cells
      ..clear()
      ..addAll(shape.positions);
    _box = shape.box();
    _syncNotes();
  }

  void _syncNotes() => _notes
    ..clear()
    ..addAll(_cells.map((c) => c.midi()));

  /// One note per string: a second tap on a string moves that string's note
  /// rather than stacking on it, and tapping a lit cell takes it off. This is
  /// what makes a captured guitar shape playable by construction — six
  /// strings, one finger each, inside a five-fret window.
  void _tapCell(FretPosition cell) {
    final removing = _cells.contains(cell);
    if (!removing && _noteSound) _player.play(cell.midi());
    setState(() {
      if (removing) {
        _cells.remove(cell);
      } else {
        _cells.removeWhere((c) => c.string == cell.string);
        _cells.add(cell);
      }
      _syncNotes();
    });
  }

  void _slideBox(int by) => setState(() {
        _box = FretBox(
          (_box.start + by).clamp(0, kMaxFret - _box.width + 1),
          _box.width,
        );
      });

  void _toggle(int midiNote) {
    // A note arriving over MIDI has no cell of its own, so on guitar it takes
    // the one the board would light for it. Out of the window it is dropped:
    // capture cannot hold a shape it is not showing.
    if (_onGuitar) {
      final cell = primaryFor(midiNote, _box);
      if (cell != null) _tapCell(cell);
      return;
    }
    final adding = !_notes.contains(midiNote);
    if (adding && _noteSound) _player.play(midiNote);
    setState(() => adding ? _notes.add(midiNote) : _notes.remove(midiNote));
  }

  void _clear() => setState(() {
        _notes.clear();
        _cells.clear();
        _pickedRootPc = null;
      });

  // ---- Save --------------------------------------------------------------

  Future<void> _save() async {
    final name = _name.text.trim();
    final existing = widget.existing;
    final spec = existing == null
        ? VoicingSpec.fromNotes(name: name, rootPc: _rootPc, notes: _sorted)
        : existing.copyWith(name: name, rootPc: _rootPc, offsets: _offsets);

    VoicingSpec? clash;
    for (final other in widget.others) {
      if (other.id != spec.id && other.sameShapeAs(spec)) {
        clash = other;
        break;
      }
    }
    if (clash != null && !await _confirmDuplicate(clash)) return;
    if (!mounted) return;
    Navigator.of(context).pop(spec);
  }

  /// A warning, never a block — two names for one shape is a legitimate thing
  /// to want, and the user knows their own practice better than we do.
  Future<bool> _confirmDuplicate(VoicingSpec clash) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('You already have this shape'),
        content: Text(
          '"${clash.name}" is the same voicing: ${clash.rootName} '
          '${clash.formula}. Save this one as well?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit voicing' : 'New voicing'),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Proportional rather than fixed so the keyboard shrinks with the
            // soft keyboard instead of shoving the name field off-screen —
            // guitar's portrait box gets a bigger share for the same reason
            // the drill screens do: a bigger cell is easier to tap.
            final compact = isCompactLayout(MediaQuery.of(context).size.height);
            final keyboardHeight = _instrument == Instrument.guitar && !compact
                ? (constraints.maxHeight * 0.58)
                    .clamp(260.0, constraints.maxHeight * 0.75)
                : (constraints.maxHeight * 0.34).clamp(110.0, 200.0);
            return Column(
              children: [
                if (_settings != null) RotateHintBanner(settings: _settings!),
                Expanded(child: _buildSteps()),
                _buildKeyboard(keyboardHeight),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSteps() {
    final ready = _notes.length >= 2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        _step(
          '1',
          'Play the voicing',
          widget.midi.isConnected
              ? 'Play the chord on your keyboard, or tap the keys below. Notes '
                  'stay put once played. Play one again to remove it.'
              : 'Tap the keys below to build the shape. Notes stay put once '
                  'tapped. Tap again to remove.',
          _buildNoteReadout(),
        ),
        const SizedBox(height: 22),
        _step(
          '2',
          'Which note is the root?',
          ready
              ? 'Defaults to the lowest note. Pick any of the twelve, since a '
                  'rootless voicing has no root in it at all.'
              : 'Play at least two notes first.',
          ready ? _buildRootChips() : const SizedBox.shrink(),
          dimmed: !ready,
        ),
        if (ready) ...[
          const SizedBox(height: 14),
          _buildFormula(),
        ],
        const SizedBox(height: 22),
        _step('3', 'Name it', 'What do you call this shape?', _buildNameField()),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _step(
    String number,
    String title,
    String subtitle,
    Widget child, {
    bool dimmed = false,
  }) {
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  number,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildNoteReadout() {
    if (_notes.isEmpty) {
      return const Text(
        'No notes yet.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final n in _sorted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: n % 12 == _rootPc
                          ? AppColors.accent2
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    noteName(n),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: _clear, child: const Text('Clear')),
      ],
    );
  }

  /// All twelve chips, always — a rootless voicing's root is by definition a
  /// note that isn't being played.
  Widget _buildRootChips() {
    final played = {for (final n in _notes) n % 12};
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var pc = 0; pc < 12; pc++)
          GestureDetector(
            onTap: () => setState(() => _pickedRootPc = pc),
            child: Container(
              width: 46,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pc == _rootPc ? AppColors.accent : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: pc == _rootPc
                      ? AppColors.accent
                      : played.contains(pc)
                          ? AppColors.accent.withValues(alpha: 0.55)
                          : AppColors.border,
                ),
              ),
              child: Text(
                pitchClassNames[pc],
                style: TextStyle(
                  color: pc == _rootPc
                      ? onAccent
                      : played.contains(pc)
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Degrees only — the user never sees a raw offset, least of all a negative
  /// one.
  Widget _buildFormula() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Text(
            'Formula, bass up',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${pitchClassNames[_rootPc]}  ${voicingFormula(_offsets)}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _name,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        if (_canSave) _save();
      },
      decoration: const InputDecoration(hintText: 'e.g. Maj7 drop 2'),
    );
  }

  /// Slide the window along the neck. The only control of its kind in the
  /// app — every drill knows which frets it wants, capture does not.
  ///
  /// [vertical] stacks it into a narrow column for the landscape neck, where
  /// there is no height to spare above the board. Up the neck is the top
  /// button either way: stacked, that is the spinner convention, and the
  /// board's own fret numbers already say which end is the nut.
  Widget _buildBoxStepper({required bool vertical}) {
    final up = IconButton(
      onPressed: _box.end >= kMaxFret ? null : () => _slideBox(1),
      icon: const Icon(Icons.add, size: 18),
      color: AppColors.textSecondary,
      tooltip: 'Up the neck',
      visualDensity: VisualDensity.compact,
    );
    final down = IconButton(
      onPressed: _box.start == 0 ? null : () => _slideBox(-1),
      icon: const Icon(Icons.remove, size: 18),
      color: AppColors.textSecondary,
      tooltip: 'Toward the nut',
      visualDensity: VisualDensity.compact,
    );
    // "Frets 0-4" does not fit a 46-point column, and beside a board that now
    // numbers its own frets the word is redundant anyway.
    final readout = Text(
      vertical ? '${_box.start}-${_box.end}' : 'Frets ${_box.start}-${_box.end}',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: vertical ? 11 : 12,
        fontFeatures: tabularFigures,
      ),
    );

    if (vertical) {
      return SizedBox(
        width: _boxStepperWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [up, readout, down],
        ),
      );
    }
    return SizedBox(
      height: _boxSliderHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [down, SizedBox(width: 74, child: readout), up],
      ),
    );
  }

  Widget _buildKeyboard(double height) {
    final compact = isCompactLayout(MediaQuery.of(context).size.height);
    // The stepper follows the board. A neck lying flat has no height to give
    // away, so there the control stands beside it and the board keeps the
    // whole allowance; a portrait box has height to spare and keeps the row
    // above, where a wider readout reads better.
    final neck = _onGuitar && (compact || isDesktopPlatform);
    final surface = RepaintBoundary(
      child: InstrumentSurface(
        instrument: _instrument,
        lowMidi: kVoicingKeyboardLow,
        octaves: _keyboardOctaves,
        anchor: _sorted,
        box: _onGuitar ? _box : null,
        latched: _onGuitar ? _cells : null,
        onCellDown: _onGuitar ? _tapCell : null,
        feedbackFor: (n) =>
            _notes.contains(n) ? KeyFeedback.pressed : KeyFeedback.idle,
        isTargetHint: (_) => false,
        onKeyDown: _toggle,
        // Latching: the note stays on when the finger comes off.
        onKeyUp: (_) {},
        compact: compact,
        leftHanded: _leftHanded,
        twinMode: _twinMode,
        labels: _fretLabels,
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: neck
            ? SizedBox(
                height: height,
                child: Row(
                  children: [
                    _buildBoxStepper(vertical: true),
                    Expanded(child: surface),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_onGuitar) _buildBoxStepper(vertical: false),
                  SizedBox(
                    height: _onGuitar ? height - _boxSliderHeight : height,
                    child: surface,
                  ),
                ],
              ),
      ),
    );
  }
}
