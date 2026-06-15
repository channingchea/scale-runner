import 'dart:async';

import 'package:flutter/foundation.dart';

import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theory/music_theory.dart';
import '../theory/scale_running.dart';

/// How a run note was (or wasn't) played, per beat of the current bar.
enum NoteResult {
  /// Right pitch, within 70ms of the beat.
  onBeat,

  /// Right pitch, within 150ms of the beat.
  close,

  /// Right pitch, but more than 150ms off — a timing miss.
  offTime,

  /// Never played before the beat passed.
  missed,
}

/// Lifecycle of the drill.
enum RunPhase { idle, countingIn, running }

/// The beat-driven "brain" of the Scale Running drill.
///
/// Analogous to `QuizController` but stateful over time: the metronome's
/// beat clock drives expectations instead of discrete prompts. The screen
/// wires [onBeat] to the metronome's tick and [msSinceBeat]/[beatPeriodMs]
/// to its timing getters; tests inject fakes for all three.
///
/// Each [RunStep] is an 8-beat bar: chord + run degree 1 on beat 0, one run
/// note per beat, octave root on beat 7. Mistakes flash and break the streak
/// but the drill never rewinds — like a real practice session.
class ScaleRunController extends ChangeNotifier {
  ScaleRunController({
    required this.chordsEnabled,
    ChordProgression? progression,
    this.increment = KeyIncrement.fifths,
    this.sevenths = false,
    this.startKeyPc = 0,
    this.beatsPerBar = 4,
  })  : progression = progression ?? commonProgressions.first,
        _keyPc = startKeyPc {
    _rebuildSteps();
  }

  /// The key each fresh start begins in (user setting).
  final int startKeyPc;

  final bool chordsEnabled;
  final ChordProgression progression;
  final KeyIncrement increment;
  final bool sevenths;
  final int beatsPerBar;

  /// Timing thresholds — identical to MetronomeController.registerHit.
  static const int onBeatMs = 70;
  static const int closeMs = 150;

  // ---- Clock wiring (set by the screen, faked in tests) ------------------
  /// Milliseconds since the most recent metronome tick.
  int Function() msSinceBeat = () => 0;

  /// Beat period in milliseconds at the current tempo.
  int Function() beatPeriodMs = () => 600;

  /// Fired on every key press before judging (e.g. metronome flash).
  void Function(int midiNote)? onAnyPress;

  // ---- Drill state ---------------------------------------------------------
  int _keyPc;
  List<RunStep> _steps = const [];
  int _stepIndex = 0;
  int _beatIndex = 0;
  RunPhase _phase = RunPhase.idle;
  int _countInRemaining = 0;

  final List<NoteResult?> _results = List.filled(8, null);
  NoteResult? _pendingNext; // early hit waiting for the next tick
  bool _chordMissedThisBar = false;

  final Set<int> _held = {};
  final Set<int> _wrongFlash = {};
  final Set<int> _correctFlash = {};
  Timer? _flashTimer;

  // ---- Session stats -------------------------------------------------------
  int notesJudged = 0;
  int notesOnBeat = 0;
  int notesClose = 0;
  int notesMissed = 0; // timing misses + never-played + chord misses
  int notesWrong = 0; // wrong pitch presses
  int streak = 0;
  int bestStreak = 0;

  // ---- Public state for the UI ---------------------------------------------
  RunPhase get phase => _phase;
  bool get running => _phase == RunPhase.running;

  /// Count-in beat number to display (1..beatsPerBar), 0 when not counting.
  int get countInBeat =>
      _phase == RunPhase.countingIn ? beatsPerBar - _countInRemaining : 0;

  int get keyPc => _keyPc;
  String get keyLabel => '${pitchClassNames[_keyPc]} Major';
  RunStep get currentStep => _steps[_stepIndex];
  int get stepIndex => _stepIndex;
  int get stepCount => _steps.length;
  int get beatIndex => _beatIndex;
  NoteResult? resultAt(int beat) => _results[beat];
  bool get chordMissedThisBar => _chordMissedThisBar;

