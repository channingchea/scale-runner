import 'dart:async';

import 'package:flutter/foundation.dart';

import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theory/music_theory.dart';
import '../theory/scale_running.dart';
import 'beat_debug.dart';
import 'beat_judge.dart';

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

/// Running attempts/correct tally for one scoring bucket (a key or mode).
/// Shared shape with Jam Mode's `JamTally`, imported by name into
/// [InversionRunController] as the common per-bucket scoring type.
class RunTally {
  int attempts = 0;
  int correct = 0;

  void record(bool ok) {
    attempts++;
    if (ok) correct++;
  }

  /// Accuracy fraction (0.0–1.0); 0 when never attempted.
  double get accuracy => attempts == 0 ? 0 : correct / attempts;
}

/// Performance tier by overall accuracy, shown in the session summary. Same
/// names/thresholds as Jam Mode's `JamTier`.
enum RunTier { openingAct, localLegend, internationalRecordingStar }

/// Display name for a [RunTier].
extension RunTierLabel on RunTier {
  String get label => switch (this) {
        RunTier.openingAct => 'Opening Act',
        RunTier.localLegend => 'Local Legend',
        RunTier.internationalRecordingStar => 'International Recording Star',
      };
}

/// Resolve a tier from an accuracy fraction (0.0–1.0).
///   <70%   → Opening Act
///   70–94% → Local Legend
///   95–100% → International Recording Star
/// Boundaries inclusive at 0.70 and 0.95, matching Jam Mode's `tierFor`.
RunTier runTierFor(double accuracy) {
  if (accuracy >= 0.95) return RunTier.internationalRecordingStar;
  if (accuracy >= 0.70) return RunTier.localLegend;
  return RunTier.openingAct;
}

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
///
/// A session is one full lap of [sessionKeys] distinct keys (optionally
/// repeated [repsPerKey] times each via the reps setting); it auto-ends and
/// fires [onSessionEnd] when the last key's last pass finishes, or on a
/// manual [stop].
class ScaleRunController extends ChangeNotifier {
  ScaleRunController({
    required this.chordsEnabled,
    ChordProgression? progression,
    this.increment = KeyIncrement.fifths,
    this.sevenths = false,
    this.startKeyPc = 0,
    this.beatsPerBar = 4,
    int repsPerKey = 1,
    this.onBeatMs = 70,
    this.closeMs = 150,
  })  : progression = progression ?? commonProgressions.first,
        // A 0 or negative setting shouldn't freeze the drill on one key
        // forever — floor to 1 (the "advance every pass" default).
        repsPerKey = repsPerKey < 1 ? 1 : repsPerKey,
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

  /// How many full passes to play in each key before advancing. Floored to
  /// 1 in the constructor.
  final int repsPerKey;

  /// A session is one full lap of this many distinct keys, regardless of
  /// [repsPerKey] (reps multiply passes per key, not the key count).
  static const int sessionKeys = 12;

  /// Timing thresholds (ms), injected from the global timing-difficulty
  /// setting — identical pattern to InversionRunController / JamModeController.
  final int onBeatMs;
  final int closeMs;

  /// Backward-grace window: a note struck just after the following tick can
  /// still rescue the beat that just went missed. Matches [closeMs], same as
  /// JamModeController.graceMs.
  int get graceMs => _judge.graceMs;

  /// The shared timing engine: all press-vs-beat math (latency, wrap, early
  /// detection, verdicts) lives in [BeatJudge], identical across modes.
  late final BeatJudge _judge = BeatJudge(
    msSinceBeat: () => msSinceBeat(),
    beatPeriodMs: () => beatPeriodMs(),
    latencyMs: () => inputLatencyMs,
    onBeatMs: onBeatMs,
    closeMs: closeMs,
  );

  /// Estimated input latency (ms) from key-strike to event, subtracted before
  /// judging a press. 0 for USB/on-screen taps; set to a BLE estimate by the
  /// screen when a BLE keyboard is driving the drill.
  int inputLatencyMs = 0;

  /// Recent per-press diagnostics for the on-screen overlay (see [kBeatDebug]).
  /// Empty and unused when debug is off.
  final BeatDebugLog debug = BeatDebugLog();

  // ---- Clock wiring (set by the screen, faked in tests) ------------------
  /// Milliseconds since the most recent metronome tick.
  int Function() msSinceBeat = () => 0;

  /// Beat period in milliseconds at the current tempo.
  int Function() beatPeriodMs = () => 600;

  /// Fired on every key press before judging (e.g. metronome flash).
  void Function(int midiNote)? onAnyPress;

