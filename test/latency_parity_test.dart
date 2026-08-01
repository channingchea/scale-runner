import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/runner/jam_mode_controller.dart';
import 'package:scale_runner/runner/scale_run_controller.dart';
import 'package:scale_runner/runner/inversion_run_controller.dart';

void main() {
  group('Latency parity across controllers', () {
    test('ScaleRunController correctly scores late-arriving perfect hits', () {
      var since = 0;
      final c = ScaleRunController(
        chordsEnabled: false,
        onBeatMs: 70,
        closeMs: 150,
      )..msSinceBeat = (() => since)
       ..beatPeriodMs = (() => 600)
       ..inputLatencyMs = 40;

      c.start();
      for (var i = 0; i < 4; i++) {
        c.onBeat(); // count in
      }
      c.onBeat(); // downbeat 0 (beat 0)
      
      // Hit beat 0 properly so we can test beat 1
      c.pressKey(60 + c.currentStep.runPcs[0]);
      
      c.onBeat(); // downbeat 1 (beat 1)

      // Strike 10ms LATE for beat 1 (arrives 50ms post-tick due to 40ms latency)
      since = 50;
      c.pressKey(60 + c.currentStep.runPcs[1]);

      // Expected strikeSince = 50 - 40 = 10.
      // Expected offBy = 10 <= 70, targetBeat = 1 (direct hit, no grace needed).
      expect(c.resultAt(1), NoteResult.onBeat);
    });

    test('JamModeController correctly scores late-arriving perfect hits', () {
      var since = 0;
      final c = JamModeController(
        freestyle: false,
        onBeatMs: 70,
        closeMs: 150,
      )..msSinceBeat = (() => since)
       ..beatPeriodMs = (() => 600)
       ..inputLatencyMs = 40;

      c.start();
      for (var i = 0; i < 5; i++) {
        // 4 count-in ticks + the downbeat (same grid as Scale Running); empty
        // hands on the downbeat open the judging grace window.
        c.onBeat();
      }

      // After the beat, the grace window is open. The press arrived at 50ms (struck 10ms late).
      since = 50;
      final chord = c.currentChord!;
      for (final pc in chord.pitchClasses) {
         c.pressKey(60 + pc);
      }

      // Expected strikeSince = 50 - 40 = 10.
      // Because it arrived in judging phase, JamModeController calculates offBy = 10.
      // It scores it immediately as onBeat!
      expect(c.lastVerdict, JamResult.onBeat);

      // Test early prep
      c.start();
      for (var i = 0; i < 4; i++) {
        c.onBeat(); // full count-in (4 ticks); the next tick is the downbeat
      }
      since = 0;
      for (final pc in c.currentChord!.pitchClasses) {
         c.pressKey(60 + pc);
      }
      // Completed during the count-in and held through the downbeat.
      c.onBeat(); // the downbeat
      expect(c.lastVerdict, JamResult.onBeat);
    });

    test('InversionRunController correctly scores late-arriving perfect hits', () {
      var since = 0;
      final c = InversionRunController(
        tempoMode: true,
        onBeatMs: 70,
        closeMs: 150,
      )..msSinceBeat = (() => since)
       ..beatPeriodMs = (() => 600)
       ..inputLatencyMs = 40;

      c.start();
      for (var i = 0; i < 4; i++) {
        c.onBeat(); // count in
      }
      c.onBeat(); // downbeat 0 starts the first step
      
      // Let the first beat finish. It checks currentVoicingHeld. It's false, so missed, and sets _graceStepIndex = 0.
      c.onBeat(); // evaluated on beat 1 for step 0
      
      // Arrives 50ms after the beat.
      since = 50;
      for (final n in c.currentStep.notes) {
         c.pressKey(n); 
      }
      
      // Expected since = 50 - 40 = 10.
      // Expected offBy = 10 <= 70.
      // Rescued via grace window!
      expect(c.resultAt(0), StepResult.onBeat);
    });
  });

  // A note struck slightly BEFORE a tick whose event arrives (BLE lag) just
  // AFTER it: rawSince < inputLatencyMs, so the latency-shifted timestamp is
  // negative. It must be judged as an early hit on the beat that just ticked
  // — never wrapped around and attributed to the next beat.
  group('Latency wrap (struck before the tick, arrived after it)', () {
    test('ScaleRunController judges the current beat, not the next', () {
      var since = 0;
      final c = ScaleRunController(
        chordsEnabled: false,
        onBeatMs: 70,
        closeMs: 150,
      )..msSinceBeat = (() => since)
       ..beatPeriodMs = (() => 600)
       ..inputLatencyMs = 40;

      c.start();
      for (var i = 0; i < 5; i++) {
        c.onBeat(); // 4 count-in ticks + downbeat -> beat 0
      }

      // Struck 30ms before the beat-0 tick, arrives 10ms after it.
      since = 10;
      c.pressKey(60 + c.currentStep.runPcs[0]);

      // shifted = 10 - 40 = -30 -> early hit on beat 0, offBy 30 -> onBeat.
      expect(c.resultAt(0), NoteResult.onBeat);
      expect(c.notesWrong, 0,
          reason: "must not be judged against beat 1's pitch");

      c.onBeat(); // beat 0 settles: already judged, so no miss.
      expect(c.notesMissed, 0);
      expect(c.notesOnBeat, 1);
    });

    test('InversionRunController grace rescue reaches wrapped presses', () {
      var since = 0;
      final c = InversionRunController(
        tempoMode: true,
        onBeatMs: 70,
        closeMs: 150,
      )..msSinceBeat = (() => since)
       ..beatPeriodMs = (() => 600)
       ..inputLatencyMs = 40;

      c.start();
      for (var i = 0; i < 5; i++) {
        c.onBeat(); // count in + downbeat -> step 0
      }
      c.onBeat(); // settles step 0 unplayed: missed, grace window opens

      // Voicing completed 30ms before that settle tick; events arrive 10ms
      // after it. shifted = -30 -> offBy 30 -> rescued as onBeat.
      since = 10;
      for (final n in c.currentStep.notes) {
        c.pressKey(n);
      }
      expect(c.resultAt(0), StepResult.onBeat);
    });

    test('JamModeController scores a wrapped completion as onBeat', () {
      var since = 0;
      final c = JamModeController(
        freestyle: false,
        onBeatMs: 70,
        closeMs: 150,
      )..msSinceBeat = (() => since)
       ..beatPeriodMs = (() => 600)
       ..inputLatencyMs = 40;

      c.start();
      for (var i = 0; i < 5; i++) {
        c.onBeat(); // 4 count-in ticks + the downbeat; empty hands → grace opens
      }

      // Chord completed 30ms before the downbeat, arrives 10ms after it.
      since = 10;
      for (final pc in c.currentChord!.pitchClasses) {
        c.pressKey(60 + pc);
      }
      // shifted = -30 -> distance 30 <= 70 -> onBeat.
      expect(c.lastVerdict, JamResult.onBeat);
    });
  });
}
