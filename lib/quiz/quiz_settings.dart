import 'package:shared_preferences/shared_preferences.dart';

import '../theory/music_theory.dart';
import '../theory/scale_running.dart';
import '../theory/jam_mode.dart';
import '../theory/voicings.dart';
import '../social/social_models.dart';
import 'quiz_controller.dart';

/// Global timing difficulty: how tight the on-beat / close windows are when
/// judging presses against the metronome. One setting shared by every mode.
enum TimingDifficulty {
  easy(onBeatMs: 100, closeMs: 200),
  normal(onBeatMs: 70, closeMs: 150),
  strict(onBeatMs: 50, closeMs: 100);

  const TimingDifficulty({required this.onBeatMs, required this.closeMs});

  /// A press within this many ms of the beat is dead-on.
  final int onBeatMs;

  /// A press within this many ms is close (still correct). Also used as the
  /// backward-grace window, so grace scales with difficulty.
  final int closeMs;

  String get label => switch (this) {
        easy => 'Easy',
        normal => 'Normal',
        strict => 'Strict',
      };
}

/// Persists which scale / chord formulas the user wants to drill.
///
/// Selection is stored by formula *name* (stable across list reordering) as a
/// `List<String>` per mode. Absence of a stored value means "all enabled" -
/// the friendly default for a first launch. An empty stored list is respected
/// as "none", but callers should prevent saving an empty selection.
class QuizSettings {
  QuizSettings._(this._prefs);

  final SharedPreferencesAsync _prefs;

  static String _keyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'enabled_scales' : 'enabled_chords';

  static String _enabledKeysKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'enabled_keys_scales' : 'enabled_keys_chords';

  static String _formulaHintKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'hint_formula_scales' : 'hint_formula_chords';

  static String _dotsHintKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'hint_dots_scales' : 'hint_dots_chords';

  static String _statsBarKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'stats_bar_scales' : 'stats_bar_chords';

  static String _beatIndicatorKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'beat_indicator_scales' : 'beat_indicator_chords';

  static const _metronomeBpmKey = 'metronome_bpm';
  static const _timingDifficultyKey = 'timing_difficulty';
  static const _noteSoundKey = 'note_sound';
  static const _tickHapticKey = 'tick_haptic';
  static const _introSeenKey = 'intro_seen';
  static const _rotateHintDismissedKey = 'rotate_hint_dismissed';

  static String _scoreKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'score_scales' : 'score_chords';

  static String _bestStreakKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'best_streak_scales' : 'best_streak_chords';

  // Scale Running drill.
  static const _runChordsKey = 'run_chords';
  static const _runProgressionKey = 'run_progression';
  static const _runIncrementKey = 'run_increment';
  static const _runSeventhsKey = 'run_sevenths';
  static const _runStartKeyKey = 'run_start_key';
  static const _runRepsKey = 'run_reps';

  // Inversion Running drill.
  static const _invChordsKey = 'inv_chords';
  static const _invTempoKey = 'inv_tempo';
  static const _invShowDotsKey = 'inv_show_dots';
  static const _invShowFormulaKey = 'inv_show_formula';

  // Jam Mode drill.
  static const _jamKeyKey = 'jam_key';
  static const _jamFamiliesKey = 'jam_families';
  static const _jamShowDotsKey = 'jam_show_dots';
  static const _jamShowFormulaKey = 'jam_show_formula';
  static const _jamSessionBarsKey = 'jam_session_bars';
  static const _jamCountInNumbersKey = 'jam_count_in_numbers';
  static const _jamFreestyleKey = 'jam_freestyle';
  static const _jamAnyTonesKey = 'jam_any_tones';
  static const _jamQualityStatsKey = 'jam_quality_stats';
  static const _jamDegreeStatsKey = 'jam_degree_stats';
  static const _runKeyStatsKey = 'run_key_stats';
  static const _runModeStatsKey = 'run_mode_stats';
  static const _invChordStatsKey = 'inv_chord_stats';

  // Voicings drill. There is deliberately no stats key: the mode is unscored,
  // so nothing it does can reach accuracy, mode scores, or the leaderboard.
  static const _voicingCustomsKey = 'voicing_customs';
  static const _voicingStartKeyKey = 'voicing_start_key';
  static const _voicingIncrementKey = 'voicing_increment';
  static const _voicingShowDotsKey = 'voicing_show_dots';
  static const _voicingShowFormulaKey = 'voicing_show_formula';

  // Latency configuration.
  static String _latencyKeyFor(String deviceName) => 'latency_$deviceName';

  static Future<QuizSettings> load() async =>
      QuizSettings._(SharedPreferencesAsync());