  /// Fired once when a running/counting-in session ends (via [stop]), so the
  /// screen can snapshot stats, persist lifetime aggregates, and show a
  /// summary. Not fired when [stop] is a no-op on an already-idle controller.
  void Function()? onSessionEnd;

  // ---- Drill state ---------------------------------------------------------
  int _keyPc;
  List<RunStep> _steps = const [];
  int _stepIndex = 0;
  int _beatIndex = 0;
  RunPhase _phase = RunPhase.idle;
  int _countInRemaining = 0;

  /// Passes completed on the current key (0-based); advances to the next key
  /// once this reaches [repsPerKey].
  int _keyRepsDone = 0;

  /// Distinct keys completed so far this session.
  int _keysCompleted = 0;

  final List<NoteResult?> _results = List.filled(8, null);
  NoteResult? _pendingNext; // early hit waiting for the next tick
  bool _chordMissedThisBar = false;

  // Backward-grace: the most recently missed beat, rescuable only during the
  // single beat that follows it — including across a bar rollover, so the last
  // note of every bar gets the same second chance as beats 1-7. Adjacency is
  // tracked with [_absBeat] rather than the step index, which the rollover
  // bumps.
  int? _graceBeat;
  int? _graceAbsBeat;
  int? _graceExpectedPc;

  /// The grace beat's bar has since ended, so its slot in [_results] now
  /// belongs to the new bar: a rescue scores the stats but leaves the dots be.
  bool _graceBarRolled = false;

  /// Beats elapsed since the downbeat; unlike [_beatIndex] it never wraps.
  int _absBeat = 0;

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

  /// Chord-hold events (chords ON, leaving beat 0 with the chord correctly
  /// sounding) that judged correct. Folded into [accuracy]'s numerator
  /// alongside [notesOnBeat]/[notesClose]; chord misses are already counted
  /// via [notesJudged]/[notesMissed] above, so this avoids double-counting
  /// the denominator.
  int chordsCorrect = 0;

  /// Per-key ("C Major", …) and per-mode ("Dorian", …) weak-point tallies,
  /// accumulated across the whole session. Snapshot via [keySnapshot] /
  /// [modeSnapshot] before a reset to merge into lifetime prefs.
  final Map<String, RunTally> keyScores = {};
  final Map<String, RunTally> modeScores = {};

  // ---- Public state for the UI ---------------------------------------------
  RunPhase get phase => _phase;
  bool get running => _phase == RunPhase.running;

  /// Count-in beat number to display (1..beatsPerBar), 0 when not counting.
  int get countInBeat =>
      _phase == RunPhase.countingIn ? beatsPerBar - _countInRemaining : 0;

  /// Beats remaining before the downbeat (countdown for the numbers
  /// display): beatsPerBar down to 1, reaching 1 on the last count-in beat.
  /// 0 when not counting in.
  int get beatsUntilDownbeat =>
      _phase == RunPhase.countingIn ? _countInRemaining + 1 : 0;

  int get keyPc => _keyPc;
  String get keyLabel => '${pitchClassNames[_keyPc]} Major';
  RunStep get currentStep => _steps[_stepIndex];
  int get stepIndex => _stepIndex;
  int get stepCount => _steps.length;
  int get beatIndex => _beatIndex;
  NoteResult? resultAt(int beat) => _results[beat];
  bool get chordMissedThisBar => _chordMissedThisBar;

  /// Current rep number on this key, 1-based ("2/2" display).
  int get repIndex => _keyRepsDone + 1;

  /// The configured reps-per-key count (for "x/N" display).
  int get repsPerKeyCount => repsPerKey;

  /// Distinct keys completed so far this session.
  int get keysCompleted => _keysCompleted;

  /// Whether every chord tone is currently sounding (always true with chords
  /// off). Containment, not exact match: the run hand legitimately adds notes.
  bool get chordHeldCorrectly {
    if (!chordsEnabled) return true;
    final pcs = _held.map(pitchClassOf).toSet();
    return currentStep.chordPcs.every(pcs.contains);
  }

  /// Overall session accuracy (0.0–1.0): on-beat + close run notes + correct
  /// chord holds, out of every judged event. 0 for an empty session.
  double get accuracy {
    if (notesJudged == 0) return 0;
    return (notesOnBeat + notesClose + chordsCorrect) / notesJudged;
  }

  /// On-time fraction among correct run notes (on-beat / (on-beat + close)).
  /// Chord holds have no timing gradation, so they don't participate here.
  double get onTimeRate {
    final correct = notesOnBeat + notesClose;
    return correct == 0 ? 0 : notesOnBeat / correct;
  }

  /// Performance tier for the current overall accuracy.
  RunTier get tier => runTierFor(accuracy);

