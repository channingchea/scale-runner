import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/theory/jam_mode.dart';

void main() {
  group('JamKey — Roman numerals (C major)', () {
    final k = JamKey(0);
    test('diatonic casing with ° on vii', () {
      expect([for (var d = 1; d <= 7; d++) k.roman(d)],
          ['I', 'ii', 'iii', 'IV', 'V', 'vi', 'vii°']);
    });
  });

  group('JamKey — triads (C major)', () {
    final k = JamKey(0);
    test('I = C major', () {
      final c = k.chord(1, JamFamily.triad);
      expect(c.pitchClasses, {0, 4, 7});
      expect(c.name, 'C');
      expect(c.prompt, 'I · C');
      expect(c.formula, '1-3-5');
    });
    test('ii = Dm', () {
      final c = k.chord(2, JamFamily.triad);
      expect(c.pitchClasses, {2, 5, 9});
      expect(c.name, 'Dm');
      expect(c.prompt, 'ii · Dm');
    });
    test('vii° = Bdim', () {
      final c = k.chord(7, JamFamily.triad);
      expect(c.pitchClasses, {11, 2, 5});
      expect(c.name, 'Bdim');
      expect(c.prompt, 'vii° · Bdim');
      expect(c.formula, '1-b3-b5');
    });
  });

  group('JamKey — 7th chords (C major)', () {
    final k = JamKey(0);
    test('names per degree', () {
      expect([for (var d = 1; d <= 7; d++) k.chord(d, JamFamily.seventh).name],
          ['Cmaj7', 'Dm7', 'Em7', 'Fmaj7', 'G7', 'Am7', 'Bm7b5']);
    });
    test('V7 = G dominant 7th pitch classes', () {
      expect(k.chord(5, JamFamily.seventh).pitchClasses, {7, 11, 2, 5});
    });
    test('Imaj7 formula', () {
      expect(k.chord(1, JamFamily.seventh).formula, '1-3-5-7');
    });
    test('V7 formula uses b7', () {
      expect(k.chord(5, JamFamily.seventh).formula, '1-3-5-b7');
    });
  });

  group('JamKey — 9th chords (C major)', () {
    final k = JamKey(0);
    test('Imaj9 = C E G B D', () {
      final c = k.chord(1, JamFamily.ninth);
      expect(c.pitchClasses, {0, 4, 7, 11, 2});
      expect(c.name, 'Cmaj9');
      expect(c.formula, '1-3-5-7-9');
    });
    test('ii9 = Dm9 (D F A C E)', () {
      final c = k.chord(2, JamFamily.ninth);
      expect(c.pitchClasses, {2, 5, 9, 0, 4});
      expect(c.name, 'Dm9');
    });
    test('vii = Bm9b5 name', () {
      expect(k.chord(7, JamFamily.ninth).name, 'Bm9b5');
    });
  });

  group('JamKey — sus chords (C major)', () {
    final k = JamKey(0);
    test('Isus2 = C D G, replaces the 3rd', () {
      final c = k.chord(1, JamFamily.sus, susType: 2);
      expect(c.pitchClasses, {0, 2, 7});
      expect(c.name, 'Csus2');
      expect(c.formula, '1-2-5');
      expect(c.pitchClasses.contains(4), isFalse); // no 3rd
    });
    test('Isus4 = C F G', () {
      final c = k.chord(1, JamFamily.sus, susType: 4);
      expect(c.pitchClasses, {0, 5, 7});
      expect(c.name, 'Csus4');
      expect(c.formula, '1-4-5');
    });
    test('ii sus uses scale tones (Dsus2 = D E A, Dsus4 = D G A)', () {
      expect(k.chord(2, JamFamily.sus, susType: 2).pitchClasses, {2, 4, 9});
      expect(k.chord(2, JamFamily.sus, susType: 4).pitchClasses, {2, 7, 9});
    });
  });

  group('JamKey — non-C key (G major)', () {
    final k = JamKey(7);
    test('label', () => expect(k.label, 'G Major'));
    test('ii = Am7', () {
      final c = k.chord(2, JamFamily.seventh);
      expect(c.name, 'Am7');
      expect(c.pitchClasses, {9, 0, 4, 7});
    });
    test('V9 = D9 (D F# A C E)', () {
      final c = k.chord(5, JamFamily.ninth);
      expect(c.pitchClasses, {2, 6, 9, 0, 4});
      expect(c.name, 'D9');
    });
  });

  group('JamKey — prompt pool', () {
    final k = JamKey(0);
    test('triads only = 7 prompts', () {
      expect(k.prompts({JamFamily.triad}).length, 7);
    });
    test('sus only = 14 prompts (sus2 + sus4 per degree)', () {
      expect(k.prompts({JamFamily.sus}).length, 14);
    });
    test('all four families = 7+7+7+14 = 35 prompts', () {
      expect(k.prompts(JamFamily.values.toSet()).length, 35);
    });
  });

  group('JamPromptPicker — no immediate repeat', () {
    test('never serves the same chord twice in a row', () {
      final pool = JamKey(0).prompts(JamFamily.values.toSet());
      final picker = JamPromptPicker(pool, rng: Random(42));
      var prev = picker.next();
      for (var i = 0; i < 500; i++) {
        final cur = picker.next();
        expect(cur.key == prev.key, isFalse);
        prev = cur;
      }
    });
    test('every pick comes from the enabled pool', () {
      final pool = JamKey(0).prompts({JamFamily.triad});
      final keys = {for (final c in pool) c.key};
      final picker = JamPromptPicker(pool, rng: Random(7));
      for (var i = 0; i < 100; i++) {
        expect(keys.contains(picker.next().key), isTrue);
      }
    });
    test('single-entry pool repeats itself without looping forever', () {
      final pool = [JamKey(0).chord(1, JamFamily.triad)];
      final picker = JamPromptPicker(pool, rng: Random(1));
      expect(picker.next().name, 'C');
      expect(picker.next().name, 'C');
    });
  });

  group('JamChordMatcher — Freestyle chord recognition (C major)', () {
    test('an unambiguous triad matches its one diatonic chord', () {
      final m = JamChordMatcher(JamKey(0), JamFamily.values.toSet());
      final match = m.match({0, 4, 7});
      expect(match, isNotNull);
      expect(match!.chord.name, 'C');
      expect(match.chord.degree, 1);
      expect(match.enabled, isTrue);
    });

    test('a chord from a disabled family is still recognized, not enabled',
        () {
      final m = JamChordMatcher(JamKey(0), {JamFamily.seventh});
      final match = m.match({0, 4, 7}); // C major triad, family = triad
      expect(match, isNotNull);
      expect(match!.chord.family, JamFamily.triad);
      expect(match.enabled, isFalse);
    });

    test('extra or missing notes never match (no partial/superset match)',
        () {
      final m = JamChordMatcher(JamKey(0), JamFamily.values.toSet());
      expect(m.match({0, 4}), isNull); // partial triad
      expect(m.match({0, 4, 7, 1}), isNull); // triad + a stray note
    });

    test('a non-diatonic cluster matches nothing', () {
      final m = JamChordMatcher(JamKey(0), JamFamily.values.toSet());
      expect(m.match({0, 1, 6}), isNull);
    });

    test('empty pitch-class set matches nothing', () {
      final m = JamChordMatcher(JamKey(0), JamFamily.values.toSet());
      expect(m.match({}), isNull);
    });

    test('ambiguous shape {0,5,7}: Isus4 and IVsus2 share the same pitch '
        'classes — bass note breaks the tie', () {
      final m = JamChordMatcher(JamKey(0), JamFamily.values.toSet());
      final asI = m.match({0, 5, 7}, bassPc: 0);
      expect(asI!.chord.degree, 1);
      expect(asI.chord.name, 'Csus4');
      final asIV = m.match({0, 5, 7}, bassPc: 5);
      expect(asIV!.chord.degree, 4);
      expect(asIV.chord.name, 'Fsus2');
    });

    test('ambiguous shape with no usable bass falls back to avoiding the '
        'forbidden (just-played) degree', () {
      final m = JamChordMatcher(JamKey(0), JamFamily.values.toSet());
      // No bassPc supplied; without it root-narrowing is skipped entirely, so
      // the forbidden-degree fallback alone must pick the non-repeat option.
      final match = m.match({0, 5, 7}, forbiddenDegree: 1);
      expect(match!.chord.degree, 4); // not the forbidden I (degree 1)
    });
  });
}
