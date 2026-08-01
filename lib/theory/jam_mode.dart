/// Pure-Dart theory for the Jam Mode drill.
///
/// No UI, no MIDI, no timing — just the diatonic chords of one major key across
/// four chord families (triads, 7ths, 9ths, sus2/sus4), each carrying a Roman
/// numeral, a display name, a degree formula, and its pitch-class set for
/// octave-free validation. Plus a no-immediate-repeat random prompt picker.
/// Fully unit-testable, same pattern as `scale_running.dart`.
library;

import 'dart:math';

import 'music_theory.dart';
import 'scale_running.dart';

/// The four diatonic chord families Jam Mode can prompt. Each is toggleable in
/// settings; the enabled set is never empty (enforced by the UI).
enum JamFamily { triad, seventh, ninth, sus }

/// Short settings label for a family.
extension JamFamilyLabel on JamFamily {
  String get label => switch (this) {
        JamFamily.triad => 'Triads',
        JamFamily.seventh => '7th chords',
        JamFamily.ninth => '9th chords',
        JamFamily.sus => 'Sus2 / Sus4',
      };
}

/// The base triad quality of a diatonic degree, used to name and Roman-number
/// every family built on it.
enum _TriadQuality { major, minor, diminished }

/// One prompt-able diatonic chord in a fixed key: the [degree] it sits on, the
/// [family] it belongs to, its octave-free [pitchClasses] for validation, and
/// the display strings (Roman numeral, name, degree formula).
class JamChord {
  /// Scale degree 1–7 this chord is rooted on.
  final int degree;

  /// Which family this voicing belongs to.
  final JamFamily family;

  /// Sus variant: 2 or 4 for [JamFamily.sus], otherwise 0.
  final int susType;

  /// Octave-free pitch-class set for validation. Any inversion/octave passes,
  /// chord tones may be doubled, any non-chord-tone fails.
  final Set<int> pitchClasses;

  /// Roman numeral with diatonic casing (uppercase major, lowercase minor,
  /// trailing ° for diminished), e.g. "I", "ii", "vii°".
  final String roman;

  /// Display name, e.g. "C", "Dm7", "Gmaj9", "Asus4".
  final String name;

  /// Degree spelling, e.g. "1-3-5", "1-b3-5-b7-9", "1-4-5".
  final String formula;

  const JamChord({
    required this.degree,
    required this.family,
    required this.susType,
    required this.pitchClasses,
    required this.roman,
    required this.name,
    required this.formula,
  });

  /// Prompt label shown on screen, e.g. "ii — Dm7".
  String get prompt => '$roman — $name';

  /// Quality key for per-quality scoring, e.g. "maj", "min", "dim", "maj7",
  /// "dom7", "m7", "m7b5", "maj9", "9", "m9", "m9b5", "sus2", "sus4". It's the
  /// name's suffix (the part after the root letter / accidental).
  String get qualityKey {
    // Strip the leading root: an uppercase letter optionally followed by '#'.
    var i = 1;
    if (i < name.length && name[i] == '#') i++;
    final suffix = name.substring(i);
    return suffix.isEmpty ? 'maj' : suffix;
  }

  /// Degree key for per-degree scoring — the diatonic Roman numeral (I–vii°).
  String get degreeKey => roman;

  /// Stable identity for no-immediate-repeat comparison: same degree, family,
  /// and sus variant is the "same" prompt.
  Object get key => '$degree:${family.index}:$susType';
}

/// Builds the diatonic chords of one major key across all four families and
/// serves random, non-repeating prompts from an enabled subset.
class JamKey {
  /// Pitch class (0–11) of the key root.
  final int rootPc;

  /// Underlying diatonic harmony (degree pitch classes + base triads).
  final DiatonicHarmony _h;

  JamKey(this.rootPc) : _h = DiatonicHarmony(rootPc);

  /// "{Root} Major", e.g. "C Major" — the key label for the header.
  String get label => '${pitchClassNames[rootPc]} Major';

  /// Root pitch class (0–11) of scale [degree] (1–7). Public so
  /// [JamChordMatcher] can break root ambiguity against the lowest held note.
  int rootPcOf(int degree) => _h.degreePc(degree);

  /// The 7 diatonic pitch classes of this key. Used for Freestyle's
  /// scale-based keyboard hints (dots + out-of-key red).
  late final Set<int> scalePcs = {
    for (var d = 1; d <= 7; d++) _h.degreePc(d),
  };

  /// Base triad quality of [degree] (1–7) in a major key.
  _TriadQuality _quality(int degree) {
    final triad = _h.chordPcs(degree);
    final root = _h.degreePc(degree);
    final shape = triad.map((pc) => (pc - root) % 12).toSet();
    if (shape.containsAll({4, 7})) return _TriadQuality.major;
    if (shape.containsAll({3, 6})) return _TriadQuality.diminished;
    return _TriadQuality.minor; // {3,7}
  }

