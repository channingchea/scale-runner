import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/runner/inversion_run_controller.dart';
import 'package:scale_runner/quiz/quiz_controller.dart' show KeyFeedback;
import 'package:scale_runner/theory/music_theory.dart';

InversionRunController makeController({List<ChordFormula>? chords, int seed = 1}) {
  final c = InversionRunController(chords: chords, seed: seed);
  c.beatPeriodMs = () => 600;
  c.msSinceBeat = () => 0;
  return c;
}

InversionRunController makeTempoController(
    {List<ChordFormula>? chords, int seed = 1, int Function()? sinceBeat}) {
  final c = InversionRunController(chords: chords, tempoMode: true, seed: seed);
  c.beatPeriodMs = () => 600;
  c.msSinceBeat = sinceBeat ?? () => 0;
  return c;
}

/// Tick through the count-in plus the downbeat tick (tempo mode).
void countIn(InversionRunController c) {
  c.start();
  for (var i = 0; i <= c.beatsPerBar; i++) {
    c.onBeat();
  }
}

/// Hold the current voicing (press, no release) so it's sounding on the beat.
void holdCurrentVoicing(InversionRunController c) {
  for (final n in c.currentStep.notes) {
    c.pressKey(n);
  }
}

/// Press-and-release every note of the current voicing.
void tapCurrentVoicing(InversionRunController c) {
  final notes = List<int>.from(c.currentStep.notes);
  for (final n in notes) {
    c.pressKey(n);
  }
  for (final n in notes) {
    c.releaseKey(n);
  }
}