  /// All available formula names for [mode], in display order.
  static List<String> allNames(QuizMode mode) => mode == QuizMode.scale
      ? [for (final s in commonScales) s.name]
      : [for (final c in commonChords) c.name];

  /// The set of enabled formula names for [mode]. Defaults to all when unset.
  Future<Set<String>> enabledNames(QuizMode mode) async {
    final stored = await _prefs.getStringList(_keyFor(mode));
    if (stored == null) return allNames(mode).toSet();
    return stored.toSet();
  }

  Future<void> setEnabledNames(QuizMode mode, Set<String> names) async {
    await _prefs.setStringList(_keyFor(mode), names.toList());
  }

  /// The set of enabled root pitch classes (0–11) for [mode]. Defaults to all
  /// twelve when unset, matching [enabledNames]'s "absence means all"
  /// convention. An empty stored value also falls back to all twelve so
  /// quiz rounds are never left with no key to draw from.
  Future<Set<int>> enabledRootPcs(QuizMode mode) async {
    final stored = await _prefs.getStringList(_enabledKeysKeyFor(mode));
    if (stored == null) return _allRootPcs;
    final pcs = {
      for (final s in stored)
        if (int.tryParse(s) case final pc? when pc >= 0 && pc <= 11) pc,
    };
    return pcs.isEmpty ? _allRootPcs : pcs;
  }

  Future<void> setEnabledRootPcs(QuizMode mode, Set<int> pcs) async {
    await _prefs.setStringList(
        _enabledKeysKeyFor(mode), [for (final pc in pcs) '$pc']);
  }

  static Set<int> get _allRootPcs => {for (var pc = 0; pc < 12; pc++) pc};

  /// Whether the formula line under the prompt is shown for [mode]. Default on.
  Future<bool> formulaHintEnabled(QuizMode mode) async =>
      await _prefs.getBool(_formulaHintKeyFor(mode)) ?? true;

  Future<void> setFormulaHintEnabled(QuizMode mode, bool on) async {
    await _prefs.setBool(_formulaHintKeyFor(mode), on);
  }

  /// Whether the blue target dots on the keyboard are shown for [mode]. Default on.
  Future<bool> dotsHintEnabled(QuizMode mode) async =>
      await _prefs.getBool(_dotsHintKeyFor(mode)) ?? true;

  Future<void> setDotsHintEnabled(QuizMode mode, bool on) async {
    await _prefs.setBool(_dotsHintKeyFor(mode), on);
  }

  /// Whether the score/streak/best stats bar is shown for [mode]. Default off.
  Future<bool> statsBarEnabled(QuizMode mode) async =>
      await _prefs.getBool(_statsBarKeyFor(mode)) ?? false;

  Future<void> setStatsBarEnabled(QuizMode mode, bool on) async {
    await _prefs.setBool(_statsBarKeyFor(mode), on);
  }

  /// Whether the BPM readout flashes with key-press timing for [mode]. Default on.
  Future<bool> beatIndicatorEnabled(QuizMode mode) async =>
      await _prefs.getBool(_beatIndicatorKeyFor(mode)) ?? true;

  Future<void> setBeatIndicatorEnabled(QuizMode mode, bool on) async {
    await _prefs.setBool(_beatIndicatorKeyFor(mode), on);
  }

  /// Whether the first-run welcome sheet has been shown.
  Future<bool> introSeen() async =>
      await _prefs.getBool(_introSeenKey) ?? false;

  Future<void> setIntroSeen() async {
    await _prefs.setBool(_introSeenKey, true);
  }

  /// Whether the portrait "rotate for bigger keys" banner has been dismissed.
  /// Once dismissed it stays dismissed. Default false (shown).
  Future<bool> rotateHintDismissed() async =>
      await _prefs.getBool(_rotateHintDismissedKey) ?? false;

  Future<void> setRotateHintDismissed() async {
    await _prefs.setBool(_rotateHintDismissedKey, true);
  }

  /// Whether key presses sound a piano note, shared across modes. Default on.
  Future<bool> noteSoundEnabled() async =>
      await _prefs.getBool(_noteSoundKey) ?? true;

  Future<void> setNoteSoundEnabled(bool on) async {
    await _prefs.setBool(_noteSoundKey, on);
  }

  /// Whether the metronome's tick buzzes the device, shared across modes.
  /// Default on.
  Future<bool> tickHapticEnabled() async =>
      await _prefs.getBool(_tickHapticKey) ?? true;

  Future<void> setTickHapticEnabled(bool on) async {
    await _prefs.setBool(_tickHapticKey, on);
  }

