import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/theory/music_theory.dart';
import 'package:scale_runner/theory/inversion_running.dart';

/// Look the four v1 chords up by name from the shared library.
ChordFormula chord(String name) =>
    commonChords.firstWhere((c) => c.name == name);

void main() {
  group('inversionLabel', () {
    test('0 = Root, 1..3 ordinal inversions', () {
      expect(inversionLabel(0), 'Root');
      expect(inversionLabel(1), '1st inversion');
      expect(inversionLabel(2), '2nd inversion');
      expect(inversionLabel(3), '3rd inversion');
    });
  });

  group('InversionCycle — triad step count & order (C Major)', () {
    final cycle = InversionCycle(chord('Major'), 0); // C
    test('triads run 7 steps', () => expect(cycle.length, 7));
    test('inversion order ascends 0..3 then descends 2..0', () {
      expect([for (final s in cycle.steps) s.inversion],
          [0, 1, 2, 3, 2, 1, 0]);
    });
    test('apex is the only octave root', () {
      final octaveRoots = cycle.steps.where((s) => s.isOctaveRoot).toList();
      expect(octaveRoots.length, 1);
      expect(cycle.steps[3].isOctaveRoot, isTrue);
      expect(cycle.steps[3].label, 'Root (8va)');
    });
    test('labels read up then down, top root not repeated', () {
      expect([for (final s in cycle.steps) s.label], [
        'Root', '1st inversion', '2nd inversion', 'Root (8va)',
        '2nd inversion', '1st inversion', 'Root',
      ]);
    });
    test('formulas rotate bass-up per inversion, apex tagged (8va)', () {
      expect([for (final s in cycle.steps) s.formula], [
        '1-3-5', '3-5-1', '5-1-3', '1-3-5 (8va)',
        '5-1-3', '3-5-1', '1-3-5',
      ]);
    });
  });

  group('InversionCycle — formula accidentals rotate whole tokens', () {
    test('Minor 7th (Eb): b3/b7 stay intact when rotated', () {
      final steps = InversionCycle(chord('Minor 7th'), 3).steps; // Eb
      expect([for (final s in steps) s.formula], [
        '1-b3-5-b7', 'b3-5-b7-1', '5-b7-1-b3', 'b7-1-b3-5',
        '1-b3-5-b7 (8va)', 'b7-1-b3-5', '5-b7-1-b3', 'b3-5-b7-1',
        '1-b3-5-b7',
      ]);
    });
  });

  group('InversionCycle — triad voicings (C Major @ C4)', () {
    final cycle = InversionCycle(chord('Major'), 0);
    test('lowMidi anchors root to C4 (60)', () => expect(cycle.lowMidi, 60));
    test('root position = C E G', () {
      expect(cycle.steps[0].notes, [60, 64, 67]);
    });
    test('1st inversion = E G C', () {
      expect(cycle.steps[1].notes, [64, 67, 72]);
    });
    test('2nd inversion = G C E', () {
      expect(cycle.steps[2].notes, [67, 72, 76]);
    });
    test('octave-up root = C E G one octave higher', () {
      expect(cycle.steps[3].notes, [72, 76, 79]);
    });
    test('descent mirrors ascent exactly', () {
      expect(cycle.steps[4].notes, cycle.steps[2].notes); // 2nd inv
      expect(cycle.steps[5].notes, cycle.steps[1].notes); // 1st inv
      expect(cycle.steps[6].notes, cycle.steps[0].notes); // root
    });
  });

  group('InversionCycle — 7th step count & order (C Major 7th)', () {
    final cycle = InversionCycle(chord('Major 7th'), 0);
    test('7ths run 9 steps', () => expect(cycle.length, 9));
    test('inversion order ascends 0..4 then descends 3..0', () {
      expect([for (final s in cycle.steps) s.inversion],
          [0, 1, 2, 3, 4, 3, 2, 1, 0]);
    });
    test('apex (step 4) is the only octave root', () {
      expect(cycle.steps.where((s) => s.isOctaveRoot).length, 1);
      expect(cycle.steps[4].isOctaveRoot, isTrue);
    });
    test('root position = C E G B; apex one octave up', () {
      expect(cycle.steps[0].notes, [60, 64, 67, 71]);
      expect(cycle.steps[4].notes, [72, 76, 79, 83]);
    });
  });

  group('InversionCycle — octave tolerance & pitch classes', () {
    final cycle = InversionCycle(chord('Minor 7th'), 2); // D
    test('every step shares the chord pitch-class set', () {
      final expected = chord('Minor 7th').pitchClasses(2); // {2,5,9,0}
      expect(cycle.pitchClasses, expected);
      for (final s in cycle.steps) {
        expect(s.pitchClasses, expected);
      }
    });
    test('label is "{root} {chord}"', () {
      expect(cycle.label, 'D Minor 7th');
    });
  });

  group('InversionCycle — transposing keyboard per root', () {
    test('lowMidi follows the root pitch class within octave 4', () {
      expect(InversionCycle(chord('Minor'), 0).lowMidi, 60); // C4
      expect(InversionCycle(chord('Minor'), 9).lowMidi, 69); // A4
      expect(InversionCycle(chord('Minor'), 11).lowMidi, 71); // B4
    });
    test('top note stays within ~2 octaves of lowMidi for all 12 roots', () {
      for (var pc = 0; pc < 12; pc++) {
        final cycle = InversionCycle(chord('Major 7th'), pc);
        final span = cycle.steps[4].notes.last - cycle.lowMidi;
        expect(span, lessThanOrEqualTo(24)); // root..root+24 fits 2 octaves
      }
    });
    test('first step always starts on lowMidi (the visual root key)', () {
      for (var pc = 0; pc < 12; pc++) {
        final cycle = InversionCycle(chord('Major'), pc);
        expect(cycle.steps.first.notes.first, cycle.lowMidi);
      }
    });
  });

  group('InversionCycle — all four v1 chords build cleanly', () {
    for (final name in ['Major', 'Minor', 'Major 7th', 'Minor 7th']) {
      test('$name has the expected step count', () {
        final cycle = InversionCycle(chord(name), 7); // G
        final n = chord(name).inversionCount;
        expect(cycle.length, 2 * n + 1);
        expect(cycle.steps.first.inversion, 0);
        expect(cycle.steps.last.inversion, 0);
      });
    }
  });
}
