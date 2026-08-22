import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../quiz/validators.dart';
import '../theory/music_theory.dart';
import '../theory/jam_mode.dart';
import 'beat_debug.dart';
import 'beat_judge.dart';

/// Lifecycle of the Jam Mode drill.
///
/// Each chord gets its own [beatsPerBar]-beat count-in during which the chord is
/// already on screen; you strike it on the downbeat that ends the count-in. The
/// metronome runs continuously, so [countingIn] and [running] are really the
/// same continuous loop. After a downbeat the controller briefly enters
/// [JamPhase.judging] — a short grace window where the *current* chord stays
/// active so a slightly-late press still scores it (rather than spilling onto
/// the next chord), before the next count-in begins. The screen treats
/// counting-in and judging alike as "active".
enum JamPhase { idle, countingIn, judging }

/// How a bar's chord was judged on its downbeat.
enum JamResult {
  /// Chord correctly held within [JamModeController.onBeatMs] of the beat.
  onBeat,

  /// Chord correctly held within [JamModeController.closeMs] of the beat.
  close,

  /// Chord wrong or not fully held when the beat passed.
  missed,
}

/// Performance tier by overall accuracy, shown in the session summary.
enum JamTier { openingAct, localLegend, internationalRecordingStar }

/// Display name for a [JamTier].
extension JamTierLabel on JamTier {
  String get label => switch (this) {
        JamTier.openingAct => 'Opening Act',
        JamTier.localLegend => 'Local Legend',
        JamTier.internationalRecordingStar => 'International Recording Star',
      };
}

/// Resolve a tier from an accuracy fraction (0.0–1.0).
///   <70%  → Opening Act
///   70–94% → Local Legend
///   95–100% → International Recording Star
JamTier tierFor(double accuracy) {
  final pct = accuracy * 100;
  if (pct >= 95) return JamTier.internationalRecordingStar;
  if (pct >= 70) return JamTier.localLegend;
  return JamTier.openingAct;
}

/// Running attempts/correct tally for one scoring bucket (a quality or degree).
class JamTally {
  int attempts = 0;
  int correct = 0;

  void record(bool ok) {
    attempts++;
    if (ok) correct++;
  }

  /// Accuracy fraction (0.0–1.0); 0 when never attempted.
  double get accuracy => attempts == 0 ? 0 : correct / attempts;
}

/// The beat-driven "brain" of the Jam Mode comping drill.
///
/// A single fixed key, one diatonic chord prompted per bar, struck on the
/// downbeat. Mirrors the tempo path of [InversionRunController]: a count-in
/// arms the drill, then on every downbeat the current prompt is judged (chord
/// correctly held = on-beat/close by timing, else missed) and the next prompt
/// is drawn — pure random, never an immediate repeat. Mistakes flash red but
/// the drill never rewinds.
///
/// Validation is octave-free via [ChordValidator]: any inversion/octave passes,
/// chord tones may be doubled, but any non-chord-tone fails. Scoring accumulates
/// by both chord quality and scale degree so weak spots surface in the summary.
///
/// Clock-agnostic: the screen wires [onBeat] to the metronome and
/// [msSinceBeat]/[beatPeriodMs] to its timing getters; tests inject fakes.
class JamModeController extends ChangeNotifier {
  JamModeController({
    this.keyPc = 0,
    Set<JamFamily>? families,
    this.beatsPerBar = 4,
    this.sessionBars = 24,
    this.freestyle = false,
    this.anyTones = false,
    int? seed,
    this.onBeatMs = 70,
    this.closeMs = 150,
  })  : families = (families == null || families.isEmpty)
            ? JamFamily.values.toSet()
            : families,
        _rng = Random(seed) {
    _rebuildPicker();
  }

  /// The fixed key (pitch class 0–11) the whole session plays in.
  final int keyPc;

  /// Enabled chord families. Never empty (the UI enforces ≥1).
  final Set<JamFamily> families;

  /// Count-in length in beats; also the bar length.
  final int beatsPerBar;

  /// Number of chords (hit-bars) in a session. The drill auto-ends and tallies
  /// once this many chords have been judged. Typically 12, 24, or 48.
  final int sessionBars;

  /// Freestyle: play any diatonic chord from an enabled family (just don't
  /// repeat the last scale degree) instead of being shown a specific chord
  /// each bar (Prompted).
  final bool freestyle;