  /// Lifetime score for [mode], persisted across navigation and launches.
  Future<int> quizScore(QuizMode mode) async =>
      await _prefs.getInt(_scoreKeyFor(mode)) ?? 0;

  /// Best streak for [mode], persisted across navigation and launches.
  Future<int> quizBestStreak(QuizMode mode) async =>
      await _prefs.getInt(_bestStreakKeyFor(mode)) ?? 0;

  Future<void> setQuizStats(QuizMode mode, int score, int bestStreak) async {
    await _prefs.setInt(_scoreKeyFor(mode), score);
    await _prefs.setInt(_bestStreakKeyFor(mode), bestStreak);
  }

  /// The metronome tempo, shared across modes. Default 100.
  Future<int> metronomeBpm() async =>
      await _prefs.getInt(_metronomeBpmKey) ?? 100;

  Future<void> setMetronomeBpm(int bpm) async {
    await _prefs.setInt(_metronomeBpmKey, bpm);
  }

  /// Global timing difficulty, shared by every beat-judged mode. Default
  /// normal; unknown stored values fall back to normal.
  Future<TimingDifficulty> timingDifficulty() async {
    final stored = await _prefs.getString(_timingDifficultyKey);
    return TimingDifficulty.values.firstWhere(
      (d) => d.name == stored,
      orElse: () => TimingDifficulty.normal,
    );
  }

  Future<void> setTimingDifficulty(TimingDifficulty difficulty) async {
    await _prefs.setString(_timingDifficultyKey, difficulty.name);
  }

  // ---- Scale Running drill settings ----

  /// Whether the drill follows a chord progression (vs scale runs only).
  /// Default on.
  Future<bool> runChordsEnabled() async =>
      await _prefs.getBool(_runChordsKey) ?? true;

  Future<void> setRunChordsEnabled(bool on) async {
    await _prefs.setBool(_runChordsKey, on);
  }

  /// The selected progression, resolved by name. Defaults to the first preset.
  Future<ChordProgression> runProgression() async {
    final name = await _prefs.getString(_runProgressionKey);
    return commonProgressions.firstWhere(
      (p) => p.name == name,
      orElse: () => commonProgressions.first,
    );
  }

  Future<void> setRunProgressionName(String name) async {
    await _prefs.setString(_runProgressionKey, name);
  }

  /// How the key advances after each progression pass. Default fifths.
  Future<KeyIncrement> runKeyIncrement() async {
    final stored = await _prefs.getString(_runIncrementKey);
    return stored == KeyIncrement.chromatic.name
        ? KeyIncrement.chromatic
        : KeyIncrement.fifths;
  }

  Future<void> setRunKeyIncrement(KeyIncrement increment) async {
    await _prefs.setString(_runIncrementKey, increment.name);
  }

  /// Pitch class (0–11) the drill starts in. Default 0 (C).
  Future<int> runStartKeyPc() async =>
      (await _prefs.getInt(_runStartKeyKey) ?? 0).clamp(0, 11);

  Future<void> setRunStartKeyPc(int pc) async {
    await _prefs.setInt(_runStartKeyKey, pc % 12);
  }

  /// Stack diatonic 7th chords instead of triads. Default off (triads).
  Future<bool> runSevenths() async =>
      await _prefs.getBool(_runSeventhsKey) ?? false;

  Future<void> setRunSevenths(bool on) async {
    await _prefs.setBool(_runSeventhsKey, on);
  }

  /// Allowed reps-per-key choices: stay on each key 1x, 2x, or 4x before
  /// advancing.
  static const runRepsOptions = [1, 2, 4];

  /// How many full passes to play in each key before advancing. Default 1
  /// (advance every pass). Falls back to 1 for any unexpected stored value.
  Future<int> runRepsPerKey() async {
    final stored = await _prefs.getInt(_runRepsKey) ?? 1;
    return runRepsOptions.contains(stored) ? stored : 1;
  }

  Future<void> setRunRepsPerKey(int reps) async {
    await _prefs.setInt(
        _runRepsKey, runRepsOptions.contains(reps) ? reps : 1);
  }

  /// The enabled [ScaleFormula]s (preserving library order). Falls back to the
  /// full set if the saved selection somehow matches nothing.
  Future<List<ScaleFormula>> enabledScales() async {
    final names = await enabledNames(QuizMode.scale);
    final filtered =
        commonScales.where((s) => names.contains(s.name)).toList();
    return filtered.isEmpty ? commonScales : filtered;
  }

