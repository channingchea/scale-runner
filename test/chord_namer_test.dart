import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/theory/chord_namer.dart';
import 'package:scale_runner/theory/music_theory.dart';

/// [quality] in root position on [rootPc], bass at C3 + rootPc.
Set<int> voice(ChordQuality quality, int rootPc) =>
    {for (final i in quality.intervals) 48 + rootPc + i};

/// The notes of `spelling` ("C E G") in one octave from C4, the first note
/// lowest, wrapping upward so the bass is exactly the first name given.
Set<int> notes(String spelling) {
  final names = spelling.split(' ');
  var last = -1;
  final out = <int>{};
  for (final n in names) {
    var midi = 60 + pitchClassNames.indexOf(n);
    while (midi <= last) {
      midi += 12;
    }
    out.add(midi);
    last = midi;
  }
  return out;
}

ChordQuality quality(String name, {bool shell = false}) => chordQualities
    .where((q) => q.name == name)
    .elementAt(shell ? 1 : 0);

void main() {
  group('quality table', () {
    test('intervals ascend from the root and no two entries share pitch '
        'classes', () {
      final seen = <String>{};
      for (final q in chordQualities) {
        expect(q.intervals.first, 0, reason: q.name);
        for (var i = 1; i < q.intervals.length; i++) {
          expect(q.intervals[i], greaterThan(q.intervals[i - 1]),
              reason: q.name);
        }
        final key = (q.pitchClasses.toList()..sort()).join(',');
        expect(seen.add(key), isTrue,
            reason: '${q.name} duplicates another entry');
      }
    });

    test('formulas spell extensions compound', () {
      expect(quality('Major').formula, '1-3-5');
      expect(quality('Minor 7th flat 5').formula, '1-b3-b5-b7');
      expect(quality('Diminished 7th').formula, '1-b3-b5-bb7');
      expect(quality('Augmented 7th').formula, '1-3-#5-b7');
      expect(quality('Add9').formula, '1-3-5-9');
      expect(quality('6/9').formula, '1-3-5-6-9');
      expect(quality('Dominant 9th').formula, '1-3-5-b7-9');
      expect(quality('Dominant 7th flat 9').formula, '1-3-5-b7-b9');
      expect(quality('Dominant 7th sharp 9').formula, '1-3-5-b7-#9');
      expect(quality('Minor 11th').formula, '1-b3-5-b7-9-11');
      expect(quality('Dominant 13th').formula, '1-3-5-b7-9-13');
      expect(quality('Major 7th', shell: true).formula, '1-3-7');
      expect(quality('Dominant 9th', shell: true).formula, '1-3-b7-9');
    });
  });

  group('nameChord — root position', () {
    test('every quality on every root names itself', () {
      for (final q in chordQualities) {
        for (var root = 0; root < 12; root++) {
          final name = nameChord(voice(q, root));
          expect(name, isNotNull, reason: '${pitchClassNames[root]} ${q.name}');
          expect(name!.quality, same(q),
              reason: '${pitchClassNames[root]} ${q.name}');
          expect(name.rootPc, root);
          expect(name.isSlash, isFalse);
          expect(name.label, '${pitchClassNames[root]} ${q.name}');
          expect(name.formula, q.formula);
        }
      }
    });

    test('octave doublings do not change the name', () {
      final name = nameChord({48, 52, 55, 60, 64, 67, 72});
      expect(name!.label, 'C Major');
    });

    test('shell voicings name as the full chord with a shorter formula', () {
      expect(nameChord(notes('C E B'))!.label, 'C Major 7th');
      expect(nameChord(notes('C E B'))!.formula, '1-3-7');
      expect(nameChord(notes('C E A#'))!.label, 'C Dominant 7th');
      expect(nameChord(notes('C D# A#'))!.label, 'C Minor 7th');
      expect(nameChord(notes('C E A# D'))!.label, 'C Dominant 9th');
      expect(nameChord(notes('C E B D'))!.label, 'C Major 9th');
      expect(nameChord(notes('C D# A# D'))!.label, 'C Minor 9th');
    });

    test('nothing in the table gives null', () {
      expect(nameChord(notes('C C# D')), isNull);
      expect(nameChord(notes('C F# B')), isNull);
      expect(nameChord({}), isNull);
      expect(nameChord({60}), isNull);
      expect(nameChord({60, 64}), isNull);
    });
  });

  group('nameChord — inversions', () {
    final triadsAndSevenths = chordQualities
        .where((q) => q.intervals.length <= 4 && q.intervals.last < 12)
        .toList();

    test('every inversion gets a name that spells exactly the notes played', () {
      // Enharmonic twins (Csus2 = Gsus4, Cm7 = Eb6, Cm6 = Am7b5) may come
      // back under the other name, so the invariant checked here is
      // soundness: the name is never null, the bass is right, and the named
      // chord's pitch classes are the ones sounding.
      for (final q in triadsAndSevenths) {
        for (var root = 0; root < 12; root++) {
          final chord = ChordFormula(q.name, q.intervals);
          for (var n = 1; n < q.intervals.length; n++) {
            final set = chord.inversion(48 + root, n).toSet();
            final played = {for (final m in set) pitchClassOf(m)};
            final bassPc = pitchClassOf(set.reduce((a, b) => a < b ? a : b));
            final name = nameChord(set);
            final why = '${pitchClassNames[root]} ${q.name} inversion $n';
            expect(name, isNotNull, reason: why);
            expect(name!.bassPc, bassPc, reason: why);
            expect(name.isSlash, name.rootPc != bassPc, reason: why);
            final spelled = {
              for (final pc in name.quality.pitchClasses) (pc + name.rootPc) % 12
            };
            expect(spelled, played, reason: why);
          }
        }
      }
    });

    test('chords with no enharmonic twin always read as slashes', () {
      for (final qName in ['Major', 'Minor', 'Diminished', 'Major 7th',
          'Dominant 7th', 'Minor Major 7th']) {
        final q = quality(qName);
        final chord = ChordFormula(q.name, q.intervals);
        for (var root = 0; root < 12; root++) {
          for (var n = 1; n < q.intervals.length; n++) {
            final name = nameChord(chord.inversion(48 + root, n).toSet())!;
            expect(name.isSlash, isTrue,
                reason: '${pitchClassNames[root]} $qName inversion $n');
            expect(name.rootPc, root);
          }
        }
      }
    });

    test('C Major inversions', () {
      expect(nameChord(notes('E G C'))!.label, 'C Major / E');
      expect(nameChord(notes('G C E'))!.label, 'C Major / G');
      expect(nameChord(notes('E G C'))!.formula, '1-3-5');
    });

    test('C6 and Am7 resolve by the bass', () {
      expect(nameChord(notes('C E G A'))!.label, 'C Major 6th');
      expect(nameChord(notes('A C E G'))!.label, 'A Minor 7th');
      expect(nameChord(notes('E G A C'))!.label, 'A Minor 7th / E');
      expect(nameChord(notes('G A C E'))!.label, 'C Major 6th / G');
    });

    test('other enharmonic pairs resolve by the bass', () {
      expect(nameChord(notes('D# G A# C'))!.label, 'D# Major 6th'); // Cm7/Eb
      expect(nameChord(notes('A C D# G'))!.label, 'A Minor 7th flat 5'); // Cm6/A
      expect(nameChord(notes('D# F# A# C'))!.label, 'D# Minor 6th'); // Cm7b5/Eb
      expect(nameChord(notes('G C D'))!.label, 'G Sus4'); // Csus2/G
      expect(nameChord(notes('F G C'))!.label, 'F Sus2'); // Csus4/F
      expect(nameChord(notes('F# A# C E'))!.label,
          'F# Dominant 7th flat 5'); // C7b5/Gb
    });

    test('diminished 7th and augmented always name from the bass', () {
      for (final qName in ['Diminished 7th', 'Augmented']) {
        final q = quality(qName);
        final chord = ChordFormula(q.name, q.intervals);
        for (var root = 0; root < 12; root++) {
          for (var n = 0; n < q.intervals.length; n++) {
            final set = chord.inversion(48 + root, n).toSet();
            final bassPc = pitchClassOf(set.reduce((a, b) => a < b ? a : b));
            final name = nameChord(set)!;
            expect(name.isSlash, isFalse);
            expect(name.rootPc, bassPc);
            expect(name.quality.name, qName);
          }
        }
      }
    });

    test('extended chords over a chord tone read as slashes of the root', () {
      expect(nameChord(notes('E G B D C'))!.label, 'C Major 9th / E');
      expect(nameChord(notes('B D F A G'))!.label, 'G Dominant 9th / B');
    });
  });

  group('nameInterval', () {
    test('all 25 simple names', () {
      const expected = [
        'Unison', 'Minor 2nd', 'Major 2nd', 'Minor 3rd', 'Major 3rd',
        'Perfect 4th', 'Tritone', 'Perfect 5th', 'Minor 6th', 'Major 6th',
        'Minor 7th', 'Major 7th', 'Octave', 'Minor 9th', 'Major 9th',
        'Minor 10th', 'Major 10th', 'Perfect 11th', 'Augmented 11th',
        'Perfect 12th', 'Minor 13th', 'Major 13th', 'Minor 14th',
        'Major 14th', 'Two Octaves',
      ];
      for (var d = 0; d <= 24; d++) {
        expect(nameInterval(60, 60 + d).label, expected[d], reason: '$d');
      }
    });

    test('past two octaves reduces and counts the octaves', () {
      expect(nameInterval(48, 75).label, 'Minor 3rd + 2 octaves');
      expect(nameInterval(48, 84).label, '3 Octaves');
      expect(nameInterval(48, 89).label, 'Perfect 4th + 3 octaves');
    });

    test('order of arguments does not matter and notes read low to high', () {
      final iv = nameInterval(67, 60);
      expect(iv.label, 'Perfect 5th');
      expect(iv.semitones, 7);
      expect(iv.notes, 'C4 – G4');
    });
  });

  group('describeHeld', () {
    test('nothing held is null', () {
      expect(describeHeld({}), isNull);
    });

    test('one note is its name', () {
      final r = describeHeld({60})!;
      expect(r.kind, ReadoutKind.note);
      expect(r.title, 'C4');
      expect(r.detail, isNull);
    });

    test('two notes are an interval with both names', () {
      final r = describeHeld({60, 64})!;
      expect(r.kind, ReadoutKind.interval);
      expect(r.title, 'Major 3rd');
      expect(r.detail, 'C4 – E4');
    });

    test('one pitch class doubled is an octave', () {
      expect(describeHeld({48, 60})!.title, 'Octave');
      expect(describeHeld({48, 60, 72})!.title, 'Two Octaves');
    });

    test('two pitch classes with doublings read from the bass', () {
      final r = describeHeld({48, 52, 60})!;
      expect(r.title, 'Major 3rd');
      expect(r.detail, 'C3 – E3');
    });

    test('three or more notes are a chord with its formula', () {
      final r = describeHeld({48, 52, 55, 59})!;
      expect(r.kind, ReadoutKind.chord);
      expect(r.title, 'C Major 7th');
      expect(r.detail, '1-3-5-7');
    });

    test('an unmatched cluster shows the note names, never blank', () {
      final r = describeHeld({60, 61, 62})!;
      expect(r.kind, ReadoutKind.unmatched);
      expect(r.title, 'C4 C#4 D4');
      expect(r.detail, isNull);
    });
  });
}
