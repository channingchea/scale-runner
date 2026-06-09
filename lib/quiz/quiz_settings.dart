import 'package:shared_preferences/shared_preferences.dart';

import '../theory/music_theory.dart';
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
}
