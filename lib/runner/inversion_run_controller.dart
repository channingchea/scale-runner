import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theory/music_theory.dart';
import '../theory/fretboard.dart';
import '../theory/inversion_running.dart';
import 'beat_judge.dart';
import 'scale_run_controller.dart' show RunTally, RunTier, runTierFor;

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
    this.interChordCountInBeats = 2,
    int? seed,
    this.onBeatMs = 70,
    this.closeMs = 150,
    this.instrument = Instrument.piano,
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

  /// Which surface the round is voiced for. Only affects which octave each
  /// chord tone lands in ([InversionCycle]); judging is unchanged, so scores
  /// stay comparable across instruments.
  final Instrument instrument;

  /// When true, the metronome drives advancement and a count-in precedes the
  /// first step. When false, the drill is self-paced (press-driven).
  final bool tempoMode;

  /// Count-in length in beats (tempo mode).
  final int beatsPerBar;

  /// Inter-chord count-in length in beats (tempo mode only), played at each
  /// cycle boundary so the next chord is visible before its first judged
  /// beat. Deliberately shorter than [beatsPerBar] so a full bar of pause
  /// between every chord doesn't kill the drill's continuous feel.
  final int interChordCountInBeats;

  final Random _rng;

  /// Timing thresholds (ms), injected from the global timing-difficulty
  /// setting — identical to MetronomeController / ScaleRunController.
  final int onBeatMs;
  final int closeMs;

  /// The shared timing engine: all press-vs-beat math (latency, wrap, early
  /// detection, verdicts) lives in [BeatJudge], identical across modes.
  late final BeatJudge _judge = BeatJudge(
    msSinceBeat: () => msSinceBeat(),
    beatPeriodMs: () => beatPeriodMs(),
    latencyMs: () => inputLatencyMs,
    onBeatMs: onBeatMs,
    closeMs: closeMs,
  );

  // ---- Clock wiring (set by the screen, faked in tests) ------------------
  int Function() msSinceBeat = () => 0;
  int Function() beatPeriodMs = () => 600;

  /// Input-latency correction (ms) for a BLE MIDI keyboard.
  /// Set by the screen when a BLE keyboard is driving the drill.
  int inputLatencyMs = 0;

  /// Fired on every key press before judging (e.g. metronome flash).
  void Function(int midiNote)? onAnyPress;

  // ---- Drill state -------------------------------------------------------
  late InversionCycle _cycle;
  int _stepIndex = 0;
  InversionPhase _phase = InversionPhase.idle;
  int _countInRemaining = 0;
  int _countInTotal = 0;

  /// Per-step verdict for the current cycle (tempo mode); null = not yet judged.
  List<StepResult?> _results = const [];
  int? _graceStepIndex;

  /// An early completion locked in just before the settle tick: its verdict,
  /// applied at the tick even if the voicing was released (staccato).
  StepResult? _pendingResult;

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

  /// Per-chord-type accuracy tally, accumulated across the session. Bucketed
  /// by chord name ("Major", "Minor", ...) rather than root, since the root
  /// is randomized every cycle and the chord type is the one selectable
  /// dimension in v1.
  final Map<String, RunTally> chordScores = {};

  /// Fired once when a running/counting-in session ends (via [stop]), so the
  /// screen can snapshot stats, persist lifetime aggregates, and show a
  /// summary. Not fired when [stop] is a no-op on an already-idle controller.
  void Function()? onSessionEnd;

  // ---- Public state for the UI -------------------------------------------
  InversionPhase get phase => _phase;
  bool get running => _phase == InversionPhase.running;
  bool get countingIn => _phase == InversionPhase.countingIn;

  /// Count-in beat to display (1..the active count-in's length — either
  /// [beatsPerBar] at session start or [interChordCountInBeats] at a
  /// cycle boundary), 0 when not counting in.
  int get countInBeat => _phase == InversionPhase.countingIn
      ? _countInTotal - _countInRemaining
      : 0;

  /// Beats remaining before the downbeat (countdown for the numbers
  /// display): the active count-in's length down to 1, reaching 1 on the
  /// last count-in beat. 0 when not counting in.
  int get beatsUntilDownbeat => _phase == InversionPhase.countingIn
      ? _countInTotal - (countInBeat == 0 ? 1 : countInBeat) + 1
      : 0;

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

  /// Overall session accuracy (0.0–1.0): voicings landed correctly out of
  /// voicings landed + wrong-pitch presses. 0 for an empty session.
  double get accuracy {
    final total = stepsCompleted + notesWrong;
    return total == 0 ? 0 : stepsCompleted / total;
  }

  /// Performance tier for the current overall accuracy. Same scale as
  /// Scale Running / Jam Mode.
  RunTier get tier => runTierFor(accuracy);

  /// The lowest-accuracy attempted chord type this session, or null if
  /// nothing has been attempted yet. Tie-break toward the most attempts.
  MapEntry<String, RunTally>? get weakestChord => _weakest(chordScores);

  MapEntry<String, RunTally>? _weakest(Map<String, RunTally> scores) {
    MapEntry<String, RunTally>? worst;
    for (final e in scores.entries) {
      if (e.value.attempts == 0) continue;
      if (worst == null ||
          e.value.accuracy < worst.value.accuracy ||
          (e.value.accuracy == worst.value.accuracy &&
              e.value.attempts > worst.value.attempts)) {
        worst = e;
      }
    }
    return worst;
  }

  /// Snapshot of the per-chord-type tally as `chord name → (attempts,
  /// correct)` records, for merging into persisted lifetime aggregates on stop.
  Map<String, (int, int)> get chordSnapshot => {
        for (final e in chordScores.entries)
          e.key: (e.value.attempts, e.value.correct),
      };

  /// Record one judged event (a landed voicing or a wrong-pitch press) against
  /// the current chord type's tally.
  void _tally(bool ok) {
    (chordScores[_cycle.chord.name] ??= RunTally()).record(ok);
  }

  // ---- Start / stop ------------------------------------------------------
  void start() {
    _buildCycle();
    _resetRoundState();
    resetScores();
    if (tempoMode) {
      _phase = InversionPhase.countingIn;
      _countInTotal = beatsPerBar;
      _countInRemaining = beatsPerBar;
    } else {
      _phase = InversionPhase.running;
    }
    notifyListeners();
  }

  void stop() {
    final wasActive = _phase != InversionPhase.idle;
    _phase = InversionPhase.idle;
    _clearFlashes();
    notifyListeners();
    if (wasActive) onSessionEnd?.call();
  }

  /// Clear all accumulated session scores. Called on each fresh [start]; the
  /// lifetime aggregates live in prefs, not here.
  void resetScores() {
    stepsCompleted = 0;
    cyclesCompleted = 0;
    notesWrong = 0;
    streak = 0;
    bestStreak = 0;
    chordScores.clear();
  }

  void _resetRoundState() {
    _stepIndex = 0;
    _held.clear();
    _results = List.filled(_cycle.length, null);
    _graceStepIndex = null;
    _pendingResult = null;
    _clearFlashes();
  }

  /// Pick a random root (all 12) and random chord, building a fresh cycle.
  void _buildCycle() {
    final rootPc = _rng.nextInt(12);
    final chord = _chords[_rng.nextInt(_chords.length)];
    _cycle = InversionCycle(chord, rootPc, instrument: instrument);
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

  /// Tempo mode: settle the current step at its tick. A verdict locked in by
  /// an early completion ([_pendingResult]) wins — it carries the strike's
  /// real timing and survives a release before the tick. Otherwise a voicing
  /// held through the tick is on-beat by definition (no latency math here:
  /// the tick measures state, not a press event — subtracting input latency
  /// at the tick just penalized BLE players a constant offset).
  void _settleAndAdvance() {
    final StepResult verdict;
    if (_pendingResult != null) {
      verdict = _pendingResult!;
      _pendingResult = null;
    } else if (currentVoicingHeld) {
      verdict = StepResult.onBeat;
    } else {
      verdict = StepResult.missed;
    }

    if (_stepIndex < _results.length) _results[_stepIndex] = verdict;
    _tally(verdict != StepResult.missed);

    if (verdict == StepResult.missed) {
      streak = 0;
      _graceStepIndex = _stepIndex;
    } else {
      stepsCompleted++;
      streak++;
      if (streak > bestStreak) bestStreak = streak;
      _graceStepIndex = null;
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
    final wasHeld = currentVoicingHeld;
    _held.add(midiNote);
    if (_phase == InversionPhase.running) {
      _judgePress(midiNote, wasHeld);
    }
    notifyListeners();
  }

  void releaseKey(int midiNote) {
    _held.remove(midiNote);
    _wrongFlash.remove(midiNote);
    notifyListeners();
  }

  void _judgePress(int midiNote, bool wasHeld) {
    final pc = pitchClassOf(midiNote);
    final chordPcs = currentStep.pitchClasses;

    // A press outside the chord is wrong: flash it, break the streak, don't
    // advance or rewind (mirrors ScaleRunController's forgiving philosophy).
    if (!chordPcs.contains(pc)) {
      notesWrong++;
      streak = 0;
      _tally(false);
      _flash(_wrongFlash, midiNote);
      return;
    }

    _flash(_correctFlash, midiNote);
    // Self-paced: a complete voicing advances. Tempo mode advances on the beat
    // instead, so a press only flashes (and registers the hit via onAnyPress).
    if (!tempoMode) {
      if (currentVoicingHeld) {
        _advanceCorrect();
      }
    } else {
      if (!wasHeld && currentVoicingHeld) {
        // The voicing just completed: judge the completing press with the
        // shared engine. A wrapped press (struck before the latest tick,
        // delivered after it — BLE lag) is just as rescuable as a late one.
        final t = _judge.judgePress();
        if (_graceStepIndex != null &&
            !t.early &&
            _judge.withinGrace(t.offBy) &&
            _results[_graceStepIndex!] == StepResult.missed) {
          // Late completion rescuing the step that just settled missed.
          _rescueGraceStep(midiNote, t.offBy);
        } else if (t.early && _judge.withinGrace(t.offBy)) {
          // Early completion just before the coming settle tick: lock in its
          // verdict now so a release before the tick (staccato) still scores.
          _pendingResult = _judge.verdictFor(t.offBy) == BeatVerdict.onBeat
              ? StepResult.onBeat
              : StepResult.close;
        }
      }
    }
  }

  void _rescueGraceStep(int midiNote, int offBy) {
    final step = _graceStepIndex!;
    final StepResult verdict = _judge.verdictFor(offBy) == BeatVerdict.onBeat
        ? StepResult.onBeat
        : StepResult.close;
    _results[step] = verdict;
    
    streak++;
    if (streak > bestStreak) bestStreak = streak;
    stepsCompleted++;
    chordScores[_cycle.chord.name]?.correct += 1;
    _graceStepIndex = null;
    _flash(_correctFlash, midiNote);
  }

  /// Self-paced advance: count the voicing as correct, then move on.
  void _advanceCorrect() {
    stepsCompleted++;
    streak++;
    if (streak > bestStreak) bestStreak = streak;
    _tally(true);
    _advanceStep();
  }

  /// Move to the next step; roll over to a fresh random round at cycle end.
  /// Tempo mode drops into a short inter-chord count-in at the boundary so
  /// the new chord is on screen before its first judged beat; self-paced
  /// rolls over instantly, unchanged.
  void _advanceStep() {
    _stepIndex++;
    if (_stepIndex >= _cycle.length) {
      cyclesCompleted++;
      _buildCycle();
      _stepIndex = 0;
      _results = List.filled(_cycle.length, null);
      _held.clear(); // require the next round's root to be re-struck
      if (tempoMode) {
        _phase = InversionPhase.countingIn;
        _countInTotal = interChordCountInBeats;
        _countInRemaining = interChordCountInBeats;
      }
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
