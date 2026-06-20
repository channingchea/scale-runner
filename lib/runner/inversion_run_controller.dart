import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theory/music_theory.dart';
import '../theory/inversion_running.dart';

/// Lifecycle of the Inversion Running drill. Self-paced uses [idle]/[running];
/// tempo mode adds a [countingIn] bar before the first beat.
enum InversionPhase { idle, countingIn, running }

/// How a step's voicing was judged on its beat (tempo mode only).
enum StepResult {
  /// Voicing held within [InversionRunController.onBeatMs] of the beat.
  onBeat,

  /// Voicing held within [InversionRunController.closeMs] of the beat.
  close,

  /// Voicing not fully held when the beat passed.
  missed,
}

/// The "brain" of the Inversion Running drill.
///
/// Two pacings share one cycle engine:
///   - Self-paced (default): play the current voicing correctly to advance up
///     then down the inversion cycle. Advancement is press-driven.
///   - Tempo ([tempoMode] = true): a count-in arms the drill, then each step
///     lands on a metronome beat. On every beat the current step is settled
///     (held in time = on-beat/close, else missed) and the drill advances —
///     mistakes flash but never rewind, like Scale Running.
///
/// Validation is octave-tolerant in the upper voices but inversion-aware: the
/// full chord must sound AND its bass (lowest) note must be the inversion's
/// bass. Because every inversion shares the same pitch-class set, the bass note
/// is what distinguishes them — checking it is what makes the drill actually
/// score the inversion the player is voicing (see [currentVoicingHeld]). The
/// screen highlights the exact transposed voicing via [isTargetHint] so the
/// chord visually climbs.
///
/// Clock-agnostic: the screen wires [onBeat] to the metronome and
/// [msSinceBeat]/[beatPeriodMs] to its timing getters; tests inject fakes.
class InversionRunController extends ChangeNotifier {
  InversionRunController({
    List<ChordFormula>? chords,
    this.tempoMode = false,
    this.beatsPerBar = 4,
    int? seed,
  })  : _chords = (chords == null || chords.isEmpty) ? _defaultChords : chords,
        _rng = Random(seed) {
    _buildCycle();
  }

  /// v1 default chord set (all already in [commonChords]).
  static const List<String> defaultChordNames = [
    'Major', 'Minor', 'Major 7th', 'Minor 7th',
  ];

  static final List<ChordFormula> _defaultChords = [
    for (final f in commonChords)
      if (defaultChordNames.contains(f.name)) f,
  ];

  final List<ChordFormula> _chords;

  /// When true, the metronome drives advancement and a count-in precedes the
  /// first step. When false, the drill is self-paced (press-driven).
  final bool tempoMode;

  /// Count-in length in beats (tempo mode).
  final int beatsPerBar;

  final Random _rng;

  /// Timing thresholds — identical to MetronomeController / ScaleRunController.
  static const int onBeatMs = 70;
  static const int closeMs = 150;

  // ---- Clock wiring (set by the screen, faked in tests) ------------------
  int Function() msSinceBeat = () => 0;
  int Function() beatPeriodMs = () => 600;

  /// Fired on every key press before judging (e.g. metronome flash).
  void Function(int midiNote)? onAnyPress;

  // ---- Drill state -------------------------------------------------------
  late InversionCycle _cycle;
  int _stepIndex = 0;
  InversionPhase _phase = InversionPhase.idle;
  int _countInRemaining = 0;

  /// Per-step verdict for the current cycle (tempo mode); null = not yet judged.
  List<StepResult?> _results = const [];

  final Set<int> _held = {};
  final Set<int> _wrongFlash = {};
  final Set<int> _correctFlash = {};
  Timer? _flashTimer;

  // ---- Session stats -----------------------------------------------------
  int stepsCompleted = 0; // voicings landed correctly
  int cyclesCompleted = 0; // full up-then-down chords finished
  int notesWrong = 0; // wrong-pitch presses
  int streak = 0; // consecutive correct voicings
  int bestStreak = 0;

  // ---- Public state for the UI -------------------------------------------
  InversionPhase get phase => _phase;
  bool get running => _phase == InversionPhase.running;
  bool get countingIn => _phase == InversionPhase.countingIn;

  /// Count-in beat to display (1..beatsPerBar), 0 when not counting in.
  int get countInBeat =>
      _phase == InversionPhase.countingIn ? beatsPerBar - _countInRemaining : 0;

  InversionCycle get cycle => _cycle;
  InversionStep get currentStep => _cycle.steps[_stepIndex];
  int get stepIndex => _stepIndex;
  int get stepCount => _cycle.length;
  int get rootPc => _cycle.rootPc;

  /// Lowest key the keyboard renders this round (the transposing anchor).
  int get lowMidi => _cycle.lowMidi;

  /// "{root} {chord}", e.g. "C Major".
  String get chordLabel => _cycle.label;

  /// Bass-up degree formula of the current step's inversion, e.g. "3-5-1".
  String get formulaLabel => currentStep.formula;

  /// Step label, e.g. "1st inversion" or "Root (8va)".
  String get stepLabel => currentStep.label;

  /// Verdict for step [i] in the current cycle (tempo mode), or null.
  StepResult? resultAt(int i) =>
      (i >= 0 && i < _results.length) ? _results[i] : null;