  /// The enabled [ChordFormula]s (preserving library order).
  Future<List<ChordFormula>> enabledChords() async {
    final names = await enabledNames(QuizMode.chord);
    final filtered =
        commonChords.where((c) => names.contains(c.name)).toList();
    return filtered.isEmpty ? commonChords : filtered;
  }

  // ---- Inversion Running drill settings ----

  /// The four chords offered in v1 (all present in [commonChords]).
  static const List<String> invChordNames = [
    'Major', 'Minor', 'Major 7th', 'Minor 7th',
  ];

  /// Enabled inversion-drill chord names. Defaults to all four v1 chords.
  Future<Set<String>> invEnabledChordNames() async {
    final stored = await _prefs.getStringList(_invChordsKey);
    if (stored == null || stored.isEmpty) return invChordNames.toSet();
    return stored.toSet();
  }

  Future<void> setInvEnabledChordNames(Set<String> names) async {
    await _prefs.setStringList(_invChordsKey, names.toList());
  }

  /// The enabled inversion-drill [ChordFormula]s (library order). Falls back to
  /// the full v1 set if the saved selection matches nothing.
  Future<List<ChordFormula>> invEnabledChords() async {
    final names = await invEnabledChordNames();
    final filtered = commonChords
        .where((c) => invChordNames.contains(c.name) && names.contains(c.name))
        .toList();
    if (filtered.isNotEmpty) return filtered;
    return commonChords.where((c) => invChordNames.contains(c.name)).toList();
  }

  /// Whether the inversion drill runs in tempo (metronome) mode. Default off
  /// (self-paced). Tempo mode is wired in a later build.
  Future<bool> invTempoMode() async =>
      await _prefs.getBool(_invTempoKey) ?? false;

  Future<void> setInvTempoMode(bool on) async {
    await _prefs.setBool(_invTempoKey, on);
  }

  /// Whether the blue target dots hint is shown on the keyboard. Default on.
  Future<bool> invShowDots() async =>
      await _prefs.getBool(_invShowDotsKey) ?? true;

  Future<void> setInvShowDots(bool on) async {
    await _prefs.setBool(_invShowDotsKey, on);
  }

  /// Whether the chord formula line is shown under the prompt. Default on.
  Future<bool> invShowFormula() async =>
      await _prefs.getBool(_invShowFormulaKey) ?? true;

  Future<void> setInvShowFormula(bool on) async {
    await _prefs.setBool(_invShowFormulaKey, on);
  }

  // ---- Jam Mode drill settings ----

  /// Pitch class (0–11) of the fixed key Jam Mode plays in. Default 0 (C).
  Future<int> jamKeyPc() async =>
      (await _prefs.getInt(_jamKeyKey) ?? 0).clamp(0, 11);

  Future<void> setJamKeyPc(int pc) async {
    await _prefs.setInt(_jamKeyKey, pc % 12);
  }

  /// Enabled chord families, stored by [JamFamily.name]. Defaults to all four;
  /// an empty stored value is treated as "all" so the drill is never empty.
  Future<Set<JamFamily>> jamFamilies() async {
    final stored = await _prefs.getStringList(_jamFamiliesKey);
    if (stored == null || stored.isEmpty) return JamFamily.values.toSet();
    final names = stored.toSet();
    final picked =
        JamFamily.values.where((f) => names.contains(f.name)).toSet();
    return picked.isEmpty ? JamFamily.values.toSet() : picked;
  }

  Future<void> setJamFamilies(Set<JamFamily> families) async {
    await _prefs.setStringList(
        _jamFamiliesKey, families.map((f) => f.name).toList());
  }

  /// Whether the blue target dots hint is shown on the keyboard. Default on.
  Future<bool> jamShowDots() async =>
      await _prefs.getBool(_jamShowDotsKey) ?? true;

  Future<void> setJamShowDots(bool on) async {
    await _prefs.setBool(_jamShowDotsKey, on);
  }

  /// Whether the chord formula line is shown under the prompt. Default on.
  Future<bool> jamShowFormula() async =>
      await _prefs.getBool(_jamShowFormulaKey) ?? true;

  Future<void> setJamShowFormula(bool on) async {
    await _prefs.setBool(_jamShowFormulaKey, on);
  }

  /// The allowed fixed session lengths, in chords.
  static const List<int> jamSessionLengths = [12, 24, 48];

  /// Number of chords per session. Default 24; clamped to an allowed length.
  Future<int> jamSessionBars() async {
    final stored = await _prefs.getInt(_jamSessionBarsKey) ?? 24;
    return jamSessionLengths.contains(stored) ? stored : 24;
  }