  /// Whether every chord tone is currently sounding (always true with chords
  /// off). Containment, not exact match: the run hand legitimately adds notes.
  bool get chordHeldCorrectly {
    if (!chordsEnabled) return true;
    final pcs = _held.map(pitchClassOf).toSet();
    return currentStep.chordPcs.every(pcs.contains);
  }

  // ---- Start / stop ----------------------------------------------------------
  /// Arms a 1-bar count-in; the drill begins on the following downbeat.
  /// The screen starts the metronome alongside this call.
  void start() {
    _phase = RunPhase.countingIn;
    _countInRemaining = beatsPerBar;
    _keyPc = startKeyPc; // every fresh start begins in the chosen key
    _rebuildSteps();
    _stepIndex = 0;
    _beatIndex = 0;
    _results.fillRange(0, 8, null);
    _pendingNext = null;
    _chordMissedThisBar = false;
    notifyListeners();
  }

  void stop() {
    _phase = RunPhase.idle;
    _results.fillRange(0, 8, null);
    _pendingNext = null;
    notifyListeners();
  }

  // ---- Beat clock --------------------------------------------------------------
  /// Wire this to MetronomeController.onBeat.
  void onBeat() {
    switch (_phase) {
      case RunPhase.idle:
        return;
      case RunPhase.countingIn:
        if (_countInRemaining > 0) {
          _countInRemaining--;
        } else {
          // This tick is the downbeat: beat 0 of the first bar.
          _phase = RunPhase.running;
          _applyPending();
        }
      case RunPhase.running:
        _settleBeat(_beatIndex);
        _advance();
    }
    notifyListeners();
  }

  /// The beat has passed: if nothing landed on it, it's a miss.
  void _settleBeat(int beat) {
    if (_results[beat] != null) return;
    _results[beat] = NoteResult.missed;
    notesJudged++;
    notesMissed++;
    streak = 0;
  }

  void _advance() {
    // Leaving beat 0: the chord had to be sounding with degree 1.
    if (_beatIndex == 0 && chordsEnabled && !chordHeldCorrectly) {
      _chordMissedThisBar = true;
      notesJudged++;
      notesMissed++;
      streak = 0;
    }
    _beatIndex++;
    if (_beatIndex >= 8) {
      // Bar complete -> next chord; past the progression -> next key.
      _beatIndex = 0;
      _chordMissedThisBar = false;
      _results.fillRange(0, 8, null);
      _stepIndex++;
      if (_stepIndex >= _steps.length) {
        _keyPc = KeyCycler(increment).next(_keyPc);
        _rebuildSteps();
        _stepIndex = 0;
      }
    }
    _applyPending();
  }

  void _applyPending() {
    if (_pendingNext == null) return;
    _results[_beatIndex] = _pendingNext;
    _pendingNext = null;
  }

  void _rebuildSteps() {
    final harmony = DiatonicHarmony(_keyPc, sevenths: sevenths);
    _steps = chordsEnabled
        ? harmony.expand(progression)
        : [harmony.scaleOnlyStep()];
  }