  /// The lowest-accuracy attempted key / mode this session, or null if
  /// nothing has been attempted yet. Tie-break toward the most attempts.
  MapEntry<String, RunTally>? get weakestKey => _weakest(keyScores);
  MapEntry<String, RunTally>? get weakestMode => _weakest(modeScores);

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

  /// Snapshot of the per-key / per-mode tallies as `label → (attempts,
  /// correct)` records, for merging into persisted lifetime aggregates.
  Map<String, (int, int)> get keySnapshot => _snapshot(keyScores);
  Map<String, (int, int)> get modeSnapshot => _snapshot(modeScores);

  Map<String, (int, int)> _snapshot(Map<String, RunTally> scores) => {
        for (final e in scores.entries) e.key: (e.value.attempts, e.value.correct),
      };

  /// The current bar's mode name ("Ionian", "Dorian", …), independent of key.
  String get _currentModeName => modeNames[(currentStep.degree - 1) % 7];

  /// Record one judged event (a run note or a chord hold) against the
  /// current bar's key and mode tallies.
  void _tally(bool ok) {
    (keyScores[keyLabel] ??= RunTally()).record(ok);
    (modeScores[_currentModeName] ??= RunTally()).record(ok);
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
    _absBeat = 0;
    _keyRepsDone = 0;
    _keysCompleted = 0;
    _results.fillRange(0, 8, null);
    _pendingNext = null;
    _chordMissedThisBar = false;
    _clearGrace();
    resetScores();
    notifyListeners();
  }

  void stop() {
    final wasActive = _phase != RunPhase.idle;
    _phase = RunPhase.idle;
    _results.fillRange(0, 8, null);
    _pendingNext = null;
    _clearGrace();
    notifyListeners();
    if (wasActive) onSessionEnd?.call();
  }