  Future<void> setJamSessionBars(int bars) async {
    final v = jamSessionLengths.contains(bars) ? bars : 24;
    await _prefs.setInt(_jamSessionBarsKey, v);
  }

  /// Count-in display style: true → decrementing numbers (default), false →
  /// beat dots.
  Future<bool> jamCountInNumbers() async =>
      await _prefs.getBool(_jamCountInNumbersKey) ?? true;

  Future<void> setJamCountInNumbers(bool on) async {
    await _prefs.setBool(_jamCountInNumbersKey, on);
  }

  /// Whether Jam Mode is in Freestyle (play any diatonic chord, just don't
  /// repeat the last scale degree) rather than Prompted (a specific chord
  /// shown each bar). Default false (Prompted).
  Future<bool> jamFreestyle() async =>
      await _prefs.getBool(_jamFreestyleKey) ?? false;

  Future<void> setJamFreestyle(bool on) async {
    await _prefs.setBool(_jamFreestyleKey, on);
  }

  /// Jam Mode "any chord tones" toggle: any 3+ note voicing built from the
  /// degree's stack tones scores, as long as the lowest note is the root.
  /// While on, the family selection is ignored (but kept stored). Default off.
  Future<bool> jamAnyTones() async =>
      await _prefs.getBool(_jamAnyTonesKey) ?? false;

  Future<void> setJamAnyTones(bool on) async {
    await _prefs.setBool(_jamAnyTonesKey, on);
  }

  /// Lifetime per-quality accuracy aggregates, accumulated across all sessions.
  /// Map key → (attempts, correct). Used to surface long-term weak spots.
  Future<Map<String, (int, int)>> jamQualityStats() async =>
      _decodeStats(await _prefs.getStringList(_jamQualityStatsKey));

  /// Lifetime per-degree accuracy aggregates (Roman numeral → attempts/correct).
  Future<Map<String, (int, int)>> jamDegreeStats() async =>
      _decodeStats(await _prefs.getStringList(_jamDegreeStatsKey));

  /// Merge one finished session's tallies into the persisted lifetime totals.
  /// Each map is `key → (attempts, correct)` for the session just played.
  Future<void> mergeJamStats(
    Map<String, (int, int)> quality,
    Map<String, (int, int)> degree,
  ) async {
    final mergedQ = _mergeStats(await jamQualityStats(), quality);
    final mergedD = _mergeStats(await jamDegreeStats(), degree);
    await _prefs.setStringList(_jamQualityStatsKey, _encodeStats(mergedQ));
    await _prefs.setStringList(_jamDegreeStatsKey, _encodeStats(mergedD));
  }

  /// Clear all lifetime Jam Mode aggregates (the settings "reset stats" action).
  Future<void> resetJamStats() async {
    await _prefs.remove(_jamQualityStatsKey);
    await _prefs.remove(_jamDegreeStatsKey);
  }

  /// Lifetime per-key accuracy aggregates for Scale Running ("C Major" →
  /// attempts/correct), accumulated across all sessions.
  Future<Map<String, (int, int)>> runKeyStats() async =>
      _decodeStats(await _prefs.getStringList(_runKeyStatsKey));

  /// Lifetime per-mode accuracy aggregates for Scale Running ("Dorian" →
  /// attempts/correct).
  Future<Map<String, (int, int)>> runModeStats() async =>
      _decodeStats(await _prefs.getStringList(_runModeStatsKey));

  /// Merge one finished Scale Running session's tallies into the persisted
  /// lifetime totals. Each map is `key → (attempts, correct)`.
  Future<void> mergeRunStats(
    Map<String, (int, int)> keyStats,
    Map<String, (int, int)> modeStats,
  ) async {
    final mergedK = _mergeStats(await runKeyStats(), keyStats);
    final mergedM = _mergeStats(await runModeStats(), modeStats);
    await _prefs.setStringList(_runKeyStatsKey, _encodeStats(mergedK));
    await _prefs.setStringList(_runModeStatsKey, _encodeStats(mergedM));
  }

  /// Clear all lifetime Scale Running aggregates (the settings "reset" action).
  Future<void> resetRunStats() async {
    await _prefs.remove(_runKeyStatsKey);
    await _prefs.remove(_runModeStatsKey);
  }

  /// Lifetime per-chord-type accuracy aggregates for Inversion Running
  /// ("Major" → attempts/correct), accumulated across all sessions.
  Future<Map<String, (int, int)>> invChordStats() async =>
      _decodeStats(await _prefs.getStringList(_invChordStatsKey));

