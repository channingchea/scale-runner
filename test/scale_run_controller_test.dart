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
  int repsPerKey = 1,
}) {
  final c = ScaleRunController(
    chordsEnabled: chords,
    progression: progression,
    increment: increment,
    startKeyPc: 0, // C
    repsPerKey: repsPerKey,
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

    test('beatsUntilDownbeat counts down 4,3,2,1 to the downbeat', () {
      final c = makeController();
      c.start();
      final expected = [4, 3, 2, 1];
      for (var i = 0; i < 4; i++) {
        c.onBeat();
        expect(c.beatsUntilDownbeat, expected[i]);
      }
      c.onBeat();
      expect(c.beatsUntilDownbeat, 0); // no longer counting in
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

  group('scoring tallies', () {
    test('a perfect chords-off run tallies the key and its Ionian mode', () {
      final c = makeController(chords: false);
      countIn(c); // running, beat 0, C Major
      const notes = [48, 50, 52, 53, 55, 57, 59, 60]; // C D E F G A B C
      for (var b = 0; b < 8; b++) {
        c.pressKey(notes[b]);
        c.releaseKey(notes[b]);
        c.onBeat();
      }
      // 8 beats judged, all on-beat.
      expect(c.notesOnBeat, 8);
      expect(c.accuracy, 1.0);
      expect(c.onTimeRate, 1.0);
      expect(c.tier, RunTier.internationalRecordingStar);
      expect(c.keyScores['C Major']!.attempts, 8);
      expect(c.keyScores['C Major']!.correct, 8);
      expect(c.modeScores['Ionian']!.attempts, 8);
    });

    test('a missed run note dings the bar\'s key and mode', () {
      final c = makeController(chords: false);
      countIn(c);
      c.onBeat(); // beat 0 unplayed -> missed
      expect(c.keyScores['C Major']!.attempts, 1);
      expect(c.keyScores['C Major']!.correct, 0);
      expect(c.modeScores['Ionian']!.correct, 0);
    });

    test('a held chord folds in as a correct, judged event', () {
      final c = makeController(); // chords on, C Major (degree 1, Ionian)
      countIn(c);
      // Hold C–E–G across beat 0. Leaving beat 0 records two correct events in
      // one tick: beat 0's run note (the C press is the degree-1 pitch) AND the
      // held chord — both against this bar's key + mode (Ionian).
      c.pressKey(48); // C
      c.pressKey(52); // E
      c.pressKey(55); // G
      c.onBeat(); // leaving beat 0 with the chord held
      expect(c.chordMissedThisBar, false);
      // No missed events: the run note landed and the chord was held.
      expect(c.notesMissed, 0);
      // Both the run note and the chord hold scored against Ionian / C Major.
      expect(c.modeScores['Ionian']!.attempts, 2);
      expect(c.modeScores['Ionian']!.correct, 2);
      expect(c.keyScores['C Major']!.correct, 2);
    });

    test('a missed chord is a judged attempt that is not correct', () {
      final c = makeController();
      countIn(c);
      // Play a non-chord, non-degree-1 note so beat 0's run note is NOT scored
      // and no full chord is held — isolating the chord miss.
      c.pressKey(50); // D — wrong for beat 0, no chord
      final attemptsBefore = c.modeScores['Ionian']?.attempts ?? 0;
      final correctBefore = c.modeScores['Ionian']?.correct ?? 0;
      c.onBeat(); // leaving beat 0 with no chord -> chord miss
      expect(c.chordMissedThisBar, true);
      // The chord miss adds one attempt to Ionian, none correct, and counts as
      // a judged miss (its own event, separate from the run-note miss on beat 0).
      expect(c.modeScores['Ionian']!.attempts, greaterThan(attemptsBefore));
      expect(c.modeScores['Ionian']!.correct, correctBefore);
      expect(c.notesWrong, 1); // the D press
    });

    test('accuracy is 0 and tier Opening Act for an empty session', () {
      final c = makeController();
      countIn(c);
      expect(c.accuracy, 0);
      expect(c.onTimeRate, 0);
      expect(c.tier, RunTier.openingAct);
      expect(c.weakestKey, isNull);
      expect(c.weakestMode, isNull);
    });
  });

  group('tier thresholds', () {
    test('boundaries are inclusive at 70% and 95%', () {
      expect(runTierFor(0.699), RunTier.openingAct);
      expect(runTierFor(0.70), RunTier.localLegend);
      expect(runTierFor(0.949), RunTier.localLegend);
      expect(runTierFor(0.95), RunTier.internationalRecordingStar);
      expect(runTierFor(1.0), RunTier.internationalRecordingStar);
    });

    test('tier labels match Jam Mode', () {
      expect(RunTier.openingAct.label, 'Opening Act');
      expect(RunTier.localLegend.label, 'Local Legend');
      expect(RunTier.internationalRecordingStar.label,
          'International Recording Star');
    });
  });

  group('weakest key / mode', () {
    test('the lowest-accuracy attempted key is the weak spot', () {
      final c = makeController(chords: false);
      countIn(c);
      // Key 1 (C Major): play every note perfectly.
      const cNotes = [48, 50, 52, 53, 55, 57, 59, 60];
      for (var b = 0; b < 8; b++) {
        c.pressKey(cNotes[b]);
        c.releaseKey(cNotes[b]);
        c.onBeat();
      }
      // Now in G Major (fifths). Miss everything for a full bar.
      expect(c.keyLabel, 'G Major');
      for (var b = 0; b < 8; b++) {
        c.onBeat();
      }
      expect(c.weakestKey!.key, 'G Major');
      expect(c.keyScores['G Major']!.correct, 0);
    });
  });

  group('session auto-end at 12 keys', () {
    test('chords-off auto-ends after 12 runs and fires onSessionEnd once', () {
      final c = makeController(chords: false);
      var ended = 0;
      c.onSessionEnd = () => ended++;
      countIn(c);
      // 12 keys * 8 beats. The 96th tick wraps the 12th key and auto-stops.
      for (var i = 0; i < 12 * 8; i++) {
        c.onBeat();
      }
      expect(c.keysCompleted, 12);
      expect(c.phase, RunPhase.idle);
      expect(ended, 1);
      // Further ticks are ignored and don't re-fire.
      c.onBeat();
      expect(ended, 1);
      expect(c.keysCompleted, 12);
    });

    test('chords-on auto-ends after 12 full progressions (4 bars each)', () {
      final c = makeController(); // 1-6-2-5, 4 steps/key
      var ended = 0;
      c.onSessionEnd = () => ended++;
      countIn(c);
      for (var i = 0; i < 12 * 4 * 8; i++) {
        c.onBeat();
      }
      expect(c.keysCompleted, 12);
      expect(c.phase, RunPhase.idle);
      expect(ended, 1);
    });

    test('stopping early surfaces the session once with a partial key count',
        () {
      final c = makeController(chords: false);
      var ended = 0;
      c.onSessionEnd = () => ended++;
      countIn(c);
      for (var i = 0; i < 3 * 8; i++) {
        c.onBeat(); // 3 keys
      }
      expect(c.keysCompleted, 3);
      c.stop();
      expect(ended, 1);
      c.stop(); // idle -> no-op, no second fire
      expect(ended, 1);
    });

    test('onSessionEnd does not fire when stop() runs on an idle controller',
        () {
      final c = makeController();
      var ended = 0;
      c.onSessionEnd = () => ended++;
      c.stop();
      expect(ended, 0);
    });
  });

  group('snapshots and reset', () {
    test('keySnapshot / modeSnapshot mirror the live tallies', () {
      final c = makeController(chords: false);
      countIn(c);
      c.onBeat(); // beat 0 missed in C Major / Ionian
      expect(c.keySnapshot['C Major'], (1, 0));
      expect(c.modeSnapshot['Ionian'], (1, 0));
    });

    test('start() resets all session scores', () {
      final c = makeController(chords: false);
      countIn(c);
      for (var i = 0; i < 8; i++) {
        c.onBeat();
      }
      expect(c.notesJudged, greaterThan(0));
      c.stop();
      c.start();
      expect(c.notesJudged, 0);
      expect(c.keysCompleted, 0);
      expect(c.keyScores, isEmpty);
      expect(c.modeScores, isEmpty);
    });
  });

  group('reps per key', () {
    test('reps=1 advances the key after one pass (unchanged behavior)', () {
      final c = makeController(chords: false); // 1 step/key
      countIn(c);
      expect(c.keyPc, 0);
      expect(c.repIndex, 1);
      expect(c.repsPerKeyCount, 1);
      for (var b = 0; b < 8; b++) {
        c.onBeat();
      }
      expect(c.keyPc, 7); // C -> G after one pass
      expect(c.keysCompleted, 1);
    });

    test('reps=2 loops the same key twice, then advances (chords off)', () {
      final c = makeController(chords: false, repsPerKey: 2);
      countIn(c);
      expect(c.keyPc, 0);
      expect(c.repIndex, 1);
      // First pass: 8 beats. Key must NOT change, rep ticks to 2.
      for (var b = 0; b < 8; b++) {
        c.onBeat();
      }
      expect(c.keyPc, 0, reason: 'still C on rep 2');
      expect(c.repIndex, 2);
      expect(c.keysCompleted, 0, reason: 'not a distinct key yet');
      // Second pass: now the key advances and counts once.
      for (var b = 0; b < 8; b++) {
        c.onBeat();
      }
      expect(c.keyPc, 7); // C -> G
      expect(c.repIndex, 1, reason: 'rep resets on key change');
      expect(c.keysCompleted, 1);
    });

    test('reps=2 chords-on repeats the full progression before advancing', () {
      final c = makeController(repsPerKey: 2); // 1-6-2-5, 4 bars/pass
      countIn(c);
      // First full progression pass (4 bars).
      for (var i = 0; i < 4 * 8; i++) {
        c.onBeat();
      }
      expect(c.keyPc, 0, reason: 'still C for rep 2');
      expect(c.repIndex, 2);
      expect(c.currentStep.chordLabel, 'C Major', reason: 'back to bar 1');
      // Second pass advances the key.
      for (var i = 0; i < 4 * 8; i++) {
        c.onBeat();
      }
      expect(c.keyPc, 7);
      expect(c.keysCompleted, 1);
    });

    test('session still auto-ends after 12 distinct keys at reps=2', () {
      final c = makeController(chords: false, repsPerKey: 2);
      var ended = 0;
      c.onSessionEnd = () => ended++;
      countIn(c);
      // 12 keys * 2 reps * 8 beats. Last tick wraps the 12th key.
      for (var i = 0; i < 12 * 2 * 8; i++) {
        c.onBeat();
      }
      expect(c.keysCompleted, 12);
      expect(c.phase, RunPhase.idle);
      expect(ended, 1);
    });

    test('both passes of a repeated key feed the weak-point tallies', () {
      final c = makeController(chords: false, repsPerKey: 2);
      countIn(c);
      // Miss every beat across both passes of C Major (2 * 8 = 16 events).
      for (var i = 0; i < 2 * 8; i++) {
        c.onBeat();
      }
      expect(c.keyScores['C Major']!.attempts, 16);
      expect(c.keyScores['C Major']!.correct, 0);
    });

    test('constructor floors reps below 1 to 1', () {
      final c = ScaleRunController(chordsEnabled: false, repsPerKey: 0);
      expect(c.repsPerKeyCount, 1);
    });
  });

  group('backward grace (late note rescues the missed beat)', () {
    // C major run from MIDI 48: C D E F G A B C.
    const notes = [48, 50, 52, 53, 55, 57, 59, 60];

    test('a note within graceMs rescues the just-missed beat as close', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c); // beat 0
      // Beat 0 played on time.
      c.pressKey(notes[0]);
      c.releaseKey(notes[0]);
      c.onBeat(); // -> beat 1 (expects D)
      // Beat 1 goes unplayed; next tick settles it missed and opens grace.
      c.onBeat(); // -> beat 2 (expects E), beat 1 now missed
      expect(c.resultAt(1), NoteResult.missed);
      expect(c.streak, 0);
      // Now play D (beat 1's note) 100ms into beat 2 — within graceMs.
      since = 100;
      c.pressKey(notes[1]); // D
      expect(c.resultAt(1), NoteResult.close, reason: 'rescued');
      expect(c.notesMissed, 0, reason: 'miss undone');
      expect(c.notesClose, 1);
      expect(c.streak, 1, reason: 'streak restored as a close hit');
    });

    test('a note beyond graceMs does NOT rescue the missed beat', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c);
      c.pressKey(notes[0]);
      c.releaseKey(notes[0]);
      c.onBeat(); // beat 1
      c.onBeat(); // beat 2, beat 1 missed + grace open
      since = 200; // past graceMs (150)
      c.pressKey(notes[1]); // D, too late to rescue
      expect(c.resultAt(1), NoteResult.missed, reason: 'still a miss');
      expect(c.notesMissed, 1);
    });

    test('rescue flips the per-key / per-mode tally to correct', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c);
      c.pressKey(notes[0]);
      c.releaseKey(notes[0]);
      c.onBeat();
      c.onBeat(); // beat 1 missed
      // Before rescue: C Major has 2 attempts (beats 0,1), 1 correct (beat 0).
      expect(c.keyScores['C Major']!.attempts, 2);
      expect(c.keyScores['C Major']!.correct, 1);
      since = 90;
      c.pressKey(notes[1]); // rescue beat 1
      expect(c.keyScores['C Major']!.correct, 2, reason: 'flipped to correct');
      expect(c.keyScores['C Major']!.attempts, 2, reason: 'no new attempt');
      expect(c.modeScores['Ionian']!.correct, 2);
    });

    test('a press matching the current beat is not stolen by grace', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c);
      c.pressKey(notes[0]);
      c.releaseKey(notes[0]);
      c.onBeat();
      c.onBeat(); // beat 2 (expects E), beat 1 (D) missed + grace open
      // Play E on time for beat 2 — matches the current beat, so it scores
      // beat 2 normally and leaves beat 1's miss intact.
      since = 0;
      c.pressKey(notes[2]); // E
      expect(c.resultAt(2), NoteResult.onBeat);
      expect(c.resultAt(1), NoteResult.missed, reason: 'beat 1 not rescued');
    });

    test('grace does not leak across a fresh start', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c);
      c.onBeat(); // beat 0 missed, grace open
      c.stop();
      c.start();
      for (var i = 0; i < 4; i++) {
        c.onBeat(); // count-in
      }
      c.onBeat(); // downbeat, beat 0
      since = 100;
      c.pressKey(notes[0]); // on-time-ish beat 0 of the new session
      // Should score beat 0 normally, not rescue anything from the old session.
      expect(c.resultAt(0), isNotNull);
      expect(c.notesClose + c.notesOnBeat, 1);
    });

    test('the last beat of a bar is rescued across the bar rollover', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c); // beat 0
      // Let the whole bar go unplayed: every beat settles missed, and the 8th
      // tick settles beat 7 and immediately rolls the bar over.
      for (var i = 0; i < 8; i++) {
        c.onBeat();
      }
      expect(c.notesMissed, 8);
      // Beat 7's note (C) arrives 100ms into the new bar - within graceMs of
      // the tick it was aimed at. Before the rollover fix this scored as a
      // wrong note on top of the miss, every single bar.
      since = 100;
      c.pressKey(notes[7]); // C, an octave up
      expect(c.notesMissed, 7, reason: 'the miss is undone');
      expect(c.notesClose, 1);
      expect(c.notesWrong, 0, reason: 'not also punished as a wrong pitch');
      expect(c.streak, 1);
      expect(c.resultAt(7), isNull,
          reason: "the new bar's beat 7 slot is left alone");
    });

    test('grace expires after one beat, not at the end of the bar', () {
      var since = 0;
      final c = makeController(chords: false, sinceBeat: () => since);
      countIn(c);
      c.pressKey(notes[0]); // beat 0 on time
      c.releaseKey(notes[0]);
      c.onBeat(); // -> beat 1
      c.onBeat(); // -> beat 2, beat 1 (D) missed + grace open
      // Play beats 2 and 3 correctly so nothing re-arms grace.
      c.pressKey(notes[2]);
      c.releaseKey(notes[2]);
      c.onBeat(); // -> beat 3
      c.pressKey(notes[3]);
      c.releaseKey(notes[3]);
      c.onBeat(); // -> beat 4, three beats past the miss
      since = 100;
      c.pressKey(notes[1]); // D, still inside graceMs of beat 4's tick
      expect(c.resultAt(1), NoteResult.missed,
          reason: 'grace only covers the beat immediately after the miss');
      expect(c.notesWrong, 1);
    });
  });
}