  /// "Any chord tones": any 3+ note voicing (doubles count) built from the
  /// degree's stack tones (1-2-3-4-5-7-9) scores, as long as the lowest held
  /// note is the chord root. Prompts show root only ("ii — D"); [families] is
  /// ignored; bars score by degree only (no quality tally). In Freestyle the
  /// bass note names the degree.
  final bool anyTones;

  final Random _rng;

  /// Timing thresholds (ms), injected from the global timing-difficulty
  /// setting — identical to MetronomeController / the other runners.
  final int onBeatMs;
  final int closeMs;

  /// After a downbeat the current chord stays scoreable for this long, so a
  /// slightly-late press still counts toward *that* chord instead of being read
  /// as an early attempt on the next one. Matches [closeMs].
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

  // ---- Clock wiring (set by the screen, faked in tests) ------------------
  int Function() msSinceBeat = () => 0;
  int Function() beatPeriodMs = () => 600;

  /// Input-latency correction (ms) for a BLE MIDI keyboard.
  /// Set by the screen when a BLE keyboard is driving the drill.
  int inputLatencyMs = 0;

  /// Recent per-downbeat diagnostics for the on-screen overlay (see
  /// [kBeatDebug]). Empty and unused when debug is off.
  final BeatDebugLog debug = BeatDebugLog();

  /// Fired on every key press before judging (e.g. metronome flash).
  void Function(int midiNote)? onAnyPress;

  // ---- Drill state -------------------------------------------------------
  late JamKey _jamKey;
  late JamPromptPicker _picker;
  late ChordValidator _validator;
  late JamChordMatcher _matcher;
  JamChord? _current;
  JamPhase _phase = JamPhase.idle;
  int _countInRemaining = 0;

  /// An early strike locked in during the last count-in window: its distance
  /// (ms) ahead of the coming downbeat. Survives a release before the tick,
  /// so short staccato stabs score by when they were struck.
  int? _pendingOffBy;

  /// Freestyle only: the chord recognized when [_pendingOffBy] was locked,
  /// so a released early strike still knows what it played.
  JamChord? _pendingChord;

  /// Freestyle only: the scale degree (1–7) that would score a repeat if
  /// played again, and the last legal chord played (for the "not ii (Dm7)"
  /// label). Null before the first legal chord this session — anything goes
  /// on bar one.
  int? _forbiddenDegree;
  JamChord? _lastLegalChord;

  /// The chord judged on the just-passed downbeat, shown alongside
  /// [lastVerdict] in the brief confirmation flash. In Prompted this is
  /// always the shown chord; in Freestyle it's whatever was recognized
  /// (null if nothing was).
  JamChord? _lastJudgedChord;

  /// The verdict of the chord most recently judged, shown briefly as a
  /// confirmation right after the downbeat. Null until the first downbeat or
  /// once the confirmation window passes.
  JamResult? _lastVerdict;
  Timer? _verdictTimer;

  /// Grace-window timer: while running, the downbeat opens a short window during
  /// which a late press can still complete (and thus score) the current chord.
  Timer? _graceTimer;

  final Set<int> _held = {};
  final Set<int> _wrongFlash = {};
  final Set<int> _correctFlash = {};
  Timer? _flashTimer;

  // ---- Session stats -----------------------------------------------------
  int barsJudged = 0;
  int barsOnBeat = 0;
  int barsClose = 0;
  int barsMissed = 0; // wrong chord or not held in time
  int notesWrong = 0; // wrong-pitch presses
  int streak = 0;
  int bestStreak = 0;

  /// Per-quality and per-degree tallies, accumulated across the session.
  final Map<String, JamTally> qualityScores = {};
  final Map<String, JamTally> degreeScores = {};

  /// Snapshot of the session's per-quality tallies as `key → (attempts, correct)`
  /// records, for merging into persisted lifetime aggregates on stop.
  Map<String, (int, int)> get qualitySnapshot => _snapshot(qualityScores);
  Map<String, (int, int)> get degreeSnapshot => _snapshot(degreeScores);

  Map<String, (int, int)> _snapshot(Map<String, JamTally> scores) => {
        for (final e in scores.entries) e.key: (e.value.attempts, e.value.correct),
      };

  // ---- Public state for the UI -------------------------------------------
  JamPhase get phase => _phase;

  /// The drill is active (a chord is on screen, counting toward its downbeat or
  /// inside the post-downbeat grace window).
  bool get active => _phase != JamPhase.idle && _current != null;

