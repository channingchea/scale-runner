import 'package:shared_preferences/shared_preferences.dart';

import '../theory/music_theory.dart';
import '../theory/scale_running.dart';
import 'quiz_controller.dart';

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

  static String _formulaHintKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'hint_formula_scales' : 'hint_formula_chords';

  static String _dotsHintKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'hint_dots_scales' : 'hint_dots_chords';

  static String _statsBarKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'stats_bar_scales' : 'stats_bar_chords';

  static String _beatIndicatorKeyFor(QuizMode mode) =>
      mode == QuizMode.scale ? 'beat_indicator_scales' : 'beat_indicator_chords';

  static const _metronomeBpmKey = 'metronome_bpm';
  static const _noteSoundKey = 'note_sound';
  static const _introSeenKey = 'intro_seen';

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

  // Inversion Running drill.
  static const _invChordsKey = 'inv_chords';
  static const _invTempoKey = 'inv_tempo';
  static const _invShowDotsKey = 'inv_show_dots';
  static const _invShowFormulaKey = 'inv_show_formula';

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

  /// Whether key presses sound a piano note, shared across modes. Default on.
  Future<bool> noteSoundEnabled() async =>
      await _prefs.getBool(_noteSoundKey) ?? true;

  Future<void> setNoteSoundEnabled(bool on) async {
    await _prefs.setBool(_noteSoundKey, on);
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
}
