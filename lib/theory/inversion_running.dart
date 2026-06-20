/// Pure-Dart theory for the Inversion Running drill.
///
/// No UI, no MIDI, no timing — just the ordered voicings of one chord's
/// inversions, climbed up a full octave and back down. Fully unit-testable,
/// same pattern as `scale_running.dart`.
library;

import 'music_theory.dart';

/// The fixed display octave the round's root is transposed into. The
/// transposing keyboard (this mode only) places its lowest key at the round's
/// root, so anchoring every root to one octave keeps the climb inside ~2
/// octaves of range regardless of key. Root pitch classes map into MIDI
/// [_anchorOctaveBase] .. [_anchorOctaveBase] + 11 (i.e. octave 4: 60–71).
const int _anchorOctaveBase = 60; // C4

/// Inversion-name label for inversion [n] (0 = Root, 1 = 1st inversion, …).
String inversionLabel(int n) => n == 0
    ? 'Root'
    : '${_ordinal(n)} inversion';

String _ordinal(int n) => switch (n) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      _ => '${n}th',
    };

/// Rotate a degree formula ("1-3-5") left by [n] so it reads bass-up for
/// inversion [n] ("3-5-1" for 1st, "5-1-3" for 2nd). Tokens (which may carry
/// accidentals like "b3") are rotated whole.
String _rotateFormula(String formula, int n) {
  final tokens = formula.split('-');
  if (tokens.isEmpty) return formula;
  final shift = n % tokens.length;
  return [...tokens.sublist(shift), ...tokens.sublist(0, shift)].join('-');
}

/// One voicing in the cycle: the [inversion] index, its MIDI [notes], a
/// display [label], and the chord's pitch classes for octave-tolerant
/// validation.
class InversionStep {
  /// Inversion index for this step (0 = root position). The octave-up root at
  /// the apex carries the chord's [ChordFormula.inversionCount] here.
  final int inversion;

  /// Exact transposed MIDI voicing to highlight (target dots).
  final List<int> notes;

  /// Display label, e.g. "Root", "1st inversion", or "Root (8va)" at the apex.
  final String label;

  /// Bass-up degree spelling for this inversion, e.g. "1-3-5", "3-5-1",
  /// "5-1-3". The apex carries "(8va)" appended.
  final String formula;

  /// Whether this step is the octave-up root at the top of the climb.
  final bool isOctaveRoot;

  const InversionStep({
    required this.inversion,
    required this.notes,
    required this.label,
    required this.formula,
    required this.isOctaveRoot,
  });

  /// Pitch-class set of this voicing — identical for every step in a cycle,
  /// so validation stays octave-tolerant while [notes] drive the display.
  Set<int> get pitchClasses => {for (final n in notes) n % 12};

  /// Pitch class of this inversion's bass (lowest) note. Unlike [pitchClasses]
  /// (shared by every step), the bass uniquely identifies the inversion — root
  /// position has the root in the bass, 1st inversion the 3rd, etc. — so it's
  /// what validation checks to confirm the player is actually inverting.
  /// [notes] is sorted ascending, so the first note is the bass.
  int get bassPc => notes.first % 12;
}

/// The full up-then-down inversion cycle for one chord in one key.
///
/// Triads (3 tones) run 7 steps: Root → 1st → 2nd → Root(8va) → 2nd → 1st →
/// Root. 7th chords (4 tones) run 9 steps with the extra 3rd inversion. The
/// climb ascends inversions 0…N (where step N is the same shape an octave up),
/// then descends N−1…0. The top octave-root is NOT repeated on the way down.
class InversionCycle {
  final ChordFormula chord;

  /// Pitch class (0–11) of the round's root.
  final int rootPc;

  /// MIDI note the keyboard's lowest key sits on this round (the root in the
  /// fixed display octave). The transposing keyboard anchors here.
  final int lowMidi;

  /// Ordered voicings: ascending inversions then descending, apex once.
  final List<InversionStep> steps;

  InversionCycle._(this.chord, this.rootPc, this.lowMidi, this.steps);

  /// Build the cycle for [chord] rooted at [rootPc] (0–11). The root is placed
  /// in the fixed display octave so the keyboard transposes per round.
  factory InversionCycle(ChordFormula chord, int rootPc) {
    final root = rootPc % 12;
    final lowMidi = _anchorOctaveBase + root;
    final n = chord.inversionCount; // 3 for triads, 4 for 7ths
    // Ascend 0..n (step n = root an octave up), then descend n-1..0.
    final order = [
      for (var i = 0; i <= n; i++) i,
      for (var i = n - 1; i >= 0; i--) i,
    ];
    final baseFormula = chord.formula;
    final steps = [
      for (final inv in order)
        InversionStep(
          inversion: inv,
          notes: chord.inversion(lowMidi, inv),
          label: inv == n ? 'Root (8va)' : inversionLabel(inv),
          formula: inv == n
              ? '${_rotateFormula(baseFormula, inv)} (8va)'
              : _rotateFormula(baseFormula, inv),
          isOctaveRoot: inv == n,
        ),
    ];
    return InversionCycle._(chord, root, lowMidi, steps);
  }

  /// Number of steps in the cycle (7 for triads, 9 for 7th chords).
  int get length => steps.length;

  /// "{Root} {Chord}", e.g. "C Major" or "D Minor 7th".
  String get label => '${pitchClassNames[rootPc]} ${chord.name}';

  /// The chord's pitch classes in this key (same for every step).
  Set<int> get pitchClasses => chord.pitchClasses(rootPc);
}