  /// Roman numeral for [degree] with diatonic casing and a ° for diminished.
  String roman(int degree) {
    const numerals = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];
    final q = _quality(degree);
    final base = numerals[(degree - 1) % 7];
    return switch (q) {
      _TriadQuality.major => base,
      _TriadQuality.minor => base.toLowerCase(),
      _TriadQuality.diminished => '${base.toLowerCase()}°',
    };
  }

  /// The pitch class of the diatonic degree [step] above [degree] (1-indexed
  /// scale steps: step 2 = a third up, step 8 = the ninth).
  int _degreeUp(int degree, int step) => _h.degreePc((degree - 1 + step) % 7 + 1);

  /// Pitch-class set of [degree]'s chord in [family]. Sus uses [susType] (2/4).
  Set<int> _pcs(int degree, JamFamily family, {int susType = 0}) {
    switch (family) {
      case JamFamily.triad:
        return _h.chordPcs(degree); // 1-3-5
      case JamFamily.seventh:
        return {..._h.chordPcs(degree), _degreeUp(degree, 6)}; // +7th
      case JamFamily.ninth:
        return {
          ..._h.chordPcs(degree),
          _degreeUp(degree, 6), // 7th
          _degreeUp(degree, 8), // 9th
        };
      case JamFamily.sus:
        // Replace the 3rd (step 2) with the 2nd (step 1) or 4th (step 3).
        final replacement = _degreeUp(degree, susType == 2 ? 1 : 3);
        return {_h.degreePc(degree), replacement, _degreeUp(degree, 4)};
    }
  }

  /// Degree formula for [degree]'s chord in [family].
  String _formula(int degree, JamFamily family, {int susType = 0}) =>
      switch (family) {
        JamFamily.triad => _triadFormula(degree),
        JamFamily.seventh => '${_triadFormula(degree)}-${_seventhDeg(degree)}',
        JamFamily.ninth =>
          '${_triadFormula(degree)}-${_seventhDeg(degree)}-9',
        JamFamily.sus => susType == 2
            ? '1-2-5'
            : '1-4-5',
      };

  /// Triad degree spelling, e.g. "1-3-5", "1-b3-5", "1-b3-b5".
  String _triadFormula(int degree) => switch (_quality(degree)) {
        _TriadQuality.major => '1-3-5',
        _TriadQuality.minor => '1-b3-5',
        _TriadQuality.diminished => '1-b3-b5',
      };

  /// The 7th's degree token: "7" on I/IV (major 7th), "b7" elsewhere, "b7" on
  /// vii° (m7b5). Determined from the actual interval so it stays correct.
  String _seventhDeg(int degree) {
    final root = _h.degreePc(degree);
    final seventh = (_degreeUp(degree, 6) - root) % 12;
    return seventh == 11 ? '7' : 'b7';
  }

  /// Name suffix for a family on a degree, appended to the root letter.
  String _suffix(int degree, JamFamily family, {int susType = 0}) {
    final q = _quality(degree);
    switch (family) {
      case JamFamily.triad:
        return switch (q) {
          _TriadQuality.major => '',
          _TriadQuality.minor => 'm',
          _TriadQuality.diminished => 'dim',
        };
      case JamFamily.seventh:
        // A major triad with a minor 7th is dominant (V7), not maj7.
        final dominant = q == _TriadQuality.major && _seventhDeg(degree) == 'b7';
        return switch (q) {
          _TriadQuality.major => dominant ? '7' : 'maj7',
          _TriadQuality.minor => 'm7',
          _TriadQuality.diminished => 'm7b5',
        };
      case JamFamily.ninth:
        final dominant = q == _TriadQuality.major && _seventhDeg(degree) == 'b7';
        return switch (q) {
          _TriadQuality.major => dominant ? '9' : 'maj9',
          _TriadQuality.minor => 'm9',
          _TriadQuality.diminished => 'm9b5',
        };
      case JamFamily.sus:
        return susType == 2 ? 'sus2' : 'sus4';
    }
  }

  /// The [JamChord] for [degree] in [family] (sus needs [susType] 2 or 4).
  JamChord chord(int degree, JamFamily family, {int susType = 0}) {
    final root = _h.degreePc(degree);
    return JamChord(
      degree: degree,
      family: family,
      susType: family == JamFamily.sus ? susType : 0,
      pitchClasses: _pcs(degree, family, susType: susType),
      roman: roman(degree),
      name:
          '${pitchClassNames[root]}${_suffix(degree, family, susType: susType)}',
      formula: _formula(degree, family, susType: susType),
    );
  }

  /// Every prompt-able chord for an [enabled] family set, degrees 1–7. Sus
  /// contributes both sus2 and sus4 per degree. Diminished degrees are kept in
  /// all families (vii°maj9 etc. are legal diatonic stacks).
  List<JamChord> prompts(Set<JamFamily> enabled) => [
        for (var d = 1; d <= 7; d++)
          for (final f in JamFamily.values)
            if (enabled.contains(f))
              if (f == JamFamily.sus) ...[
                chord(d, f, susType: 2),
                chord(d, f, susType: 4),
              ] else
                chord(d, f),
      ];
}