  /// Clear all accumulated session scores. Called on each fresh [start]; the
  /// lifetime aggregates live in prefs, not here.
  void resetScores() {
    notesJudged = 0;
    notesOnBeat = 0;
    notesClose = 0;
    notesMissed = 0;
    notesWrong = 0;
    chordsCorrect = 0;
    streak = 0;
    bestStreak = 0;
    keyScores.clear();
    modeScores.clear();
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

  /// The beat has passed: if nothing landed on it, it's a miss — and it opens
  /// a short backward-grace window in case the note comes just after the tick.
  void _settleBeat(int beat) {
    if (_results[beat] != null) return;
    debug.add('SETTLE beat=$beat MISSED (nothing landed) '
        'since=${msSinceBeat()} lat=$inputLatencyMs');
    _results[beat] = NoteResult.missed;
    notesJudged++;
    notesMissed++;
    streak = 0;
    _tally(false);
    _armGrace(beat);
  }

  void _advance() {
    // Leaving beat 0: the chord had to be sounding with degree 1. Both
    // outcomes are a judged event against this bar's key + mode.
    if (_beatIndex == 0 && chordsEnabled) {
      final held = chordHeldCorrectly;
      _tally(held);
      notesJudged++;
      if (held) {
        chordsCorrect++;
      } else {
        _chordMissedThisBar = true;
        notesMissed++;
        streak = 0;
      }
    }
    _absBeat++;
    _beatIndex++;
    if (_beatIndex >= 8) {
      // Bar complete -> next chord; past the progression -> next pass or key.
      _beatIndex = 0;
      _chordMissedThisBar = false;
      _results.fillRange(0, 8, null);
      // Grace survives the rollover (the last beat of a bar deserves the same
      // second chance), but _results has been refilled, so mark it slot-less.
      if (_graceBeat != null) _graceBarRolled = true;
      _stepIndex++;
      if (_stepIndex >= _steps.length) {
        _keyRepsDone++;
        if (_keyRepsDone < repsPerKey) {
          // Another pass of the same key before advancing.
          _stepIndex = 0;
        } else {
          _keyRepsDone = 0;
          _keysCompleted++;
          if (_keysCompleted >= sessionKeys) {
            // The 12th distinct key just finished its last bar: auto-end.
            stop();
            return;
          }
          _keyPc = KeyCycler(increment).next(_keyPc);
          _rebuildSteps();
          _stepIndex = 0;
        }
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

    // All timing math (latency subtraction, the BLE wrap case, early-for-next
    // detection) lives in the shared engine; see BeatJudge.judgePress.
    final t = _judge.judgePress();
    final early = t.early; // pending: applied at the next tick
    final offBy = t.offBy;
    final targetBeat = early ? _beatIndex + 1 : _beatIndex;
    final expectedPc = _expectedPcAt(targetBeat);

    debug.add('PRESS pc=$pc beat=$_beatIndex target=$targetBeat exp=$expectedPc '
        'since=${msSinceBeat()} lat=$inputLatencyMs off=$offBy '
        'early=$early wrap=${t.wrapped} v=${_judge.verdictFor(offBy)}');

    // Backward grace: a press that doesn't match the current beat but DOES
    // match the beat that just missed — and lands within graceMs of its
    // tick — rescues that beat as a close hit instead of leaving it a miss.
    // Only within the same bar (grace is cleared at every bar rollover), and
    // only when the rescue note isn't itself the current beat's expected
    // pitch (so an on-time correct press is never stolen by grace). A
    // wrapped press was struck before this tick — before the miss even
    // settled — so it's never a rescue; it's judged as an early hit on the
    // current beat.
    if (!early &&
        !t.wrapped &&
        _graceBeat != null &&
        _absBeat == _graceAbsBeat! + 1 &&
        pc == _graceExpectedPc &&
        pc != expectedPc &&
        _judge.withinGrace(offBy) &&
        (_graceBarRolled || _results[_graceBeat!] == NoteResult.missed)) {
      _rescueGraceBeat(midiNote, offBy);
      return;
    }

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
    switch (_judge.verdictFor(offBy)) {
      case BeatVerdict.onBeat:
        result = NoteResult.onBeat;
        notesOnBeat++;
        streak++;
      case BeatVerdict.close:
        result = NoteResult.close;
        notesClose++;
        streak++;
      case BeatVerdict.off:
        result = NoteResult.offTime;
        notesMissed++;
        streak = 0;
    }
    notesJudged++;
    if (streak > bestStreak) bestStreak = streak;
    _tally(result != NoteResult.offTime);

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

  /// A press that rescues [_graceBeat]: flips it from missed to a close or on-beat hit,
  /// restores the streak, and corrects the tally without adding a new
  /// attempt (the attempt was already recorded when it first settled missed).
  void _rescueGraceBeat(int midiNote, int offBy) {
    final beat = _graceBeat!;
    final NoteResult result = _judge.verdictFor(offBy) == BeatVerdict.onBeat
        ? NoteResult.onBeat
        : NoteResult.close;
    if (!_graceBarRolled) _results[beat] = result;
    notesMissed--;
    if (result == NoteResult.onBeat) {
      notesOnBeat++;
    } else {
      notesClose++;
    }
    streak++;
    if (streak > bestStreak) bestStreak = streak;
    keyScores[keyLabel]?.correct += 1;
    modeScores[_currentModeName]?.correct += 1;
    _flash(_correctFlash, midiNote);
    _clearGrace();
  }

  void _armGrace(int beat) {
    _graceBeat = beat;
    _graceAbsBeat = _absBeat;
    _graceExpectedPc = _expectedPcAt(beat);
    _graceBarRolled = false;
  }

  void _clearGrace() {
    _graceBeat = null;
    _graceAbsBeat = null;
    _graceExpectedPc = null;
    _graceBarRolled = false;
  }

  /// Judge a press in the final count-in window against beat 0 of bar 1.
  /// Only near-downbeat early presses count; everything else is ignored
  /// (the user is allowed to noodle during the count-in).
  void _judgeFirstDownbeatPress(int midiNote) {
    final offBy = _judge.offByBeforeNextTick();
    if (!_judge.withinGrace(offBy)) return; // not aimed at the downbeat
    if (pitchClassOf(midiNote) != currentStep.runPcs[0]) return;
    if (_pendingNext != null) return;
    final result = _judge.verdictFor(offBy) == BeatVerdict.onBeat
        ? NoteResult.onBeat
        : NoteResult.close;
    notesJudged++;
    if (result == NoteResult.onBeat) {
      notesOnBeat++;
    } else {
      notesClose++;
    }
    streak++;
    if (streak > bestStreak) bestStreak = streak;
    _tally(true);
    _flash(_correctFlash, midiNote);
    _pendingNext = result;
  }

  /// Expected run pitch class at [beat], looking across the bar line (beat 8 =
  /// beat 0 of the next step, possibly the next pass of this key or the next
  /// key entirely).
  int _expectedPcAt(int beat) {
    if (beat <= 7) return currentStep.runPcs[beat];
    final nextIndex = _stepIndex + 1;
    if (nextIndex < _steps.length) return _steps[nextIndex].runPcs[0];
    // Past the end of this pass. If another rep of the same key is coming,
    // the next note is this key's first step again, not the next key's.
    if (_keyRepsDone + 1 < repsPerKey) return _steps[0].runPcs[0];
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
