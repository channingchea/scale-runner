/// Quiz validators. Pure Dart — fed by note input that, in the running app,
/// comes from the live MIDI stream (or on-screen taps). No MIDI dependency
/// here so the logic is fully unit-testable.
library;

import '../theory/music_theory.dart';

/// Outcome of feeding a note to a validator.
enum ValidationStatus {
  /// Note accepted; the answer is not yet complete.
  inProgress,

  /// The full expected answer has now been played correctly.
  complete,

  /// A wrong note was played; the attempt has failed and should be replayed.
  wrong,
}

/// Validates a scale played one note at a time, in ascending order.
///
/// Comparison is by pitch class, so the user may play in any octave; only the
/// order of pitch classes matters. Feed each Note On to [onNoteOn]. A correct
/// sequence advances; the first wrong pitch class returns [ValidationStatus.wrong]
/// and the caller should reset (via [reset]) and have the user replay.
class ScaleValidator {
  /// Expected pitch-class sequence, in order, including the octave root on top
  /// when present (e.g. C major -> [0,2,4,5,7,9,11,0]).
  final List<int> expected;
  int _index = 0;

  ScaleValidator(this.expected)
      : assert(expected.isNotEmpty, 'expected sequence must not be empty');

  /// Build a validator from a scale formula in a given root.
  factory ScaleValidator.fromFormula(ScaleFormula scale, int rootMidi,
      {bool includeOctave = true}) {
    final pcs = [
      for (final n in scale.notesFrom(rootMidi, includeOctave: includeOctave))
        pitchClassOf(n)
    ];
    return ScaleValidator(pcs);
  }

  /// How many notes have been correctly played so far.
  int get progress => _index;

  /// Whether the full sequence has been completed.
  bool get isComplete => _index >= expected.length;

  /// Feed a MIDI Note On. Returns the resulting status.
  ValidationStatus onNoteOn(int midiNote) {
    if (isComplete) return ValidationStatus.complete;
    if (pitchClassOf(midiNote) == expected[_index]) {
      _index++;
      return isComplete ? ValidationStatus.complete : ValidationStatus.inProgress;
    }
    return ValidationStatus.wrong;
  }

  /// Reset to the start of the sequence (after a wrong attempt or to replay).
  void reset() => _index = 0;
}

/// Validates a chord: the correct set of pitch classes must be held
/// simultaneously, with no extra notes.
///
/// Feed the currently-held notes (from the MIDI stream / tapped keys) to
/// [evaluate] whenever the held set changes. Comparison is by pitch class, so
/// voicing/octave doesn't matter — only that exactly the chord's pitch classes
/// are sounding. (To require a specific inversion later, compare bass note or
/// absolute notes instead.)
class ChordValidator {
  /// The exact set of pitch classes the chord requires.
  final Set<int> expected;

  ChordValidator(this.expected)
      : assert(expected.isNotEmpty, 'expected set must not be empty');

  /// Build a validator from a chord formula in a given root.
  factory ChordValidator.fromFormula(ChordFormula chord, int rootMidi) =>
      ChordValidator(chord.pitchClasses(pitchClassOf(rootMidi)));

  /// Evaluate the currently-held notes.
  ///
  /// Returns [ValidationStatus.complete] when the held pitch classes exactly
  /// match the expected set. Returns [ValidationStatus.wrong] if any held note
  /// is outside the chord (a wrong note is sounding). Otherwise
  /// [ValidationStatus.inProgress] — a correct-so-far subset, still building.
  ValidationStatus evaluate(Set<int> heldNotes) {
    final heldPcs = heldNotes.map(pitchClassOf).toSet();
    if (heldPcs.isEmpty) return ValidationStatus.inProgress;
    if (!heldPcs.every(expected.contains)) return ValidationStatus.wrong;
    return heldPcs.containsAll(expected)
        ? ValidationStatus.complete
        : ValidationStatus.inProgress;
  }
}
