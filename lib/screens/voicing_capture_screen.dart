import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/note_player.dart';
import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';
import '../theory/music_theory.dart';
import '../theory/voicings.dart';
import '../widgets/piano_keyboard.dart';
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
  final TextEditingController _name = TextEditingController();
  final NotePlayer _player = NotePlayer();
  StreamSubscription<MidiNoteEvent>? _midiSub;
  QuizSettings? _settings;
  bool _noteSound = true;

  /// The root the user tapped. Null means "follow the bass" — the default
  /// tracks the lowest played note until they pick one themselves, so a
  /// root-position shape needs no tap at all.
  int? _pickedRootPc;

  static const double _keyboardOctaves = 3;

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
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _noteSound = sound;
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

  void _toggle(int midiNote) {
    final adding = !_notes.contains(midiNote);
    if (adding && _noteSound) _player.play(midiNote);
    setState(() => adding ? _notes.add(midiNote) : _notes.remove(midiNote));
  }

  void _clear() => setState(() {
        _notes.clear();
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
          '"${clash.name}" is the same voicing — ${clash.rootName} '
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
            // soft keyboard instead of shoving the name field off-screen.
            final keyboardHeight =
                (constraints.maxHeight * 0.34).clamp(110.0, 200.0);
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
                  'stay put once played — play one again to remove it.'
              : 'Tap the keys below to build the shape. Notes stay put once '
                  'tapped — tap again to remove.',
          _buildNoteReadout(),
        ),
        const SizedBox(height: 22),
        _step(
          '2',
          'Which note is the root?',
          ready
              ? 'Defaults to the lowest note. Pick any of the twelve — a '
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

  Widget _buildKeyboard(double height) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(
          height: height,
          child: RepaintBoundary(
            child: PianoKeyboard(
              lowMidi: kVoicingKeyboardLow,
              octaves: _keyboardOctaves,
              feedbackFor: (n) => _notes.contains(n)
                  ? KeyFeedback.pressed
                  : KeyFeedback.idle,
              isTargetHint: (_) => false,
              onKeyDown: _toggle,
              // Latching: the note stays on when the finger comes off.
              onKeyUp: (_) {},
            ),
          ),
        ),
      ),
    );
  }
}
