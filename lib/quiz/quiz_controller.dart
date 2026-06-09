import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../theory/music_theory.dart';
import '../midi/midi_service.dart';
import 'validators.dart';

/// Which kind of quiz is running.
enum QuizMode { scale, chord }

/// Visual state of a single keyboard key, used to drive its color/glow.
enum KeyFeedback {
  /// Default, untouched.
  idle,

  /// Currently held down (by tap or MIDI), no judgment yet.
  pressed,

  /// Played correctly as part of the answer.
  correct,

  /// Wrong note - flashes red.
  wrong,
}

/// Drives a single round of the quiz and the running session.
///
/// Holds no Flutter widgets - it is a [ChangeNotifier] the UI listens to. It
/// accepts note input from two sources that behave identically:
///   - on-screen taps  -> [pressKey] / [releaseKey]
///   - live MIDI        -> attach a [MidiService] via [bindMidi]
///
/// On a correct answer it celebrates and holds (showing a green check); the
/// next key press advances to a new random prompt. On a wrong note it flashes,
/// resets the attempt, and lets the user try again.
class QuizController extends ChangeNotifier {
  QuizController({
    required this.mode,
    List<ScaleFormula>? scales,
    List<ChordFormula>? chords,
    int? seed,
  })  : _scales = scales ?? commonScales,
        _chords = chords ?? commonChords,
        _rng = Random(seed) {
    _nextRound();
  }

  final QuizMode mode;
  final List<ScaleFormula> _scales;
  final List<ChordFormula> _chords;
  final Random _rng;

  // ---- Keyboard range ----------------------------------------------------
  // The on-screen keyboard spans two octaves starting at C3 (MIDI 48). Targets
  // are generated within the lower octave so the "+octave" top note still fits.
  static const int keyboardLowMidi = 48; // C3
  static const int keyboardOctaves = 2;
  static const int keyboardHighMidi =
      keyboardLowMidi + keyboardOctaves * 12; // exclusive-ish top C

  // ---- Current round -----------------------------------------------------
  late String promptLabel; // e.g. "G Major" or "D Minor 7th"
  late String formulaLabel; // degree notation, e.g. "1-2-b3-4-5-b6-b7"
  late int _rootMidi; // root note for this round
  late List<int> targetNotes; // the notes the user should play (in order)
  ScaleValidator? _scaleValidator;
  ChordValidator? _chordValidator;

  /// Pitch classes already played correctly this round (for highlighting).
  final Set<int> _solvedPcs = {};

  /// Notes currently held down (taps + MIDI), by MIDI number.
  final Set<int> _held = {};

  /// Keys flashing wrong, cleared after a short delay.
  final Set<int> _wrongFlash = {};

  bool _roundComplete = false;
  bool get roundComplete => _roundComplete;

  // ---- Session stats -----------------------------------------------------
  int score = 0;
  int streak = 0;
  int bestStreak = 0;
  int attempts = 0; // total rounds presented

  // ---- MIDI binding ------------------------------------------------------
  StreamSubscription<MidiNoteEvent>? _midiSub;

  /// Route a MIDI service's note events into the quiz. Tap input still works.
  void bindMidi(MidiService service) {
    _midiSub?.cancel();
    _midiSub = service.noteStream.listen((e) {
      if (e.isOn) {
        pressKey(e.note);
      } else {
        releaseKey(e.note);
      }
    });
  }

  // ---- Public key state for the UI --------------------------------------
  KeyFeedback feedbackFor(int midiNote) {
    if (_wrongFlash.contains(midiNote)) return KeyFeedback.wrong;
    if (_solvedPcs.contains(pitchClassOf(midiNote)) &&
        _isTargetPitchClass(midiNote)) {
      return KeyFeedback.correct;
    }
    if (_held.contains(midiNote)) return KeyFeedback.pressed;
    return KeyFeedback.idle;
  }

  /// Whether [midiNote]'s pitch class is part of the current target (used to
  /// show a subtle hint and to tint solved notes green).
  bool isTargetHint(int midiNote) => _isTargetPitchClass(midiNote);

