/// Pure-Dart theory for the Scale Running drill.
///
/// No UI, no MIDI, no timing — just diatonic harmony: which chord to hold and
/// which mode to run for each degree of a progression, plus key cycling.
/// Fully unit-testable, same pattern as `music_theory.dart`.
library;

import 'music_theory.dart';

/// Major-scale intervals — the basis for diatonic chords and modes.
const List<int> _majorIntervals = [0, 2, 4, 5, 7, 9, 11];

/// Mode name of each major-scale degree 1–7.
const List<String> modeNames = [
  'Ionian', 'Dorian', 'Phrygian', 'Lydian', 'Mixolydian', 'Aeolian', 'Locrian',
];

/// How the key root advances after a full pass of the progression.
enum KeyIncrement { chromatic, fifths }

/// Advances a key root pitch class by semitone or by fifths.
class KeyCycler {
  final KeyIncrement increment;
  const KeyCycler(this.increment);

  int next(int rootPc) =>
      (rootPc + (increment == KeyIncrement.chromatic ? 1 : 7)) % 12;
}

/// A named sequence of scale degrees (1–7), one chord per 8-beat bar.
class ChordProgression {
  final String name;
  final List<int> degrees;
  const ChordProgression(this.name, this.degrees);
}

/// Preset progressions for v1 (no custom builder yet).
const List<ChordProgression> commonProgressions = [
  ChordProgression('1-6-2-5', [1, 6, 2, 5]),
  ChordProgression('2-5-1', [2, 5, 1]),
  ChordProgression('1-4-5', [1, 4, 5]),
  ChordProgression('1-5-6-4', [1, 5, 6, 4]),
  ChordProgression('12-bar blues', [1, 1, 1, 1, 4, 4, 1, 1, 5, 4, 1, 1]),
];

/// One 8-beat slot of the drill: hold [chordPcs] while running [runPcs],
/// one note per beat (beat 0 = chord + run degree 1, beat 7 = octave root).
class RunStep {
  final int degree; // scale degree 1–7 (1 in no-chords mode)
  final Set<int> chordPcs; // empty in no-chords mode
  final List<int> runPcs; // exactly 8 pitch classes, beats 0–7
  final String chordLabel; // e.g. "D Minor 7th" ('' in no-chords mode)
  final String modeLabel; // e.g. "D Dorian"

  const RunStep({
    required this.degree,
    required this.chordPcs,
    required this.runPcs,
    required this.chordLabel,
    required this.modeLabel,
  });
}

/// Diatonic chords and modes of a major key rooted at [keyRootPc].
class DiatonicHarmony {
  final int keyRootPc;

  /// Stack diatonic 7th chords instead of triads.
  final bool sevenths;

  const DiatonicHarmony(this.keyRootPc, {this.sevenths = false});

  /// Pitch class of scale [degree] (1–7) in this key.
  int degreePc(int degree) =>
      (keyRootPc + _majorIntervals[(degree - 1) % 7]) % 12;

  /// The diatonic chord on [degree]: thirds stacked within the key.
  Set<int> chordPcs(int degree) => {
        for (var i = 0; i < (sevenths ? 4 : 3); i++)
          degreePc((degree - 1 + 2 * i) % 7 + 1),
      };

  /// The 8 ascending run pitch classes of [degree]'s mode: the major scale
  /// rotated to start on that degree, plus the octave root on top.
  List<int> runPcs(int degree) {
    final run = [
      for (var i = 0; i < 7; i++) degreePc((degree - 1 + i) % 7 + 1),
    ];
    return [...run, run.first];
  }

  /// The chord quality on [degree], matched by interval shape against the
  /// shared [commonChords] library (e.g. degree 2 → Minor / Minor 7th).
  ChordFormula chordQuality(int degree) {
    final root = degreePc(degree);
    final shape = chordPcs(degree).map((pc) => (pc - root) % 12).toList()
      ..sort();
    return commonChords.firstWhere((c) {
      final ref = [...c.intervals]..sort();
      if (ref.length != shape.length) return false;
      for (var i = 0; i < ref.length; i++) {
        if (ref[i] != shape[i]) return false;
      }
      return true;
    });
  }

  /// The full [RunStep] for [degree].
  RunStep stepFor(int degree) {
    final root = degreePc(degree);
    return RunStep(
      degree: degree,
      chordPcs: chordPcs(degree),
      runPcs: runPcs(degree),
      chordLabel: '${pitchClassNames[root]} ${chordQuality(degree).name}',
      modeLabel: '${pitchClassNames[root]} ${modeNames[(degree - 1) % 7]}',
    );
  }

  /// Expand a progression into its run steps for this key.
  List<RunStep> expand(ChordProgression progression) =>
      [for (final d in progression.degrees) stepFor(d)];

  /// The no-chords drill step: just the key's scale run, nothing to hold.
  /// The scale must have 7 tones so the run fills the 8-beat bar (1→8).
  RunStep scaleOnlyStep({ScaleFormula? scale}) {
    final s = scale ?? commonScales.first; // Major (Ionian)
    assert(s.intervals.length == 7, 'scale run needs a 7-note scale');
    final run = [for (final i in s.intervals) (keyRootPc + i) % 12];
    return RunStep(
      degree: 1,
      chordPcs: const {},
      runPcs: [...run, run.first],
      chordLabel: '',
      modeLabel: '${pitchClassNames[keyRootPc]} ${s.name}',
    );
  }
}