  /// Kept for the UI/tests: "a chord is on screen". Identical to [active] now
  /// that count-in and the grace window are one continuous loop.
  bool get running => active;
  bool get countingIn => _phase == JamPhase.countingIn;

  /// True during the brief grace window right after a downbeat.
  bool get judging => _phase == JamPhase.judging;

  /// Count-in beat to display (1..beatsPerBar). Counts the beats of the current
  /// chord's count-in; the chord is struck on the downbeat after the count of
  /// [beatsPerBar] — which is also beat 1 of the next chord's bar, so the
  /// strike tick (and the grace window after it) displays as 1. 0 when idle.
  int get countInBeat => _phase == JamPhase.idle
      ? 0
      : (_phase == JamPhase.judging ? 1 : beatsPerBar - _countInRemaining);

  /// Beats remaining before the strike (countdown for the numbers display):
  /// [beatsPerBar]..1, reaching 1 on the count beat just before the strike
  /// tick. During the grace window (strike just passed) it reads 1. 0 when
  /// idle.
  int get beatsUntilStrike => _phase == JamPhase.idle
      ? 0
      : (_phase == JamPhase.judging ? 1 : _countInRemaining + 1);

  /// The verdict of the chord just judged, for the brief confirmation flash.
  /// Null outside the confirmation window.
  JamResult? get lastVerdict => _lastVerdict;

  /// Chords completed so far in this fixed-length session.
  int get barsCompleted => barsJudged;

  /// Chords remaining before the session auto-ends.
  int get barsRemaining => (sessionBars - barsJudged).clamp(0, sessionBars);

  /// "{Root} Major" — the key header.
  String get keyLabel => _jamKey.label;

  /// The chord currently prompted (visible during its count-in). Null before the
  /// first prompt is drawn.
  JamChord? get currentChord => _current;

  /// Prompt label, e.g. "ii — Dm7" (empty before the first prompt). In
  /// Freestyle there's no fixed prompt, so this just reads "Freestyle".
  String get promptLabel => freestyle ? 'Freestyle' : (_current?.prompt ?? '');

  /// Whether the prompted chord is fully and exactly sounding right now
  /// (octave-free, no extra notes) — drives the "chord matched" indicator.
  /// In Freestyle this means: a diatonic chord from an enabled family is held
  /// and it isn't a repeat of the last legal degree.
  bool get currentChordMatched => (freestyle || anyTones)
      ? _isChordComplete
      : (_current != null &&
          _validator.evaluate(_held) == ValidationStatus.complete);

  /// Freestyle only: the chord currently recognized while building, for the
  /// live readout pill. Null outside Freestyle, when idle, no notes held, or
  /// nothing recognized yet.
  JamChordMatch? get liveChordMatch {
    if (!freestyle) return null;
    if (!anyTones) return _liveMatch;
    final m = _openMatch;
    return m == null ? null : JamChordMatch(m, true);
  }

  /// Freestyle only: whether the live-recognized chord shares a degree with
  /// the last legal chord — striking it now would score a repeat miss.
  bool get liveChordIsRepeat =>
      liveChordMatch != null && liveChordMatch!.chord.degree == _forbiddenDegree;

  /// Freestyle only: "not ii (Dm7)" — the forbidden degree/chord shown under
  /// the prompt. Empty before the first legal chord (anything goes on bar one).
  String get freestyleForbiddenLabel {
    final last = _lastLegalChord;
    return last == null ? '' : 'not ${last.roman} (${last.name})';
  }

  /// The chord judged on the just-passed downbeat, for the brief confirmation
  /// flash shown alongside [lastVerdict]. Meaningful only while that's set.
  JamChord? get lastJudgedChord => _lastJudgedChord;

  JamChordMatch? get _liveMatch {
    if (_held.isEmpty) return null;
    final heldPcs = _held.map(pitchClassOf).toSet();
    final bassPc = pitchClassOf(_held.reduce(min));
    return _matcher.match(heldPcs,
        bassPc: bassPc, forbiddenDegree: _forbiddenDegree);
  }

  /// Total bars judged, correct (on-beat + close), and overall accuracy.
  int get barsCorrect => barsOnBeat + barsClose;
  double get accuracy => barsJudged == 0 ? 0 : barsCorrect / barsJudged;

  /// On-time fraction among correct bars (on-beat / correct).
  double get onTimeRate => barsCorrect == 0 ? 0 : barsOnBeat / barsCorrect;

  /// Performance tier for the current overall accuracy.
  JamTier get tier => tierFor(accuracy);