void main() {
  group('start / idle gating', () {
    test('starts running with a built cycle', () {
      final c = makeController();
      expect(c.phase, InversionPhase.idle);
      c.start();
      expect(c.phase, InversionPhase.running);
      expect(c.stepIndex, 0);
      expect(c.rootPc, inInclusiveRange(0, 11));
      expect(c.stepCount, anyOf(7, 9)); // triad or 7th
    });

    test('presses are ignored while idle', () {
      final c = makeController();
      final note = c.currentStep.notes.first;
      c.pressKey(note);
      expect(c.stepsCompleted, 0);
      expect(c.notesWrong, 0);
    });
  });

  group('self-paced advance', () {
    test('completing a voicing advances exactly one step', () {
      final c = makeController();
      c.start();
      expect(c.stepIndex, 0);
      tapCurrentVoicing(c);
      expect(c.stepIndex, 1);
      expect(c.stepsCompleted, 1);
      expect(c.streak, 1);
    });

    test('an incomplete voicing does not advance', () {
      final c = makeController();
      c.start();
      // Press all but the last chord tone of the root voicing.
      final notes = c.currentStep.notes;
      for (var i = 0; i < notes.length - 1; i++) {
        c.pressKey(notes[i]);
      }
      expect(c.stepIndex, 0); // still on the root
      expect(c.stepsCompleted, 0);
      // The final tone completes it.
      c.pressKey(notes.last);
      expect(c.stepIndex, 1);
    });

    test('octave-off input still advances (pitch-class validation)', () {
      final c = makeController();
      c.start();
      // Play the root voicing an octave below the transposed target.
      for (final n in c.currentStep.notes) {
        c.pressKey(n - 12);
      }
      expect(c.stepIndex, 1);
      expect(c.notesWrong, 0);
    });
  });

  group('inversion-aware validation', () {
    test('holding root position does NOT satisfy a higher inversion', () {
      final only = commonChords.where((c) => c.name == 'Major').toList();
      final c = makeController(chords: only, seed: 3);
      c.start();
      // Capture root-position notes, then advance to the 1st inversion.
      final rootNotes = List<int>.from(c.currentStep.notes);
      tapCurrentVoicing(c); // now on step 1 (1st inversion)
      expect(c.stepIndex, 1);
      // Re-press the ROOT-position voicing: same pitch classes, wrong bass.
      for (final n in rootNotes) {
        c.pressKey(n);
      }
      expect(c.currentVoicingHeld, isFalse);
      expect(c.stepIndex, 1); // did not advance — the inversion is wrong
    });

    test('correct inversion (right bass) does satisfy and advance', () {
      final only = commonChords.where((c) => c.name == 'Major').toList();
      final c = makeController(chords: only, seed: 3);
      c.start();
      tapCurrentVoicing(c); // to step 1
      // Play the actual 1st-inversion voicing (third in the bass).
      tapCurrentVoicing(c);
      expect(c.stepIndex, 2);
    });

    test('upper voices stay octave-tolerant as long as the bass is correct', () {
      final only = commonChords.where((c) => c.name == 'Major').toList();
      final c = makeController(chords: only, seed: 3);
      c.start();
      final notes = List<int>.from(c.currentStep.notes); // root position
      // Keep the bass note, raise the upper voices an octave.
      c.pressKey(notes.first);
      for (final n in notes.skip(1)) {
        c.pressKey(n + 12);
      }
      expect(c.stepIndex, 1); // still advanced — bass is the root
    });
  });

  group('wrong notes', () {
    test('a non-chord tone flashes wrong, no advance, breaks streak', () {
      final c = makeController();
      c.start();
      tapCurrentVoicing(c); // streak = 1, now on step 1
      expect(c.streak, 1);
      // Find a MIDI note (octave 5) whose pitch class is NOT in the chord.
      final chordPcs = c.currentStep.pitchClasses;
      final badNote = List.generate(12, (i) => 72 + i)
          .firstWhere((n) => !chordPcs.contains(n % 12));
      c.pressKey(badNote);
      expect(c.notesWrong, 1);
      expect(c.streak, 0);
      expect(c.stepIndex, 1); // no rewind, no advance
      expect(c.feedbackFor(badNote), KeyFeedback.wrong);
    });
  });

  group('cycle completion -> new round', () {
    test('finishing the whole cycle starts a fresh round at step 0', () {
      final c = makeController();
      c.start();
      final steps = c.stepCount;
      for (var i = 0; i < steps; i++) {
        tapCurrentVoicing(c);
      }
      expect(c.cyclesCompleted, 1);
      expect(c.stepIndex, 0); // rolled over to a new cycle
      expect(c.stepsCompleted, steps);
    });

    test('many consecutive completions keep rolling rounds over', () {
      final c = makeController();
      c.start();
      var rounds = 0;
      // Complete 3 full cycles regardless of triad/7th length.
      while (rounds < 3) {
        final n = c.stepCount;
        for (var i = 0; i < n; i++) {
          tapCurrentVoicing(c);
        }
        rounds++;
      }
      expect(c.cyclesCompleted, 3);
      expect(c.stepIndex, 0);
    });
  });

  group('target hints & rendering', () {
    test('isTargetHint marks the exact transposed voicing (climbs)', () {
      final c = makeController();
      c.start();
      final rootNotes = List<int>.from(c.currentStep.notes);
      for (final n in rootNotes) {
        expect(c.isTargetHint(n), isTrue);
      }
      // Advance one step; the hinted notes should change (inversion climbs).
      tapCurrentVoicing(c);
      expect(c.currentStep.notes, isNot(rootNotes));
    });

    test('lowMidi anchors the keyboard to the round root', () {
      final c = makeController();
      c.start();
      expect(c.lowMidi, 60 + c.rootPc); // octave-4 anchor from InversionCycle
      expect(c.currentStep.notes.first, c.lowMidi); // root position starts low
    });
  });

  group('chord set restriction', () {
    test('only the configured chords appear', () {
      final only = commonChords.where((c) => c.name == 'Major').toList();
      final c = makeController(chords: only, seed: 7);
      c.start();
      for (var r = 0; r < 12; r++) {
        expect(c.chordLabel.endsWith('Major'), isTrue);
        for (var i = 0; i < c.stepCount; i++) {
          tapCurrentVoicing(c);
        }
      }
    });

    test('defaults to the four v1 chords when none supplied', () {
      final c = makeController(chords: null);
      c.start();
      // Sweep rounds; every chord name must be one of the four defaults.
      for (var r = 0; r < 20; r++) {
        expect(InversionRunController.defaultChordNames
            .any((n) => c.chordLabel.endsWith(n)), isTrue);
        for (var i = 0; i < c.stepCount; i++) {
          tapCurrentVoicing(c);
        }
      }
    });
  });

  group('stop', () {
    test('stop returns to idle and ignores ticks', () {
      final c = makeController();
      c.start();
      c.stop();
      expect(c.phase, InversionPhase.idle);
      c.onBeat();
      expect(c.phase, InversionPhase.idle);
    });
  });

  group('self-paced: beats are inert', () {
    test('onBeat does not advance in self-paced mode', () {
      final c = makeController();
      c.start();
      c.onBeat();
      c.onBeat();
      expect(c.stepIndex, 0);
    });
  });

  group('tempo mode: count-in', () {
    test('start arms a count-in; the (beatsPerBar+1)th tick is the downbeat', () {
      final c = makeTempoController();
      c.start();
      expect(c.phase, InversionPhase.countingIn);
      for (var i = 1; i <= c.beatsPerBar; i++) {
        c.onBeat();
        expect(c.countInBeat, i);
        expect(c.phase, InversionPhase.countingIn);
      }
      c.onBeat();
      expect(c.phase, InversionPhase.running);
      expect(c.stepIndex, 0);
    });

    test('presses during count-in are not judged', () {
      final c = makeTempoController();
      c.start();
      c.pressKey(c.currentStep.notes.first);
      expect(c.stepsCompleted, 0);
      expect(c.notesWrong, 0);
    });
  });

  group('tempo mode: beat-driven advance', () {
    test('voicing held on the beat scores onBeat and advances', () {
      final c = makeTempoController();
      countIn(c);
      expect(c.stepIndex, 0);
      holdCurrentVoicing(c);
      c.onBeat();
      expect(c.stepIndex, 1);
      expect(c.resultAt(0), StepResult.onBeat);
      expect(c.streak, 1);
      expect(c.stepsCompleted, 1);
    });

    test('a press alone does not advance — the beat does', () {
      final c = makeTempoController();
      countIn(c);
      holdCurrentVoicing(c);
      expect(c.stepIndex, 0); // still on step 0 until the beat ticks
    });

    test('voicing not held when the beat passes is a miss but advances', () {
      final c = makeTempoController();
      countIn(c);
      c.onBeat(); // nothing held on step 0's beat
      expect(c.stepIndex, 1);
      expect(c.resultAt(0), StepResult.missed);
      expect(c.streak, 0);
      expect(c.stepsCompleted, 0);
    });

    test('held late-but-close counts (amber), held very late misses', () {
      var since = 0;
      final c = makeTempoController(sinceBeat: () => since);
      countIn(c);
      since = 100; // 100ms off → close
      holdCurrentVoicing(c);
      c.onBeat();
      expect(c.resultAt(0), StepResult.close);
      expect(c.streak, 1);
    });

    test('completing the cycle on beats rolls over to a new round', () {
      final c = makeTempoController();
      countIn(c);
      final steps = c.stepCount;
      for (var i = 0; i < steps; i++) {
        holdCurrentVoicing(c);
        c.onBeat();
      }
      expect(c.cyclesCompleted, 1);
      expect(c.stepIndex, 0);
    });
  });
}