  bool _isTargetPitchClass(int midiNote) {
    final pc = pitchClassOf(midiNote);
    if (mode == QuizMode.scale) {
      return _scaleValidator!.expected.contains(pc);
    }
    return _chordValidator!.expected.contains(pc);
  }

  // ---- Input handlers ----------------------------------------------------
  void pressKey(int midiNote) {
    // After a win we hold on the green check; the next press advances.
    if (_roundComplete) {
      _nextRound();
      return;
    }
    _held.add(midiNote);
    if (mode == QuizMode.scale) {
      _handleScaleNote(midiNote);
    } else {
      _handleChordNotes();
    }
    notifyListeners();
  }

  void releaseKey(int midiNote) {
    _held.remove(midiNote);
    // Releasing a key immediately clears its red flash (don't wait for the
    // timer) so lifting the offending finger resets the chord visually.
    _wrongFlash.remove(midiNote);
    if (mode == QuizMode.chord && !_roundComplete) {
      // Re-evaluate the now-smaller held set.
      _handleChordNotes();
    }
    notifyListeners();
  }

  void _handleScaleNote(int midiNote) {
    final status = _scaleValidator!.onNoteOn(midiNote);
    switch (status) {
      case ValidationStatus.inProgress:
        _solvedPcs.add(pitchClassOf(midiNote));
        break;
      case ValidationStatus.complete:
        _solvedPcs.add(pitchClassOf(midiNote));
        _win();
        break;
      case ValidationStatus.wrong:
        _flashWrong(midiNote);
        _scaleValidator!.reset();
        _solvedPcs.clear();
        _registerMiss();
        break;
    }
  }

  void _handleChordNotes() {
    final status = _chordValidator!.evaluate(_held);
    switch (status) {
      case ValidationStatus.inProgress:
        _solvedPcs
          ..clear()
          ..addAll(_held.map(pitchClassOf).where(_chordValidator!.expected.contains));
        break;
      case ValidationStatus.complete:
        _solvedPcs
          ..clear()
          ..addAll(_chordValidator!.expected);
        _win();
        break;
      case ValidationStatus.wrong:
        for (final n in _held) {
          if (!_chordValidator!.expected.contains(pitchClassOf(n))) {
            _flashWrong(n);
          }
        }
        _registerMiss();
        break;
    }
  }

  void _flashWrong(int midiNote) {
    _wrongFlash.add(midiNote);
    Timer(const Duration(milliseconds: 450), () {
      _wrongFlash.remove(midiNote);
      notifyListeners();
    });
  }

  void _registerMiss() {
    if (streak != 0) {
      streak = 0;
      notifyListeners();
    }
  }

  void _win() {
    _roundComplete = true;
    score++;
    streak++;
    if (streak > bestStreak) bestStreak = streak;
    notifyListeners();
    // Hold here on the green check; the next key press calls _nextRound.
  }

  /// Skip the current prompt without scoring (breaks the streak).
  void skip() {
    streak = 0;
    _nextRound();
  }

  void _nextRound() {
    attempts++;
    _roundComplete = false;
    _solvedPcs.clear();
    _held.clear();
    _wrongFlash.clear();

    // Pick a random root within the lower octave of the keyboard.
    _rootMidi = keyboardLowMidi + _rng.nextInt(12);

    if (mode == QuizMode.scale) {
      final scale = _scales[_rng.nextInt(_scales.length)];
      _scaleValidator = ScaleValidator.fromFormula(scale, _rootMidi);
      _chordValidator = null;
      targetNotes = scale.notesFrom(_rootMidi);
      promptLabel = '${pitchClassNames[pitchClassOf(_rootMidi)]} ${scale.name}';
      formulaLabel = scale.formula;
    } else {
      final chord = _chords[_rng.nextInt(_chords.length)];
      _chordValidator = ChordValidator.fromFormula(chord, _rootMidi);
      _scaleValidator = null;
      targetNotes = chord.notesFrom(_rootMidi);
      promptLabel = '${pitchClassNames[pitchClassOf(_rootMidi)]} ${chord.name}';
      formulaLabel = chord.formula;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _midiSub?.cancel();
    super.dispose();
  }
}