  /// The lowest-accuracy attempted quality / degree (the weak spot), or null
  /// if nothing has been attempted yet.
  MapEntry<String, JamTally>? get weakestQuality => _weakest(qualityScores);
  MapEntry<String, JamTally>? get weakestDegree => _weakest(degreeScores);

  MapEntry<String, JamTally>? _weakest(Map<String, JamTally> scores) {
    MapEntry<String, JamTally>? worst;
    for (final e in scores.entries) {
      if (e.value.attempts == 0) continue;
      if (worst == null || e.value.accuracy < worst.value.accuracy) worst = e;
    }
    return worst;
  }

  // ---- Start / stop ------------------------------------------------------
  void start() {
    _rebuildPicker();
    _phase = JamPhase.countingIn;
    _countInRemaining = beatsPerBar;
    _lastVerdict = null;
    _lastJudgedChord = null;
    _forbiddenDegree = null;
    _lastLegalChord = null;
    _pendingOffBy = null;
    _pendingChord = null;
    _verdictTimer?.cancel();
    _graceTimer?.cancel();
    // Draw the first chord now so it's on screen for its whole count-in; it's
    // struck on the downbeat that ends the count-in. Freestyle has no fixed
    // prompt, so there's nothing to draw — anything legal goes on bar one.
    if (!freestyle) _nextPrompt();
    _held.clear();
    _clearFlashes();
    notifyListeners();
  }

  /// Fired once when a running/counting-in session ends (via [stop]), so the
  /// screen can snapshot stats, persist lifetime aggregates, and show a summary.
  /// Not fired when [stop] is a no-op on an already-idle controller.
  void Function()? onSessionEnd;

  void stop() {
    final wasActive = _phase != JamPhase.idle;
    _phase = JamPhase.idle;
    _verdictTimer?.cancel();
    _graceTimer?.cancel();
    _clearFlashes();
    notifyListeners();
    if (wasActive) onSessionEnd?.call();
  }

  /// Clear accumulated session scores (used by the settings "reset" action).
  void resetScores() {
    barsJudged = barsOnBeat = barsClose = barsMissed = notesWrong = 0;
    streak = bestStreak = 0;
    _lastVerdict = null;
    _graceTimer?.cancel();
    qualityScores.clear();
    degreeScores.clear();
    notifyListeners();
  }

  void _rebuildPicker() {
    _jamKey = JamKey(keyPc);
    _picker = JamPromptPicker(
        anyTones ? _jamKey.openPrompts() : _jamKey.prompts(families),
        rng: _rng);
    _validator = ChordValidator(_jamKey.chord(1, JamFamily.triad).pitchClasses);
    _matcher = JamChordMatcher(_jamKey, families);
  }

  /// Draw the next prompt and rearm its validator.
  void _nextPrompt() {
    _current = _picker.next();
    _validator = ChordValidator(_current!.pitchClasses);
  }

  // ---- Beat clock --------------------------------------------------------
  /// Wire to MetronomeController.onBeat. The metronome runs continuously; each
  /// chord is shown for a full [beatsPerBar]-beat count-in, then judged on the
  /// downbeat that ends it, after which the next chord's count-in begins — no
  /// break or reset. The session auto-ends once [sessionBars] chords are judged.
  void onBeat() {
    switch (_phase) {
      case JamPhase.idle:
        return;
      case JamPhase.judging:
        // The previous chord's grace window was still open when the next beat
        // arrived (only possible at very low tempo). Resolve it now as whatever
        // it currently is, then treat this beat as that chord's resolution —
        // i.e. fall through into advancing.
        _resolveGrace(null);
        return;
      case JamPhase.countingIn:
        if (_countInRemaining > 0) {
          // Still counting in toward this chord's downbeat. A full
          // [beatsPerBar] count-in beats tick before the strike beat — the
          // downbeat AFTER the count of "beatsPerBar", exactly like Scale
          // Running's count-in (count 1-2-3-4, play on the next downbeat).
          _countInRemaining--;
          notifyListeners();
          return;
        }
        // This tick is the downbeat. A locked-in early strike from the last
        // count-in window ([_pendingOffBy]) scores even if the chord was
        // released before the tick (staccato comping); otherwise a chord held
        // through the tick judges immediately, and anything else opens a
        // grace window so a slightly-late press still scores *this* chord
        // rather than spilling onto the next one.
        debug.add('DOWNBEAT since=${msSinceBeat()} period=${beatPeriodMs()} '
            'lat=$inputLatencyMs pending=$_pendingOffBy '
            'complete=$_isChordComplete '
            'held=${(_held.map(pitchClassOf).toList()..sort())} '
            'exp=${(_current?.pitchClasses.toList()?..sort())}');
        if (_pendingOffBy != null || _isChordComplete) {
          _scoreCurrent(offBy: _pendingOffBy ?? 0,
              preMatched: _pendingOffBy != null);
          _advanceOrEnd();
        } else {
          _phase = JamPhase.judging;
          _graceTimer?.cancel();
          // The real wall-clock wait must also absorb input latency: a
          // physically on-time press doesn't even arrive as an event until
          // ~inputLatencyMs after the tick, so waiting only graceMs would
          // give up before it's ever seen. This was masked while latency
          // correction was stuck at 0 (see resolveInputLatencyMs) and
          // surfaces now that it reads real BLE latency — especially under
          // Strict timing, where closeMs can be smaller than the device's
          // own latency. The scored offBy (computed once the press does
          // arrive) is unaffected — it's still capped to closeMs there.
          _graceTimer = Timer(
              Duration(milliseconds: graceMs + inputLatencyMs),
              _resolveGraceTimedOut);
          notifyListeners();
        }
    }
  }

