import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/runner/scale_run_controller.dart';
import 'package:scale_runner/theory/scale_running.dart';

/// Builds a controller with a fake clock at 600ms/beat. [sinceBeat] controls
/// where presses land relative to the last tick.
ScaleRunController makeController({
  bool chords = true,
  ChordProgression? progression,
  KeyIncrement increment = KeyIncrement.fifths,
  int Function()? sinceBeat,
}) {
  final c = ScaleRunController(
    chordsEnabled: chords,
    progression: progression,
    increment: increment,
    startKeyPc: 0, // C
  );
  c.beatPeriodMs = () => 600;
  c.msSinceBeat = sinceBeat ?? () => 0;
  return c;
}

/// Tick through the 4-beat count-in plus the downbeat tick.
void countIn(ScaleRunController c) {
  c.start();
  for (var i = 0; i < 5; i++) {
    c.onBeat();
  }
}

void main() {
  group('count-in and arming', () {
    test('start arms a 4-beat count-in, 5th tick is the downbeat', () {
      final c = makeController();
      c.start();
      expect(c.phase, RunPhase.countingIn);
      for (var i = 1; i <= 4; i++) {
        c.onBeat();
        expect(c.countInBeat, i);
        expect(c.phase, RunPhase.countingIn);
      }
      c.onBeat();
      expect(c.phase, RunPhase.running);
      expect(c.beatIndex, 0);
    });

    test('presses are not judged while idle or counting in', () {
      final c = makeController();
      c.pressKey(60);
      c.start();
      c.onBeat();
      c.pressKey(60);
      expect(c.notesJudged, 0);
      expect(c.notesWrong, 0);
    });
  });

  group('beat advancement and run completion', () {
    test('correct notes per beat advance through the bar', () {
      final c = makeController(chords: false);
      countIn(c); // running, beat 0
      // C major run: C D E F G A B C from MIDI 48.
      const notes = [48, 50, 52, 53, 55, 57, 59, 60];
      for (var b = 0; b < 8; b++) {
        expect(c.beatIndex, b);
        c.pressKey(notes[b]);
        expect(c.resultAt(b), NoteResult.onBeat);
        c.releaseKey(notes[b]);
        c.onBeat();
      }
      expect(c.notesOnBeat, 8);
      expect(c.streak, 8);
    });

    test('bar completion advances to the next chord of the progression', () {
      final c = makeController(); // 1-6-2-5 in C
      countIn(c);
      expect(c.currentStep.chordLabel, 'C Major');
      for (var b = 0; b < 8; b++) {
        c.onBeat(); // all missed, but the drill keeps going
      }
      expect(c.stepIndex, 1);
      expect(c.currentStep.chordLabel, 'A Minor');
      expect(c.currentStep.modeLabel, 'A Aeolian');
    });

    test('finishing the progression advances the key (fifths)', () {
      final c = makeController();
      countIn(c);
      for (var i = 0; i < 4 * 8; i++) {
        c.onBeat(); // sweep all 4 bars
      }
      expect(c.keyPc, 7); // C -> G
      expect(c.stepIndex, 0);
      expect(c.currentStep.chordLabel, 'G Major');
    });

    test('startKeyPc sets the opening key', () {
      final c = ScaleRunController(chordsEnabled: true, startKeyPc: 10); // Bb
      expect(c.keyPc, 10);
      expect(c.keyLabel, 'A# Major');
      expect(c.currentStep.chordLabel, 'A# Major');
    });

    test('restarting returns to the chosen start key', () {
      final c = ScaleRunController(chordsEnabled: true, startKeyPc: 5); // F
      c.beatPeriodMs = () => 600;
      c.msSinceBeat = () => 0;
      countIn(c);
      for (var i = 0; i < 4 * 8; i++) {
        c.onBeat(); // full pass: F -> C (fifths)
      }
      expect(c.keyPc, 0);
      c.stop();
      c.start();
      expect(c.keyPc, 5); // back to F, not resuming from C
    });

    test('chromatic increment advances by semitone', () {
      final c = makeController(increment: KeyIncrement.chromatic);
      countIn(c);
      for (var i = 0; i < 4 * 8; i++) {
        c.onBeat();
      }
      expect(c.keyPc, 1); // C -> C#
    });
  });

  group('timing judgment', () {
    test('late-but-close press is amber, not a miss', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c);
      since = 100; // 100ms late
      c.pressKey(48);
      expect(c.resultAt(0), NoteResult.close);
      expect(c.streak, 1);
    });

    test('>150ms is a timing miss that breaks the streak', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c);
      c.pressKey(48); // beat 0 on time
      c.releaseKey(48);
      c.onBeat();
      since = 200; // beat 1, 200ms late
      c.pressKey(50);
      expect(c.resultAt(1), NoteResult.offTime);
      expect(c.streak, 0);
      expect(c.notesMissed, 1);
    });

    test('early press in the back half claims the NEXT beat', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c);
      c.pressKey(48);
      c.releaseKey(48);
      since = 520; // 80ms early for beat 1
      c.pressKey(50); // D, expected on beat 1
      c.releaseKey(50);
      since = 0;
      c.onBeat(); // advance: pending result lands on beat 1
      expect(c.beatIndex, 1);
      expect(c.resultAt(1), NoteResult.close);
      expect(c.resultAt(0), NoteResult.onBeat); // beat 0 was not overwritten
    });
  });

  group('mistakes keep the drill going', () {
    test('wrong pitch flashes and breaks streak but never rewinds', () {
      final c = makeController(chords: false);
      countIn(c);
      c.pressKey(48); // correct beat 0
      c.releaseKey(48);
      c.onBeat();
      c.pressKey(49); // C# — wrong on beat 1
      expect(c.notesWrong, 1);
      expect(c.streak, 0);
      expect(c.beatIndex, 1); // still beat 1, no rewind
      c.pressKey(50); // the right note still lands inside the window
      expect(c.resultAt(1), NoteResult.onBeat);
    });

    test('an unplayed beat settles as missed when the next beat ticks', () {
      final c = makeController(chords: false);
      countIn(c);
      c.onBeat(); // nothing played on beat 0
      expect(c.resultAt(0), NoteResult.missed);
      expect(c.notesMissed, 1);
      expect(c.beatIndex, 1);
    });
  });

  group('chord validation', () {
    test('chordHeldCorrectly tracks containment, run notes may overlap', () {
      final c = makeController(); // C major bar first
      countIn(c);
      expect(c.chordHeldCorrectly, false);
      c.pressKey(48); // C
      c.pressKey(52); // E
      c.pressKey(55); // G
      expect(c.chordHeldCorrectly, true);
      c.pressKey(50); // run note D on top doesn't invalidate the chord
      expect(c.chordHeldCorrectly, true);
    });

    test('leaving beat 0 without the chord counts a miss', () {
      final c = makeController();
      countIn(c);
      c.pressKey(48); // run degree 1 only, no chord
      c.onBeat();
      expect(c.chordMissedThisBar, true);
      expect(c.streak, 0);
    });

    test('re-striking a held chord tone is never judged wrong', () {
      final c = makeController();
      countIn(c);
      c.pressKey(48);
      c.pressKey(52);
      c.pressKey(55);
      c.onBeat(); // beat 1 expects D
      c.pressKey(52); // E re-strike: chord tone, not wrong
      expect(c.notesWrong, 0);
    });

    test('no-chords mode has an empty chord and an Ionian run', () {
      final c = makeController(chords: false);
      expect(c.currentStep.chordPcs, isEmpty);
      expect(c.currentStep.runPcs, [0, 2, 4, 5, 7, 9, 11, 0]);
      expect(c.chordHeldCorrectly, true);
    });
  });

  group('stop', () {
    test('stop returns to idle and clears results', () {
      final c = makeController(chords: false);
      countIn(c);
      c.pressKey(48);
      c.stop();
      expect(c.phase, RunPhase.idle);
      expect(c.resultAt(0), null);
      c.onBeat(); // ticks while idle are ignored
      expect(c.phase, RunPhase.idle);
    });
  });
}
