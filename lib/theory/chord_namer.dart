/// Names whatever is sounding: a note, an interval, or a chord.
///
/// Pure Dart — no Flutter, no I/O. The reverse of the quiz: the quiz turns
/// a name into notes, this turns notes into a name. Used by Free Play.
library;

import 'dart:math' show max, min;

import 'music_theory.dart';

/// A chord type: its word-style name (matching the quiz prompts), a compact
/// symbol for a possible later setting, and its tones as semitones from the
/// root. Extensions are written compound (14 = 9th, 17 = 11th, 21 = 13th) so
/// the formula reads "1-3-5-b7-9" rather than "1-2-3-5-b7"; matching only
/// ever looks at the pitch classes.
class ChordQuality {
  const ChordQuality(this.name, this.symbol, this.intervals);

  final String name;
  final String symbol;
  final List<int> intervals;

  /// The tones reduced to pitch classes relative to the root.
  Set<int> get pitchClasses => {for (final i in intervals) i % 12};

  /// Degree notation, e.g. "1-b3-5-b7-9".
  String get formula => chordFormulaOf(intervals);
}

const Map<int, String> _compoundLabels = {
  13: 'b9', 14: '9', 15: '#9', 17: '11', 18: '#11', 20: 'b13', 21: '13',
};

/// [formulaOf] for chord intervals that may carry compound extensions.
String chordFormulaOf(List<int> intervals) {
  final simple = [for (final i in intervals) if (i < 12) i];
  return [
    if (simple.isNotEmpty) formulaOf(simple),
    for (final i in intervals) if (i >= 12) _compoundLabels[i] ?? '${i % 12}',
  ].join('-');
}

/// Every chord Free Play can name, in priority order. Within one root the
/// first entry whose pitch classes match wins, so shell voicings sit after
/// the full forms they abbreviate. No two entries share a pitch-class set.
const List<ChordQuality> chordQualities = [
  // Triads
  ChordQuality('Major', '', [0, 4, 7]),
  ChordQuality('Minor', 'm', [0, 3, 7]),
  ChordQuality('Diminished', 'dim', [0, 3, 6]),
  ChordQuality('Augmented', 'aug', [0, 4, 8]),
  ChordQuality('Sus2', 'sus2', [0, 2, 7]),
  ChordQuality('Sus4', 'sus4', [0, 5, 7]),
  // Sevenths
  ChordQuality('Major 7th', 'maj7', [0, 4, 7, 11]),
  ChordQuality('Dominant 7th', '7', [0, 4, 7, 10]),
  ChordQuality('Minor 7th', 'm7', [0, 3, 7, 10]),
  ChordQuality('Minor 7th flat 5', 'm7b5', [0, 3, 6, 10]),
  ChordQuality('Diminished 7th', 'dim7', [0, 3, 6, 9]),
  ChordQuality('Minor Major 7th', 'mMaj7', [0, 3, 7, 11]),
  ChordQuality('Augmented 7th', '7#5', [0, 4, 8, 10]),
  ChordQuality('Augmented Major 7th', 'maj7#5', [0, 4, 8, 11]),
  ChordQuality('7sus4', '7sus4', [0, 5, 7, 10]),
  ChordQuality('7sus2', '7sus2', [0, 2, 7, 10]),
  ChordQuality('Dominant 7th flat 5', '7b5', [0, 4, 6, 10]),
  // Sixths
  ChordQuality('Major 6th', '6', [0, 4, 7, 9]),
  ChordQuality('Minor 6th', 'm6', [0, 3, 7, 9]),
  ChordQuality('6/9', '6/9', [0, 4, 7, 9, 14]),
  ChordQuality('Minor 6/9', 'm6/9', [0, 3, 7, 9, 14]),
  // Adds
  ChordQuality('Add9', 'add9', [0, 4, 7, 14]),
  ChordQuality('Minor Add9', 'madd9', [0, 3, 7, 14]),
  ChordQuality('Add11', 'add11', [0, 4, 7, 17]),
  ChordQuality('Minor Add11', 'madd11', [0, 3, 7, 17]),
  // Extended
  ChordQuality('Major 9th', 'maj9', [0, 4, 7, 11, 14]),
  ChordQuality('Dominant 9th', '9', [0, 4, 7, 10, 14]),
  ChordQuality('Minor 9th', 'm9', [0, 3, 7, 10, 14]),
  ChordQuality('Minor Major 9th', 'mMaj9', [0, 3, 7, 11, 14]),
  ChordQuality('Dominant 7th flat 9', '7b9', [0, 4, 7, 10, 13]),
  ChordQuality('Dominant 7th sharp 9', '7#9', [0, 4, 7, 10, 15]),
  ChordQuality('Dominant 11th', '11', [0, 4, 7, 10, 14, 17]),
  ChordQuality('Minor 11th', 'm11', [0, 3, 7, 10, 14, 17]),
  ChordQuality('Dominant 13th', '13', [0, 4, 7, 10, 14, 21]),
  ChordQuality('Major 13th', 'maj13', [0, 4, 7, 11, 14, 21]),
  ChordQuality('Minor 13th', 'm13', [0, 3, 7, 10, 14, 21]),
  // Shell voicings: the 5th left out. Same names as the full forms above.
  ChordQuality('Major 7th', 'maj7', [0, 4, 11]),
  ChordQuality('Dominant 7th', '7', [0, 4, 10]),
  ChordQuality('Minor 7th', 'm7', [0, 3, 10]),
  ChordQuality('Dominant 9th', '9', [0, 4, 10, 14]),
  ChordQuality('Major 9th', 'maj9', [0, 4, 11, 14]),
  ChordQuality('Minor 9th', 'm9', [0, 3, 10, 14]),
];