/// Draws random prompts from a fixed pool, never repeating the one just shown.
///
/// Pure and seedable for testing. The pool comes from [JamKey.prompts] for the
/// current key and enabled families; rebuild the picker when either changes.
class JamPromptPicker {
  final List<JamChord> _pool;
  final Random _rng;
  JamChord? _last;

  JamPromptPicker(List<JamChord> pool, {Random? rng})
      : assert(pool.isNotEmpty, 'prompt pool must not be empty'),
        _pool = List.unmodifiable(pool),
        _rng = rng ?? Random();

  /// The last chord served, or null before the first [next].
  JamChord? get last => _last;

  /// Next chord — uniformly random, but never the same identity as the last
  /// (unless the pool has only one entry, which can only repeat itself).
  JamChord next() {
    if (_pool.length == 1) return _last = _pool.first;
    JamChord pick;
    do {
      pick = _pool[_rng.nextInt(_pool.length)];
    } while (_last != null && pick.key == _last!.key);
    return _last = pick;
  }
}

/// Bitmask encoding of a pitch-class set (bit i set ⇔ pitch class i present) —
/// a fast, value-equal key for exact chord-shape lookups (`Set<int>` has no
/// content equality of its own).
int _pcMask(Iterable<int> pcs) => pcs.fold(0, (mask, pc) => mask | (1 << pc));

/// One candidate match for a held pitch-class set in Jam Mode Freestyle: the
/// diatonic [chord] it exactly matches, and whether that chord's family is
/// currently enabled (a disabled-family chord is still recognized — and
/// reported not-[enabled] — rather than silently read as wrong notes).
class JamChordMatch {
  final JamChord chord;
  final bool enabled;
  const JamChordMatch(this.chord, this.enabled);
}

/// Recognizes any diatonic chord in a key from a held pitch-class set, for
/// Jam Mode Freestyle (the player picks the chord instead of being prompted).
///
/// Indexed once per key from *all four* families regardless of which are
/// enabled, so a chord from a disabled family is still recognized as a real
/// (if currently illegal) diatonic chord rather than unrecognized noise.
///
/// Some pitch-class sets are shared by more than one diatonic chord (e.g. an
/// m7 and the relative major's 6th chord have identical pitch classes).
/// Ambiguity is resolved first by matching the lowest held note as the
/// chord's root, then — if that doesn't narrow it to one candidate — by
/// preferring whichever isn't the forbidden (just-played) degree.
class JamChordMatcher {
  final JamKey key;
  final Set<JamFamily> enabledFamilies;
  final Map<int, List<JamChord>> _index;

  JamChordMatcher(this.key, this.enabledFamilies)
      : _index = _buildIndex(key);

  static Map<int, List<JamChord>> _buildIndex(JamKey key) {
    final index = <int, List<JamChord>>{};
    for (final chord in key.prompts(JamFamily.values.toSet())) {
      index.putIfAbsent(_pcMask(chord.pitchClasses), () => []).add(chord);
    }
    return index;
  }

  /// Match [heldPcs] to a diatonic chord, or null if it isn't one (extra or
  /// missing notes, or a non-diatonic stack). [bassPc] is the pitch class of
  /// the lowest held note, used to break root ambiguity. [forbiddenDegree] is
  /// the scale degree (1–7) to avoid when a tie remains.
  JamChordMatch? match(Set<int> heldPcs, {int? bassPc, int? forbiddenDegree}) {
    if (heldPcs.isEmpty) return null;
    var candidates = _index[_pcMask(heldPcs)];
    if (candidates == null || candidates.isEmpty) return null;
    if (candidates.length > 1 && bassPc != null) {
      final byRoot =
          candidates.where((c) => key.rootPcOf(c.degree) == bassPc).toList();
      if (byRoot.isNotEmpty) candidates = byRoot;
    }
    if (candidates.length > 1 && forbiddenDegree != null) {
      final nonRepeat =
          candidates.where((c) => c.degree != forbiddenDegree).toList();
      if (nonRepeat.isNotEmpty) candidates = nonRepeat;
    }
    final chord = candidates.first;
    return JamChordMatch(chord, enabledFamilies.contains(chord.family));
  }
}
