/// Pure-Dart music theory core.
///
/// No UI, no MIDI, no I/O — just the domain model and the data the quiz
/// validators run against. Fully testable without hardware.
library;

/// Names of the 12 pitch classes (sharp spelling).
const List<String> pitchClassNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

/// Pitch class (0–11) of a MIDI note number. Middle C (60) -> 0.
int pitchClassOf(int midiNote) => midiNote % 12;

/// Octave of a MIDI note in scientific pitch notation (middle C = C4).
int octaveOf(int midiNote) => (midiNote ~/ 12) - 1;

/// Human-readable name of a MIDI note, e.g. 60 -> "C4", 61 -> "C#4".
String noteName(int midiNote) =>
    '${pitchClassNames[pitchClassOf(midiNote)]}${octaveOf(midiNote)}';

/// Default flat-spelled degree label for each semitone offset 0..11.
const List<String> _flatLabels = [
  '1', 'b2', '2', 'b3', '3', '4', 'b5', '5', 'b6', '6', 'b7', '7',
];

/// Renders semitone offsets as degree notation. Flat-spelled by default, with
/// two context-dependent sharp respellings so the reading matches how the chord
/// or scale actually functions:
///   - the tritone (6) reads "#4" when a perfect 5th (7) is present and there is
///     no perfect 4th (5) — e.g. Lydian "1-2-3-#4-5-6-7" — but stays "b5" in a
///     diminished context (Blues "…-4-b5-5-…", Locrian, dim/m7b5 chords).
///   - the augmented 5th (8) reads "#5" when there is no perfect 5th (7) but a
///     major 3rd (4) is present — e.g. Augmented "1-3-#5" — otherwise "b6".
///   - the major 6th / diminished 7th (9) reads "bb7" in a fully-diminished
///     context (b3 and b5 present, no perfect 5th) — e.g. Diminished 7th
///     "1-b3-b5-bb7" — otherwise "6" (Major 6th, Minor 6th, pentatonics).
String formulaOf(List<int> intervals) {
  final pcs = {for (final i in intervals) i % 12};
  return [
    for (final raw in intervals)
      switch (raw % 12) {
        6 when pcs.contains(7) && !pcs.contains(5) => '#4',
        8 when !pcs.contains(7) && pcs.contains(4) => '#5',
        9 when pcs.contains(3) && pcs.contains(6) && !pcs.contains(7) => 'bb7',
        final i => _flatLabels[i],
      }
  ].join('-');
}

/// A scale defined by its name and ascending semitone offsets from the root.
///
/// The root itself is offset 0. Example: major = [0,2,4,5,7,9,11].
class ScaleFormula {
  final String name;
  final List<int> intervals;
  const ScaleFormula(this.name, this.intervals);

  /// Degree notation, e.g. "1-2-b3-4-5-b6-b7".
  String get formula => formulaOf(intervals);

  /// Ascending MIDI notes for this scale from [rootMidi], spanning one octave.
  /// When [includeOctave] is true the octave root is appended on top, so the
  /// run reads "do-re-mi…do".
  List<int> notesFrom(int rootMidi, {bool includeOctave = true}) {
    final notes = [for (final i in intervals) rootMidi + i];
    if (includeOctave) notes.add(rootMidi + 12);
    return notes;
  }

  /// The set of pitch classes this scale contains in [rootPc]'s key.
  Set<int> pitchClasses(int rootPc) =>
      {for (final i in intervals) (rootPc + i) % 12};
}

/// A chord defined by its name and semitone offsets from the root.
///
/// Example: major triad = [0,4,7]; dominant 7th = [0,4,7,10].
class ChordFormula {
  final String name;
  final List<int> intervals;
  const ChordFormula(this.name, this.intervals);

  /// Degree notation, e.g. "1-b3-5-b7".
  String get formula => formulaOf(intervals);

  /// MIDI notes of this chord in root position from [rootMidi].
  List<int> notesFrom(int rootMidi) => [for (final i in intervals) rootMidi + i];

  /// MIDI notes of the given [n] inversion (0 = root position).
  ///
  /// Each inversion moves the lowest remaining note up an octave — the
  /// standard definition of a chord inversion.
  List<int> inversion(int rootMidi, int n) {
    final notes = notesFrom(rootMidi);
    for (var step = 0; step < n; step++) {
      notes.sort();
      notes[0] += 12;
    }
    notes.sort();
    return notes;
  }

  /// Number of distinct inversions (equals the number of chord tones).
  int get inversionCount => intervals.length;

  /// The set of pitch classes in this chord rooted at [rootPc]
  /// (inversion-independent).
  Set<int> pitchClasses(int rootPc) =>
      {for (final i in intervals) (rootPc + i) % 12};
}

/// Library of the most common scales. Intervals are semitones from the root.
const List<ScaleFormula> commonScales = [
  ScaleFormula('Major (Ionian)', [0, 2, 4, 5, 7, 9, 11]),
  ScaleFormula('Natural Minor (Aeolian)', [0, 2, 3, 5, 7, 8, 10]),
  ScaleFormula('Harmonic Minor', [0, 2, 3, 5, 7, 8, 11]),
  ScaleFormula('Melodic Minor (asc)', [0, 2, 3, 5, 7, 9, 11]),
  ScaleFormula('Dorian', [0, 2, 3, 5, 7, 9, 10]),
  ScaleFormula('Phrygian', [0, 1, 3, 5, 7, 8, 10]),
  ScaleFormula('Lydian', [0, 2, 4, 6, 7, 9, 11]),
  ScaleFormula('Mixolydian', [0, 2, 4, 5, 7, 9, 10]),
  ScaleFormula('Locrian', [0, 1, 3, 5, 6, 8, 10]),
  ScaleFormula('Major Pentatonic', [0, 2, 4, 7, 9]),
  ScaleFormula('Minor Pentatonic', [0, 3, 5, 7, 10]),
  ScaleFormula('Blues', [0, 3, 5, 6, 7, 10]),
  ScaleFormula('Chromatic', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
];

/// Library of the most common chords. Intervals are semitones from the root.
const List<ChordFormula> commonChords = [
  ChordFormula('Major', [0, 4, 7]),
  ChordFormula('Minor', [0, 3, 7]),
  ChordFormula('Diminished', [0, 3, 6]),
  ChordFormula('Augmented', [0, 4, 8]),
  ChordFormula('Sus2', [0, 2, 7]),
  ChordFormula('Sus4', [0, 5, 7]),
  ChordFormula('Major 7th', [0, 4, 7, 11]),
  ChordFormula('Dominant 7th', [0, 4, 7, 10]),
  ChordFormula('Minor 7th', [0, 3, 7, 10]),
  ChordFormula('Minor 7th flat 5', [0, 3, 6, 10]),
  ChordFormula('Diminished 7th', [0, 3, 6, 9]),
  ChordFormula('Major 6th', [0, 4, 7, 9]),
  ChordFormula('Minor 6th', [0, 3, 7, 9]),
];