/// A named chord: which root and quality, and what is in the bass.
class ChordName {
  const ChordName({
    required this.rootPc,
    required this.quality,
    required this.bassPc,
  });

  final int rootPc;
  final ChordQuality quality;
  final int bassPc;

  /// The bass is a chord tone other than the root, so the label carries it.
  bool get isSlash => bassPc != rootPc;

  /// "C Major 7th", or "C Major 7th / E" when inverted.
  String get label => '${pitchClassNames[rootPc]} ${quality.name}'
      '${isSlash ? ' / ${pitchClassNames[bassPc]}' : ''}';

  /// Root-position degrees, e.g. "1-3-5-7", whatever the inversion.
  String get formula => quality.formula;
}

/// When the bass is not the root, which root to prefer, by the interval from
/// that root up to the bass. A chord over its own 5th keeps its identity best
/// (second inversion), then over its 3rd, then its 7th. This is what makes
/// E-G-A-C read "A Minor 7th / E" while G-A-C-E reads "C Major 6th / G".
const List<int> _bassIntervalPriority = [7, 4, 3, 10, 11, 9, 2, 5, 6, 8, 1];

/// Roots to try for [pcs] with [bassPc] sounding lowest: the bass itself
/// first, then the other tones by [_bassIntervalPriority].
List<int> rootCandidates(Set<int> pcs, int bassPc) {
  final others = [for (final pc in pcs) if (pc != bassPc) pc]
    ..sort((a, b) => _bassIntervalPriority
        .indexOf((bassPc - a) % 12)
        .compareTo(_bassIntervalPriority.indexOf((bassPc - b) % 12)));
  return [bassPc, ...others];
}

/// Names the chord [midiNotes] spell, or null when no table entry fits.
///
/// Octave doublings are ignored; the bass is the lowest note. The bass is
/// tried as the root first, so C6 and Am7 (the same four pitch classes)
/// resolve by which is on the bottom.
ChordName? nameChord(Set<int> midiNotes) {
  if (midiNotes.isEmpty) return null;
  final bassPc = pitchClassOf(midiNotes.reduce(min));
  final pcs = {for (final n in midiNotes) pitchClassOf(n)};
  for (final rootPc in rootCandidates(pcs, bassPc)) {
    final relative = {for (final pc in pcs) (pc - rootPc) % 12};
    for (final q in chordQualities) {
      final qpcs = q.pitchClasses;
      if (qpcs.length == relative.length && qpcs.containsAll(relative)) {
        return ChordName(rootPc: rootPc, quality: q, bassPc: bassPc);
      }
    }
  }
  return null;
}

const List<String> _intervalNames = [
  'Unison', 'Minor 2nd', 'Major 2nd', 'Minor 3rd', 'Major 3rd', 'Perfect 4th',
  'Tritone', 'Perfect 5th', 'Minor 6th', 'Major 6th', 'Minor 7th', 'Major 7th',
  'Octave', 'Minor 9th', 'Major 9th', 'Minor 10th', 'Major 10th',
  'Perfect 11th', 'Augmented 11th', 'Perfect 12th', 'Minor 13th', 'Major 13th',
  'Minor 14th', 'Major 14th', 'Two Octaves',
];

/// The distance between two notes.
class IntervalName {
  IntervalName(int a, int b)
      : low = min(a, b),
        high = max(a, b);

  final int low;
  final int high;

  int get semitones => high - low;

  /// "Perfect 5th", "Octave", or past two octaves "Minor 3rd + 2 octaves".
  String get label {
    final d = semitones;
    if (d < _intervalNames.length) return _intervalNames[d];
    final octaves = d ~/ 12;
    final rest = d % 12;
    return rest == 0
        ? '$octaves Octaves'
        : '${_intervalNames[rest]} + $octaves octaves';
  }

  /// Both notes, low to high: "C4 – G4".
  String get notes => '${noteName(low)} – ${noteName(high)}';
}

IntervalName nameInterval(int low, int high) => IntervalName(low, high);

enum ReadoutKind { note, interval, chord, unmatched }

/// What Free Play shows for the notes sounding right now.
class Readout {
  const Readout(this.kind, this.title, [this.detail]);

  final ReadoutKind kind;

  /// The name: "C4", "Perfect 5th", "C Major 7th / E", or the note names when
  /// three or more notes match nothing in the table.
  final String title;

  /// The line under it: an interval's notes, a chord's formula, else null.
  final String? detail;
}

/// Names [midiNotes]: one note by name, two pitch classes as an interval,
/// three or more as a chord. Null when nothing is sounding. Never null for a
/// non-empty set, so the readout is never blank mid-chord.
Readout? describeHeld(Set<int> midiNotes) {
  if (midiNotes.isEmpty) return null;
  final sorted = midiNotes.toList()..sort();
  if (sorted.length == 1) return Readout(ReadoutKind.note, noteName(sorted[0]));
  final pcs = {for (final n in sorted) pitchClassOf(n)};
  if (pcs.length <= 2) {
    // One pitch class doubled reads as the span (Octave); two pitch classes
    // read from the bass to the nearest note of the other class, so C3-E3-C4
    // is still a Major 3rd.
    final low = sorted.first;
    final high = pcs.length == 1
        ? sorted.last
        : sorted.firstWhere((n) => pitchClassOf(n) != pitchClassOf(low));
    final iv = nameInterval(low, high);
    return Readout(ReadoutKind.interval, iv.label, iv.notes);
  }
  final chord = nameChord(midiNotes);
  if (chord != null) {
    return Readout(ReadoutKind.chord, chord.label, chord.formula);
  }
  return Readout(ReadoutKind.unmatched, sorted.map(noteName).join(' '));
}