  bool get _isChordComplete {
    if (anyTones) {
      final m = _openMatch;
      return m != null && (!freestyle || m.degree != _forbiddenDegree);
    }
    if (freestyle) {
      final m = _liveMatch;
      return m != null && m.enabled && m.chord.degree != _forbiddenDegree;
    }
    return _validator.evaluate(_held) == ValidationStatus.complete;
  }

  /// "Any chord tones": the open chord currently voiced, or null. Requires at
  /// least 3 keys held (doubles count), every held pitch class inside the
  /// degree's stack, and the lowest key sounding the root. Prompted matches
  /// only against the prompted degree; Freestyle names the degree from the
  /// bass note (the forbidden-repeat check is the caller's job, so the live
  /// pill can still show a repeat as a repeat).
  JamChord? get _openMatch {
    if (_held.length < 3) return null;
    final bassPc = pitchClassOf(_held.reduce(min));
    final heldPcs = _held.map(pitchClassOf).toSet();
    if (!freestyle) {
      final c = _current;
      if (c == null || _jamKey.rootPcOf(c.degree) != bassPc) return null;
      return heldPcs.every(c.pitchClasses.contains) ? c : null;
    }
    final degree = _jamKey.degreeOfRoot(bassPc);
    if (degree == null) return null;
    final chord = _jamKey.openChord(degree);
    return heldPcs.every(chord.pitchClasses.contains) ? chord : null;
  }

  /// The grace timer expired without the chord being completed: lock in a miss
  /// and advance.
  void _resolveGraceTimedOut() => _resolveGrace(null);

  /// Resolve an open grace window: score the current chord by whether it ended
  /// up complete (a late completion counts as a [JamResult.close] hit), then
  /// advance to the next chord or end the session.
  void _resolveGrace(int? offBy) {
    if (_phase != JamPhase.judging) return;
    _graceTimer?.cancel();
    _scoreCurrent(offBy: offBy);
    _advanceOrEnd();
  }

  /// Test hook: synchronously close an open grace window (the real one is a
  /// 150ms timer). No-op when not currently in the grace window.
  @visibleForTesting
  void debugResolveGrace() => _resolveGrace(null);

  /// Draw the next chord (resetting the count-in) or end the session if the
  /// configured number of chords have now been judged.
  void _advanceOrEnd() {
    if (barsJudged >= sessionBars) {
      stop(); // auto-end + tally
      return;
    }
    if (!freestyle) _nextPrompt();
    // The strike tick doubles as beat 1 of the next chord's bar, so only
    // beatsPerBar - 1 count beats remain before its strike — keeping one
    // chord per bar with every strike on a downbeat.
    _countInRemaining = beatsPerBar - 1;
    _pendingOffBy = null;
    _pendingChord = null;
    _held.clear();
    _phase = JamPhase.countingIn;
    notifyListeners();
  }