  /// Merge one finished Inversion Running session's tally into the persisted
  /// lifetime totals. Map is `chord name → (attempts, correct)`.
  Future<void> mergeInversionStats(Map<String, (int, int)> chordStats) async {
    final merged = _mergeStats(await invChordStats(), chordStats);
    await _prefs.setStringList(_invChordStatsKey, _encodeStats(merged));
  }

  /// Clear all lifetime Inversion Running aggregates (the settings "reset" action).
  Future<void> resetInversionStats() async {
    await _prefs.remove(_invChordStatsKey);
  }

  /// Lifetime per-mode totals for the shareable overview scores, summed from
  /// the stored running aggregates. Scale Running sums per-key plays, Jam
  /// sums per-quality, Inversion sums per-chord — one (attempts, correct)
  /// per mode. (Per-key and per-mode views count the same plays, so summing
  /// either gives the mode total; keys/qualities are used.)
  Future<ModeStats> modeStats() async {
    final (ra, rc) = _sumStats(await runKeyStats());
    final (ja, jc) = _sumStats(await jamQualityStats());
    final (ia, ic) = _sumStats(await invChordStats());
    return ModeStats(
      runAttempts: ra,
      runCorrect: rc,
      jamAttempts: ja,
      jamCorrect: jc,
      invAttempts: ia,
      invCorrect: ic,
    );
  }

  static (int, int) _sumStats(Map<String, (int, int)> m) {
    var a = 0, c = 0;
    for (final v in m.values) {
      a += v.$1;
      c += v.$2;
    }
    return (a, c);
  }

  // ---- Voicings drill ----

  /// How many voicings a free user may save. Pro is unlimited. Going over the
  /// limit (by buying Pro, saving, then lapsing) never deletes anything — it
  /// only blocks saving more.
  static const int freeVoicingLimit = 3;

  /// The user's saved voicings, oldest first. A line that fails to decode is
  /// skipped rather than thrown, so one corrupt entry can't hide the rest of
  /// the collection.
  Future<List<VoicingSpec>> savedVoicings() async {
    final stored = await _prefs.getStringList(_voicingCustomsKey);
    if (stored == null) return [];
    return [
      for (final line in stored) ?VoicingSpec.decode(line),
    ];
  }

  /// Add [spec], or replace the one already holding its id. An edit or rename
  /// keeps its place in the list rather than jumping to the end.
  Future<void> upsertVoicing(VoicingSpec spec) async {
    final all = await savedVoicings();
    final i = all.indexWhere((v) => v.id == spec.id);
    if (i >= 0) {
      all[i] = spec;
    } else {
      all.add(spec);
    }
    await _writeVoicings(all);
  }

  /// Replace the stored order with [ordered]. The list order *is* the display
  /// order, so reordering is just a rewrite — no sort key to keep in sync.
  Future<void> reorderVoicings(List<VoicingSpec> ordered) =>
      _writeVoicings(ordered);

  Future<void> deleteVoicing(String id) async {
    final all = await savedVoicings();
    all.removeWhere((v) => v.id == id);
    await _writeVoicings(all);
  }

  Future<void> _writeVoicings(List<VoicingSpec> all) async {
    await _prefs.setStringList(
        _voicingCustomsKey, [for (final v in all) v.encode()]);
  }

  /// Pitch class (0–11) the drill starts in. Default 0 (C).
  Future<int> voicingStartKeyPc() async =>
      (await _prefs.getInt(_voicingStartKeyKey) ?? 0).clamp(0, 11);

  Future<void> setVoicingStartKeyPc(int pc) async {
    await _prefs.setInt(_voicingStartKeyKey, pc % 12);
  }

  /// How the key advances between steps. Default chromatic (25 keys, up an
  /// octave and back); fifths runs the circle once, 12 keys.
  Future<KeyIncrement> voicingIncrement() async {
    final stored = await _prefs.getString(_voicingIncrementKey);
    return stored == KeyIncrement.fifths.name
        ? KeyIncrement.fifths
        : KeyIncrement.chromatic;
  }

  Future<void> setVoicingIncrement(KeyIncrement increment) async {
    await _prefs.setString(_voicingIncrementKey, increment.name);
  }

  /// Whether the target dots hint is shown on the keyboard. Default on.
  Future<bool> voicingShowDots() async =>
      await _prefs.getBool(_voicingShowDotsKey) ?? true;

  Future<void> setVoicingShowDots(bool on) async {
    await _prefs.setBool(_voicingShowDotsKey, on);
  }

  /// Whether the degree formula is shown under the key. Default on.
  Future<bool> voicingShowFormula() async =>
      await _prefs.getBool(_voicingShowFormulaKey) ?? true;

  Future<void> setVoicingShowFormula(bool on) async {
    await _prefs.setBool(_voicingShowFormulaKey, on);
  }