  /// Whether the current voicing is fully sounding *as the correct inversion*.
  ///
  /// Two conditions, both octave-tolerant in the upper voices:
  ///   1. Every chord-tone pitch class is held (containment, so duplicate
  ///      octaves are fine).
  ///   2. The lowest held note's pitch class is the inversion's bass — root
  ///      position needs the root in the bass, 1st inversion the 3rd, etc.
  ///
  /// Condition 2 is what makes the drill actually score inversions: every
  /// inversion shares the same pitch-class set, so without the bass check
  /// holding root position would satisfy every step.
  bool get currentVoicingHeld {
    if (_held.isEmpty) return false;
    final pcs = _held.map(pitchClassOf).toSet();
    if (!currentStep.pitchClasses.every(pcs.contains)) return false;
    final bassPc = pitchClassOf(_held.reduce((a, b) => a < b ? a : b));
    return bassPc == currentStep.bassPc;
  }

  // ---- Start / stop ------------------------------------------------------
  void start() {
    _buildCycle();
    _resetRoundState();
    if (tempoMode) {
      _phase = InversionPhase.countingIn;
      _countInRemaining = beatsPerBar;
    } else {
      _phase = InversionPhase.running;
    }
    notifyListeners();
  }

  void stop() {
    _phase = InversionPhase.idle;
    _clearFlashes();
    notifyListeners();
  }

  void _resetRoundState() {
    _stepIndex = 0;
    _held.clear();
    _results = List.filled(_cycle.length, null);
    _clearFlashes();
  }

  /// Pick a random root (all 12) and random chord, building a fresh cycle.
  void _buildCycle() {
    final rootPc = _rng.nextInt(12);
    final chord = _chords[_rng.nextInt(_chords.length)];
    _cycle = InversionCycle(chord, rootPc);
  }

  // ---- Beat clock --------------------------------------------------------
  /// Wire to MetronomeController.onBeat. No-op in self-paced; in tempo mode it
  /// runs the count-in, then settles + advances one step per beat.
  void onBeat() {
    switch (_phase) {
      case InversionPhase.idle:
        return;
      case InversionPhase.countingIn:
        if (_countInRemaining > 0) {
          _countInRemaining--;
        } else {
          // This tick is the downbeat: step 0 begins now.
          _phase = InversionPhase.running;
        }
        notifyListeners();
      case InversionPhase.running:
        if (tempoMode) {
          _settleAndAdvance();
          notifyListeners();
        }
    }
  }

  /// Tempo mode: judge whether the current voicing was held in time, record the
  /// verdict, then advance (rolling over at the end of the cycle).
  void _settleAndAdvance() {
    final period = beatPeriodMs();
    final since = msSinceBeat().clamp(0, period);
    final offBy = since <= period ~/ 2 ? since : period - since;

    final StepResult verdict;
    if (currentVoicingHeld && offBy <= onBeatMs) {
      verdict = StepResult.onBeat;
    } else if (currentVoicingHeld && offBy <= closeMs) {
      verdict = StepResult.close;
    } else {
      verdict = StepResult.missed;
    }

    if (_stepIndex < _results.length) _results[_stepIndex] = verdict;

    if (verdict == StepResult.missed) {
      streak = 0;
    } else {
      stepsCompleted++;
      streak++;
      if (streak > bestStreak) bestStreak = streak;
    }
    _advanceStep();
  }

  // ---- Input (taps + MIDI, identical paths) ------------------------------
  StreamSubscription<MidiNoteEvent>? _midiSub;

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

  void pressKey(int midiNote) {
    onAnyPress?.call(midiNote);
    _held.add(midiNote);
    if (_phase == InversionPhase.running) {
      _judgePress(midiNote);
    }
    notifyListeners();
  }

  void releaseKey(int midiNote) {
    _held.remove(midiNote);
    _wrongFlash.remove(midiNote);
    notifyListeners();
  }

  void _judgePress(int midiNote) {
    final pc = pitchClassOf(midiNote);
    final chordPcs = currentStep.pitchClasses;

    // A press outside the chord is wrong: flash it, break the streak, don't
    // advance or rewind (mirrors ScaleRunController's forgiving philosophy).
    if (!chordPcs.contains(pc)) {
      notesWrong++;
      streak = 0;
      _flash(_wrongFlash, midiNote);
      return;
    }

    _flash(_correctFlash, midiNote);
    // Self-paced: a complete voicing advances. Tempo mode advances on the beat
    // instead, so a press only flashes (and registers the hit via onAnyPress).
    if (!tempoMode && currentVoicingHeld) {
      _advanceCorrect();
    }
  }

  /// Self-paced advance: count the voicing as correct, then move on.
  void _advanceCorrect() {
    stepsCompleted++;
    streak++;
    if (streak > bestStreak) bestStreak = streak;
    _advanceStep();
  }

  /// Move to the next step; roll over to a fresh random round at cycle end.
  void _advanceStep() {
    _stepIndex++;
    if (_stepIndex >= _cycle.length) {
      cyclesCompleted++;
      _buildCycle();
      _stepIndex = 0;
      _results = List.filled(_cycle.length, null);
      _held.clear(); // require the next round's root to be re-struck
    }
  }

  void _flash(Set<int> set, int midiNote) {
    set.add(midiNote);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 350), _clearFlashes);
  }

  void _clearFlashes() {
    _wrongFlash.clear();
    _correctFlash.clear();
    notifyListeners();
  }

  // ---- Keyboard rendering ------------------------------------------------
  KeyFeedback feedbackFor(int midiNote) {
    if (_wrongFlash.contains(midiNote)) return KeyFeedback.wrong;
    if (_correctFlash.contains(midiNote)) return KeyFeedback.correct;
    if (_held.contains(midiNote)) return KeyFeedback.pressed;
    return KeyFeedback.idle;
  }

  /// Target dots: the exact transposed voicing of the current step, so the
  /// chord visually climbs. Matched by MIDI note (not pitch class) so the dots
  /// move up the keyboard inversion by inversion.
  bool isTargetHint(int midiNote) => currentStep.notes.contains(midiNote);

  @override
  void dispose() {
    _midiSub?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }
}