  // ---- Input (taps + MIDI, identical paths) -----------------------------------
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
    if (_phase == RunPhase.running) {
      _judgePress(midiNote);
    } else if (_phase == RunPhase.countingIn && _countInRemaining == 0) {
      // Last count-in window: an early press can still claim the downbeat.
      _judgeFirstDownbeatPress(midiNote);
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
    final period = beatPeriodMs();
    final since = msSinceBeat().clamp(0, period);

    // A press in the back half of the window is early for the NEXT beat.
    final early = since > period / 2;
    final offBy = early ? period - since : since;
    final targetBeat = early ? _beatIndex + 1 : _beatIndex;
    final expectedPc = _expectedPcAt(targetBeat);

    if (pc != expectedPc) {
      // Re-striking a held chord tone is never wrong; anything else is.
      if (!(chordsEnabled && currentStep.chordPcs.contains(pc))) {
        notesWrong++;
        streak = 0;
        _flash(_wrongFlash, midiNote);
      }
      return;
    }

    // Right pitch — judge timing. Ignore duplicates for an already-judged beat.
    final slot = early ? _pendingNext : _results[targetBeat];
    if (slot != null) return;

    final NoteResult result;
    if (offBy <= onBeatMs) {
      result = NoteResult.onBeat;
      notesOnBeat++;
      streak++;
    } else if (offBy <= closeMs) {
      result = NoteResult.close;
      notesClose++;
      streak++;
    } else {
      result = NoteResult.offTime;
      notesMissed++;
      streak = 0;
    }
    notesJudged++;
    if (streak > bestStreak) bestStreak = streak;

    if (result == NoteResult.offTime) {
      _flash(_wrongFlash, midiNote);
    } else {
      _flash(_correctFlash, midiNote);
    }
    if (early) {
      _pendingNext = result;
    } else {
      _results[targetBeat] = result;
    }
  }

  /// Judge a press in the final count-in window against beat 0 of bar 1.
  /// Only near-downbeat early presses count; everything else is ignored
  /// (the user is allowed to noodle during the count-in).
  void _judgeFirstDownbeatPress(int midiNote) {
    final period = beatPeriodMs();
    final since = msSinceBeat().clamp(0, period);
    final offBy = period - since;
    if (offBy > closeMs) return; // not aimed at the downbeat
    if (pitchClassOf(midiNote) != currentStep.runPcs[0]) return;
    if (_pendingNext != null) return;
    final result = offBy <= onBeatMs ? NoteResult.onBeat : NoteResult.close;
    notesJudged++;
    if (result == NoteResult.onBeat) {
      notesOnBeat++;
    } else {
      notesClose++;
    }
    streak++;
    if (streak > bestStreak) bestStreak = streak;
    _flash(_correctFlash, midiNote);
    _pendingNext = result;
  }

  /// Expected run pitch class at [beat], looking across the bar line (beat 8 =
  /// beat 0 of the next step, possibly in the next key).
  int _expectedPcAt(int beat) {
    if (beat <= 7) return currentStep.runPcs[beat];
    final nextIndex = _stepIndex + 1;
    if (nextIndex < _steps.length) return _steps[nextIndex].runPcs[0];
    final nextKey = KeyCycler(increment).next(_keyPc);
    final harmony = DiatonicHarmony(nextKey, sevenths: sevenths);
    final next = chordsEnabled
        ? harmony.stepFor(progression.degrees.first)
        : harmony.scaleOnlyStep();
    return next.runPcs[0];
  }

  void _flash(Set<int> set, int midiNote) {
    set.add(midiNote);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      _wrongFlash.clear();
      _correctFlash.clear();
      notifyListeners();
    });
  }

  // ---- Keyboard rendering ------------------------------------------------------
  KeyFeedback feedbackFor(int midiNote) {
    if (_wrongFlash.contains(midiNote)) return KeyFeedback.wrong;
    if (_correctFlash.contains(midiNote)) return KeyFeedback.correct;
    if (_held.contains(midiNote)) return KeyFeedback.pressed;
    return KeyFeedback.idle;
  }

  /// Hint dots: the chord tones plus the run note expected on the current
  /// beat (pitch-class based, so they show in every octave).
  bool isTargetHint(int midiNote) {
    final pc = pitchClassOf(midiNote);
    final step = currentStep;
    if (step.chordPcs.contains(pc)) return true;
    final beat = _phase == RunPhase.running ? _beatIndex : 0;
    return step.runPcs[beat] == pc;
  }

  @override
  void dispose() {
    _midiSub?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }
}