  // ---- Pro trial sessions ----
  // Mode identifiers used both for the trial counters below and for matching
  // a session's mode when deciding whether it just consumed a free trial.
  // Stable strings (not enum names) so they survive refactors.
  static const String modeScaleRun = 'scale_run';
  static const String modeInversionRun = 'inversion_run';
  static const String modeJam = 'jam';

  /// How many free sessions each Pro mode grants before the paywall sticks.
  static const int freeTrialSessions = 3;

  static String _trialCountKeyFor(String mode) => 'trial_count_$mode';

  /// Pre-3-attempt builds stored a single bool. Read only, for migration.
  static String _legacyTrialUsedKeyFor(String mode) => 'trial_used_$mode';

  /// How many free sessions of [mode] have been played. Users upgrading from
  /// a build with the old one-shot trial count as having used exactly one, so
  /// they gain the two extra attempts rather than losing their history.
  Future<int> trialsUsed(String mode) async {
    final count = await _prefs.getInt(_trialCountKeyFor(mode));
    if (count != null) return count;
    final legacy = await _prefs.getBool(_legacyTrialUsedKeyFor(mode)) ?? false;
    return legacy ? 1 : 0;
  }

  /// Free sessions of [mode] still available. Only meaningful without Pro.
  Future<int> trialsRemaining(String mode) async =>
      (freeTrialSessions - await trialsUsed(mode)).clamp(0, freeTrialSessions);

  /// Consume one free session of [mode] and return how many are left.
  /// Irreversible from the UI (no "reset trial" action).
  Future<int> consumeTrial(String mode) async {
    final used = (await trialsUsed(mode)) + 1;
    await _prefs.setInt(_trialCountKeyFor(mode), used);
    return (freeTrialSessions - used).clamp(0, freeTrialSessions);
  }

  // ---- Daily practice streak ----
  // Named daily_* to avoid colliding with the in-session `streak` concept
  // (consecutive correct answers). All values are owned by StreakService;
  // dates are yyyy-MM-dd in device-local time.
  static const _dailyStreakCurrentKey = 'daily_streak_current';
  static const _dailyStreakBestKey = 'daily_streak_best';
  static const _dailyStreakTotalKey = 'daily_streak_total_days';
  static const _dailyStreakLastDateKey = 'daily_streak_last_date';
  static const _dailyStreakFreezeWeekKey = 'daily_streak_freeze_used_week';

  Future<int> dailyStreakCurrent() async =>
      await _prefs.getInt(_dailyStreakCurrentKey) ?? 0;

  Future<void> setDailyStreakCurrent(int v) async =>
      _prefs.setInt(_dailyStreakCurrentKey, v);

  Future<int> dailyStreakBest() async =>
      await _prefs.getInt(_dailyStreakBestKey) ?? 0;

  Future<void> setDailyStreakBest(int v) async =>
      _prefs.setInt(_dailyStreakBestKey, v);

  Future<int> dailyStreakTotalDays() async =>
      await _prefs.getInt(_dailyStreakTotalKey) ?? 0;

  Future<void> setDailyStreakTotalDays(int v) async =>
      _prefs.setInt(_dailyStreakTotalKey, v);

  /// The last practiced local date as `yyyy-MM-dd`, or null if never.
  Future<String?> dailyStreakLastDate() async =>
      _prefs.getString(_dailyStreakLastDateKey);

  Future<void> setDailyStreakLastDate(String yyyyMmDd) async =>
      _prefs.setString(_dailyStreakLastDateKey, yyyyMmDd);

  /// The ISO week ("2026-W28") in which the Pro streak freeze was last used,
  /// or null if never. One freeze per ISO week.
  Future<String?> dailyStreakFreezeWeek() async =>
      _prefs.getString(_dailyStreakFreezeWeekKey);

  Future<void> setDailyStreakFreezeWeek(String isoWeek) async =>
      _prefs.setString(_dailyStreakFreezeWeekKey, isoWeek);

  // ---- Practice reminders ----
  static const _remindersEnabledKey = 'reminders_enabled';
  static const _reminderHourKey = 'reminder_hour';
  static const _reminderMinuteKey = 'reminder_minute';
  static const _reminderPromptSeenKey = 'reminder_prompt_seen';

  /// Whether practice reminder notifications are on. Default off — the user
  /// opts in via the post-first-session prompt or Settings.
  Future<bool> remindersEnabled() async =>
      await _prefs.getBool(_remindersEnabledKey) ?? false;

  Future<void> setRemindersEnabled(bool on) async =>
      _prefs.setBool(_remindersEnabledKey, on);