  /// Score the current chord and flash its verdict. [preMatched] marks a
  /// strike locked in before the downbeat ([_pendingOffBy]), which counts as
  /// matched even if the keys were released before the tick.
  void _scoreCurrent({required int? offBy, bool preMatched = false}) {
    final chord = freestyle
        ? (_pendingChord ?? (anyTones ? _openMatch : _liveMatch?.chord))
        : _current;
    final matched = preMatched || _isChordComplete;

    final JamResult verdict;
    if (!matched || offBy == null) {
      verdict = JamResult.missed;
    } else {
      verdict = switch (_judge.verdictFor(offBy)) {
        BeatVerdict.onBeat => JamResult.onBeat,
        BeatVerdict.close => JamResult.close,
        BeatVerdict.off => JamResult.missed,
      };
    }

    debug.add('  SCORE off=$offBy matched=$matched preMatched=$preMatched '
        '-> $verdict (onBeatMs=$onBeatMs closeMs=$closeMs)');
    barsJudged++;
    final ok = verdict != JamResult.missed;
    switch (verdict) {
      case JamResult.onBeat:
        barsOnBeat++;
      case JamResult.close:
        barsClose++;
      case JamResult.missed:
        barsMissed++;
    }
    if (ok) {
      streak++;
      if (streak > bestStreak) bestStreak = streak;
    } else {
      streak = 0;
    }

    if (chord != null) {
      // "Any chord tones" bars have no fixed quality — degree tally only.
      if (!anyTones) {
        (qualityScores[chord.qualityKey] ??= JamTally()).record(ok);
      }
      (degreeScores[chord.degreeKey] ??= JamTally()).record(ok);
    }
    if (freestyle && ok && chord != null) {
      _forbiddenDegree = chord.degree;
      _lastLegalChord = chord;
    }
    _lastJudgedChord = chord;

    _flashVerdict(verdict);
  }

  /// Show [verdict] as a brief confirmation right after the downbeat.
  void _flashVerdict(JamResult verdict) {
    _lastVerdict = verdict;
    _verdictTimer?.cancel();
    _verdictTimer = Timer(const Duration(milliseconds: 400), () {
      _lastVerdict = null;
      notifyListeners();
    });
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
    final wasComplete = _isChordComplete;
    _held.add(midiNote);
    if (_phase != JamPhase.idle && (freestyle || _current != null)) {
      _judgePress(midiNote);
      
      if (!wasComplete && _isChordComplete) {
        if (_phase == JamPhase.judging) {
          // Late completion inside the grace window: judged by the shared
          // engine. A wrapped press (struck before the tick, delivered after
          // it) judges by its true distance; a press genuinely early for the
          // NEXT beat can't claim this chord (offBy null → missed).
          final t = _judge.judgePress();
          _resolveGrace(t.early ? null : t.offBy);
          return;
        } else if (_phase == JamPhase.countingIn) {
          if (_countInRemaining == 0) {
            // Last count-in window: an early strike within the grace window
            // pre-claims the downbeat with its real timing — and survives a
            // release before the tick (staccato comping).
            final offBy = _judge.offByBeforeNextTick();
            if (_judge.withinGrace(offBy)) {
              _pendingOffBy = offBy;
              if (freestyle) {
                _pendingChord = anyTones ? _openMatch : _liveMatch?.chord;
              }
            }
          }
          // Completed earlier in the count-in: no lock needed — a chord still
          // held when the downbeat ticks judges complete there (offBy 0).
        }
      }
    }
    notifyListeners();
  }

  void releaseKey(int midiNote) {
    _held.remove(midiNote);
    _wrongFlash.remove(midiNote);
    notifyListeners();
  }

  /// A press outside the prompted chord flashes wrong and breaks the streak;
  /// the bar's verdict is still decided on the downbeat. A chord tone flashes
  /// correct. Mirrors the forgiving philosophy of the other runners.
  void _judgePress(int midiNote) {
    final pc = pitchClassOf(midiNote);
    final validPcs = freestyle ? _jamKey.scalePcs : _current!.pitchClasses;
    if (!validPcs.contains(pc)) {
      notesWrong++;
      streak = 0;
      _flash(_wrongFlash, midiNote);
      return;
    }
    _flash(_correctFlash, midiNote);
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

  /// Target dots: every pitch class of the prompted chord, so a hint shows in
  /// each octave the keyboard spans. Null prompt → no hints.
  bool isTargetHint(int midiNote) => freestyle
      ? _jamKey.scalePcs.contains(pitchClassOf(midiNote))
      : (_current?.pitchClasses.contains(pitchClassOf(midiNote)) ?? false);

  @override
  void dispose() {
    _midiSub?.cancel();
    _flashTimer?.cancel();
    _verdictTimer?.cancel();
    _graceTimer?.cancel();
    super.dispose();
  }
}
