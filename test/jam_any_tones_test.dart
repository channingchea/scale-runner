import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/runner/jam_mode_controller.dart';
import 'package:scale_runner/theory/jam_mode.dart';

JamModeController makeController({
  int keyPc = 0,
  int seed = 1,
  int sessionBars = 1000,
  bool freestyle = false,
}) {
  final c = JamModeController(
      keyPc: keyPc,
      seed: seed,
      sessionBars: sessionBars,
      freestyle: freestyle,
      anyTones: true);
  c.beatPeriodMs = () => 600;
  c.msSinceBeat = () => 0;
  return c;
}

/// Start and tick the count-in so the next onBeat judges the current chord.
void armFirstChord(JamModeController c) {
  c.start();
  for (var i = 0; i < c.beatsPerBar; i++) {
    c.onBeat();
  }
}

/// Judge the armed chord and count in the next one.
void advanceOneChord(JamModeController c) {
  c.onBeat();
  if (c.judging) c.debugResolveGrace();
  for (var i = 0; i < c.beatsPerBar - 1; i++) {
    c.onBeat();
  }
}

void releaseAll(JamModeController c) {
  for (var n = 0; n < 128; n++) {
    c.releaseKey(n);
  }
}

void main() {
  group('JamKey open-chord theory', () {
    final key = JamKey(0); // C major

    test('stackPcs is every in-key pc except the 6th above the root', () {
      // Degree 1 (C): C D E F G B — no A.
      expect(key.stackPcs(1), {0, 2, 4, 5, 7, 11});
      // Degree 2 (D): D E F G A C — no B.
      expect(key.stackPcs(2), {2, 4, 5, 7, 9, 0});
      for (var d = 1; d <= 7; d++) {
        expect(key.stackPcs(d).length, 6);
        expect(key.stackPcs(d).difference(key.scalePcs), isEmpty);
      }
    });

    test('openChord shows roman + bare root, no quality suffix', () {
      final ii = key.openChord(2);
      expect(ii.roman, 'ii');
      expect(ii.name, 'D');
      expect(ii.prompt, 'ii · D');
      expect(ii.pitchClasses, key.stackPcs(2));
    });

    test('openPrompts is one prompt per degree with distinct identities', () {
      final prompts = key.openPrompts();
      expect(prompts.length, 7);
      expect(prompts.map((p) => p.key).toSet().length, 7);
    });

    test('degreeOfRoot maps diatonic roots and rejects chromatics', () {
      expect(key.degreeOfRoot(2), 2); // D → ii
      expect(key.degreeOfRoot(7), 5); // G → V
      expect(key.degreeOfRoot(1), isNull); // C# not a diatonic root
    });
  });

  group('prompted, any chord tones', () {
    /// Two stack tones (≠ root) of the armed chord, to build voicings with.
    List<int> twoStackTones(JamModeController c, int rootPc) => c
        .currentChord!.pitchClasses
        .where((pc) => pc != rootPc)
        .take(2)
        .toList();

    int rootPcOf(JamModeController c) =>
        JamKey(0).rootPcOf(c.currentChord!.degree);

    test('a 3-note shell voicing with the root in the bass scores', () {
      final c = makeController();
      armFirstChord(c);
      final root = rootPcOf(c);
      final tones = twoStackTones(c, root);
      c.pressKey(48 + root); // bass = root
      c.pressKey(60 + tones[0]);
      c.pressKey(60 + tones[1]);
      c.onBeat();
      expect(c.barsJudged, 1);
      expect(c.barsOnBeat, 1);
    });

    test('doubled notes count toward the 3-note minimum', () {
      final c = makeController();
      armFirstChord(c);
      final root = rootPcOf(c);
      final tones = twoStackTones(c, root);
      c.pressKey(48 + root);
      c.pressKey(60 + root); // doubled root
      c.pressKey(60 + tones[0]);
      c.onBeat();
      if (c.judging) c.debugResolveGrace();
      expect(c.barsOnBeat, 1);
    });

    test('only 2 notes is not a chord — missed', () {
      final c = makeController();
      armFirstChord(c);
      final root = rootPcOf(c);
      final tones = twoStackTones(c, root);
      c.pressKey(48 + root);
      c.pressKey(60 + tones[0]);
      c.onBeat();
      if (c.judging) c.debugResolveGrace();
      expect(c.barsMissed, 1);
    });

    test('an inversion (non-root bass) is missed', () {
      final c = makeController();
      armFirstChord(c);
      final root = rootPcOf(c);
      final tones = twoStackTones(c, root);
      c.pressKey(48 + tones[0]); // bass is NOT the root
      c.pressKey(60 + root);
      c.pressKey(60 + tones[1]);
      c.onBeat();
      if (c.judging) c.debugResolveGrace();
      expect(c.barsMissed, 1);
    });

    test('the 6th above the root is out of the stack: wrong flash + miss', () {
      final c = makeController();
      armFirstChord(c);
      final root = rootPcOf(c);
      final sixth =
          JamKey(0).scalePcs.difference(c.currentChord!.pitchClasses).single;
      final tones = twoStackTones(c, root);
      c.pressKey(48 + root);
      c.pressKey(60 + tones[0]);
      c.pressKey(60 + sixth);
      expect(c.notesWrong, 1);
      c.onBeat();
      if (c.judging) c.debugResolveGrace();
      expect(c.barsMissed, 1);
    });

    test('bars tally by degree only — quality buckets stay empty', () {
      final c = makeController();
      armFirstChord(c);
      final root = rootPcOf(c);
      final roman = c.currentChord!.roman;
      final tones = twoStackTones(c, root);
      c.pressKey(48 + root);
      c.pressKey(60 + tones[0]);
      c.pressKey(60 + tones[1]);
      c.onBeat();
      expect(c.qualityScores, isEmpty);
      expect(c.degreeScores[roman]!.correct, 1);
    });
  });

  group('freestyle, any chord tones', () {
    test('bass names the degree; a valid stack scores that degree', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      // D in the bass + F, A, C above: a ii stack (Dm7 shell + extensions).
      c.pressKey(50); // D3
      c.pressKey(65); // F4
      c.pressKey(69); // A4
      c.pressKey(72); // C5
      expect(c.liveChordMatch!.chord.roman, 'ii');
      c.onBeat();
      expect(c.barsOnBeat, 1);
      expect(c.degreeScores['ii']!.correct, 1);
    });

    test('repeating the last degree is a miss; a new degree scores', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      c.pressKey(50); // D
      c.pressKey(65); // F
      c.pressKey(69); // A
      advanceOneChord(c);
      expect(c.barsOnBeat, 1);
      releaseAll(c);
      // Same degree again (different voicing) → forbidden repeat → miss.
      c.pressKey(50); // D
      c.pressKey(64); // E (the 2nd/9th — in the ii stack)
      c.pressKey(69); // A
      advanceOneChord(c);
      expect(c.barsMissed, 1);
      releaseAll(c);
      // A V stack (G in the bass) now scores.
      c.pressKey(43); // G2
      c.pressKey(59); // B3
      c.pressKey(65); // F4
      advanceOneChord(c);
      expect(c.barsOnBeat, 2);
    });

    test('a chromatic bass (no diatonic root) never matches', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      c.pressKey(49); // C#3 in the bass
      c.pressKey(65);
      c.pressKey(69);
      expect(c.liveChordMatch, isNull);
      c.onBeat();
      if (c.judging) c.debugResolveGrace();
      expect(c.barsMissed, 1);
    });
  });
}
