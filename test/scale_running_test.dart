import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/theory/scale_running.dart';

void main() {
  group('DiatonicHarmony — degree pitch classes (C major)', () {
    const h = DiatonicHarmony(0); // C
    test('degrees 1–7 map to C D E F G A B', () {
      expect([for (var d = 1; d <= 7; d++) h.degreePc(d)],
          [0, 2, 4, 5, 7, 9, 11]);
    });
  });

  group('DiatonicHarmony — diatonic triads (C major)', () {
    const h = DiatonicHarmony(0);
    test('I = C major triad', () => expect(h.chordPcs(1), {0, 4, 7}));
    test('ii = D minor triad', () => expect(h.chordPcs(2), {2, 5, 9}));
    test('V = G major triad', () => expect(h.chordPcs(5), {7, 11, 2}));
    test('vii = B diminished triad', () => expect(h.chordPcs(7), {11, 2, 5}));

    test('qualities per degree', () {
      expect([for (var d = 1; d <= 7; d++) h.chordQuality(d).name], [
        'Major', 'Minor', 'Minor', 'Major', 'Major', 'Minor', 'Diminished',
      ]);
    });
  });

  group('DiatonicHarmony — diatonic 7ths (C major)', () {
    const h = DiatonicHarmony(0, sevenths: true);
    test('qualities per degree', () {
      expect([for (var d = 1; d <= 7; d++) h.chordQuality(d).name], [
        'Major 7th', 'Minor 7th', 'Minor 7th', 'Major 7th',
        'Dominant 7th', 'Minor 7th', 'Minor 7th flat 5',
      ]);
    });
    test('V7 = G dominant 7th pitch classes', () {
      expect(h.chordPcs(5), {7, 11, 2, 5});
    });
  });

  group('DiatonicHarmony — mode runs (C major)', () {
    const h = DiatonicHarmony(0);
    test('degree 1 run = C Ionian + octave', () {
      expect(h.runPcs(1), [0, 2, 4, 5, 7, 9, 11, 0]);
    });
    test('degree 2 run = D Dorian + octave', () {
      expect(h.runPcs(2), [2, 4, 5, 7, 9, 11, 0, 2]);
    });
    test('degree 6 run = A Aeolian + octave', () {
      expect(h.runPcs(6), [9, 11, 0, 2, 4, 5, 7, 9]);
    });
    test('every run has exactly 8 notes ending on its own root', () {
      for (var d = 1; d <= 7; d++) {
        final run = h.runPcs(d);
        expect(run.length, 8);
        expect(run.last, run.first);
      }
    });
    test('mode labels', () {
      expect(h.stepFor(1).modeLabel, 'C Ionian');
      expect(h.stepFor(2).modeLabel, 'D Dorian');
      expect(h.stepFor(6).modeLabel, 'A Aeolian');
    });
  });

  group('DiatonicHarmony — non-C key (G major)', () {
    const h = DiatonicHarmony(7);
    test('ii of G = A minor', () {
      expect(h.chordPcs(2), {9, 0, 4});
      expect(h.stepFor(2).chordLabel, 'A Minor');
    });
    test('degree 2 run = A Dorian (G major from A)', () {
      expect(h.runPcs(2), [9, 11, 0, 2, 4, 6, 7, 9]);
    });
  });

  group('KeyCycler', () {
    test('chromatic +1 wraps at the octave', () {
      const c = KeyCycler(KeyIncrement.chromatic);
      expect(c.next(0), 1);
      expect(c.next(11), 0);
    });
    test('fifths +7 visits all 12 keys', () {
      const c = KeyCycler(KeyIncrement.fifths);
      final seen = <int>{};
      var pc = 0;
      for (var i = 0; i < 12; i++) {
        seen.add(pc);
        pc = c.next(pc);
      }
      expect(seen.length, 12);
      expect(pc, 0); // back home after 12 steps
    });
  });

  group('Progression expansion', () {
    test('1-6-2-5 in C expands to C / Am / Dm / G', () {
      const h = DiatonicHarmony(0);
      final steps = h.expand(commonProgressions[0]);
      expect([for (final s in steps) s.chordLabel],
          ['C Major', 'A Minor', 'D Minor', 'G Major']);
      expect([for (final s in steps) s.modeLabel],
          ['C Ionian', 'A Aeolian', 'D Dorian', 'G Mixolydian']);
    });
    test('12-bar blues has 12 steps', () {
      const h = DiatonicHarmony(0);
      expect(h.expand(commonProgressions[4]).length, 12);
    });
  });

  group('No-chords mode', () {
    test('scale-only step runs the Ionian with no chord', () {
      const h = DiatonicHarmony(2); // D
      final step = h.scaleOnlyStep();
      expect(step.chordPcs, isEmpty);
      expect(step.runPcs, [2, 4, 6, 7, 9, 11, 1, 2]);
      expect(step.modeLabel, 'D Major (Ionian)');
    });
  });
}