  /// Daily reminder time. Default 18:00.
  Future<(int hour, int minute)> reminderTime() async => (
        await _prefs.getInt(_reminderHourKey) ?? 18,
        await _prefs.getInt(_reminderMinuteKey) ?? 0,
      );

  Future<void> setReminderTime(int hour, int minute) async {
    await _prefs.setInt(_reminderHourKey, hour);
    await _prefs.setInt(_reminderMinuteKey, minute);
  }

  /// Whether the one-time "want a daily reminder?" prompt has been shown.
  Future<bool> reminderPromptSeen() async =>
      await _prefs.getBool(_reminderPromptSeenKey) ?? false;

  Future<void> setReminderPromptSeen() async =>
      _prefs.setBool(_reminderPromptSeenKey, true);

  // ---- Social ----
  static const _socialPendingStreakKey = 'social_pending_streak';
  static const _socialSeenAtKey = 'social_activity_seen_at';
  static const _socialWeeklyKey = 'social_weekly_current';
  static const _socialWeeklyDirtyKey = 'social_weekly_dirty';
  static const _socialModeStatsDirtyKey = 'social_mode_stats_dirty';

  /// A streak payload ("current|best|total") that couldn't be pushed to the
  /// backend yet (offline / transient error), or null when fully synced.
  Future<String?> socialPendingStreak() async =>
      _prefs.getString(_socialPendingStreakKey);

  Future<void> setSocialPendingStreak(String? encoded) async =>
      encoded == null
          ? _prefs.remove(_socialPendingStreakKey)
          : _prefs.setString(_socialPendingStreakKey, encoded);

  /// When the activity feed was last viewed (ISO-8601 UTC), for the unread
  /// badge on "friend joined" items. Applause read-state lives server-side.
  Future<String?> socialActivitySeenAt() async =>
      _prefs.getString(_socialSeenAtKey);

  Future<void> setSocialActivitySeenAt(String iso) async =>
      _prefs.setString(_socialSeenAtKey, iso);

  /// This ISO week's practice-mode aggregate (an encoded [WeeklyStat]), or
  /// null before any practice this week. See SocialService for the schema.
  Future<String?> socialWeeklyCurrent() async =>
      _prefs.getString(_socialWeeklyKey);

  Future<void> setSocialWeeklyCurrent(String encoded) async =>
      _prefs.setString(_socialWeeklyKey, encoded);

  /// Whether the local weekly aggregate has changes not yet pushed to Supabase.
  Future<bool> socialWeeklyDirty() async =>
      await _prefs.getBool(_socialWeeklyDirtyKey) ?? false;

  Future<void> setSocialWeeklyDirty(bool v) async =>
      _prefs.setBool(_socialWeeklyDirtyKey, v);

  /// Whether the local per-mode totals have changes not yet pushed to Supabase.
  Future<bool> socialModeStatsDirty() async =>
      await _prefs.getBool(_socialModeStatsDirtyKey) ?? false;

  Future<void> setSocialModeStatsDirty(bool v) async =>
      _prefs.setBool(_socialModeStatsDirtyKey, v);

  /// Encode `key → (attempts, correct)` as `"key|attempts|correct"` lines. Keys
  /// (quality suffixes, Roman numerals) never contain a pipe.
  static List<String> _encodeStats(Map<String, (int, int)> stats) =>
      [for (final e in stats.entries) '${e.key}|${e.value.$1}|${e.value.$2}'];

  static Map<String, (int, int)> _decodeStats(List<String>? lines) {
    final out = <String, (int, int)>{};
    if (lines == null) return out;
    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length != 3) continue;
      final attempts = int.tryParse(parts[1]);
      final correct = int.tryParse(parts[2]);
      if (attempts == null || correct == null) continue;
      out[parts[0]] = (attempts, correct);
    }
    return out;
  }

  static Map<String, (int, int)> _mergeStats(
    Map<String, (int, int)> base,
    Map<String, (int, int)> add,
  ) {
    final out = Map<String, (int, int)>.from(base);
    add.forEach((k, v) {
      final cur = out[k] ?? (0, 0);
      out[k] = (cur.$1 + v.$1, cur.$2 + v.$2);
    });
    return out;
  }

  // ---- Latency Configuration ------------------------------------------------

  Future<int?> inputLatencyMs(String deviceName) async {
    return _prefs.getInt(_latencyKeyFor(deviceName));
  }

  Future<void> setInputLatencyMs(String deviceName, int ms) async {
    await _prefs.setInt(_latencyKeyFor(deviceName), ms);
  }
}
