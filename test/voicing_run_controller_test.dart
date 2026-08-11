import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/quiz/quiz_controller.dart' show KeyFeedback;
import 'package:scale_runner/runner/voicing_run_controller.dart';
import 'package:scale_runner/theory/voicings.dart';

/// Cmaj7 drop 2, 7th in the bass — sig [0,5,8,13], bass = the 7th.
VoicingSpec drop2Spec() => VoicingSpec(
      id: 'test',
      name: 'Maj7 drop 2',
      rootPc: 0,
      offsets: const [-1, 4, 7, 12],
      createdAt: DateTime.utc(2026),
    );

VoicingRunController make({
  VoicingSpec? spec,
  int startPc = 0,
  KeyIncrement increment = KeyIncrement.chromatic,
}) =>
    VoicingRunController(
      spec: spec ?? drop2Spec(),
      startPc: startPc,
      increment: increment,
    );

/// Press then release a set of notes, as a player would.
void play(VoicingRunController c, List<int> notes) {
  for (final n in notes) {
    c.pressKey(n);
  }
  for (final n in notes) {
    c.releaseKey(n);
  }
}

/// Play the current key's exact target voicing, optionally shifted by octaves.
void playCurrent(VoicingRunController c, {int transpose = 0}) =>
    play(c, [for (final n in c.currentStep.notes) n + transpose]);

void main() {
  group('start / idle gating', () {
    test('starts idle with the cycle built', () {
      final c = make();
      expect(c.running, isFalse);
      expect(c.isComplete, isFalse);
      expect(c.stepIndex, 0);
      expect(c.stepCount, 25); // chromatic
      expect(c.lowMidi, 48); // C3, fixed
      expect(c.keyLabel, 'C');
      expect(c.formulaLabel, '7-3-5-1');
    });

    test('presses are ignored while idle', () {
      final c = make();
      playCurrent(c);
      expect(c.stepIndex, 0);
      expect(c.keysCompleted, 0);
    });

    test('start resets to the first key', () {
      final c = make();
      c.start();
      playCurrent(c);
      expect(c.stepIndex, 1);
      c.start();
      expect(c.stepIndex, 0);
      expect(c.keysCompleted, 0);
      expect(c.running, isTrue);
    });
  });

  group('advancing — octave-agnostic, order-strict', () {
    test('the exact voicing advances one key', () {
      final c = make()..start();
      expect(c.currentStep.notes, [59, 64, 67, 72]);
      playCurrent(c);
      expect(c.stepIndex, 1);
      expect(c.keysCompleted, 1);
      expect(c.keyLabel, 'C#');
    });

    test('right shape, wrong register still passes', () {
      final c = make()..start();
      playCurrent(c, transpose: 12);
      expect(c.stepIndex, 1);
      final d = make()..start();
      playCurrent(d, transpose: -12);
      expect(d.stepIndex, 1);
    });

    test('right pitch classes, wrong spacing fails', () {
      final c = make()..start();
      play(c, [60, 64, 67, 71]); // close Cmaj7 — same tones, wrong voicing
      expect(c.stepIndex, 0);
      expect(c.keysCompleted, 0);
    });

    test('right spacing, wrong bass fails', () {
      final c = make()..start();
      play(c, [60, 65, 68, 73]); // the drop 2 shape, but rooted on C#
      expect(c.stepIndex, 0);
    });

    test('an incomplete voicing does not advance', () {
      final c = make()..start();
      final notes = c.currentStep.notes;
      for (var i = 0; i < notes.length - 1; i++) {
        c.pressKey(notes[i]);
      }
      expect(c.currentVoicingHeld, isFalse);
      expect(c.stepIndex, 0);
      c.pressKey(notes.last); // the last voice completes it
      expect(c.stepIndex, 1);
    });

    test('an extra held note blocks the match until it is lifted', () {
      final c = make()..start();
      c.pressKey(61); // a stray note that is not in the shape
      for (final n in c.currentStep.notes) {
        c.pressKey(n);
      }
      expect(c.currentVoicingHeld, isFalse);
      expect(c.stepIndex, 0);
      c.releaseKey(61); // lifting it leaves the correct shape sounding
      expect(c.stepIndex, 1);
      expect(c.keysCompleted, 1);
    });
  });

  group('wrong notes flash but never move the drill', () {
    test('an out-of-shape note flashes red and does not advance', () {
      final c = make()..start();
      c.pressKey(61); // C# — not a tone of this key's voicing
      expect(c.feedbackFor(61), KeyFeedback.wrong);
      expect(c.stepIndex, 0);
      expect(c.keysCompleted, 0);
    });

    test('a wrong note never rewinds progress', () {
      final c = make()..start();
      playCurrent(c);
      playCurrent(c);
      expect(c.stepIndex, 2);
      play(c, [60, 63, 64]); // none of these belong to the key of D
      expect(c.stepIndex, 2);
      expect(c.keysCompleted, 2);
    });

    test('the drill recovers: a fumble then the right shape still advances',
        () {
      final c = make()..start();
      play(c, [61]); // wrong
      play(c, [60, 64, 67, 71]); // right tones, wrong spacing
      expect(c.stepIndex, 0);
      playCurrent(c);
      expect(c.stepIndex, 1);
      expect(c.keysCompleted, 1);
    });

    test('a chord tone in the wrong place flashes back, not red', () {
      final c = make()..start();
      c.pressKey(64); // the 3rd — belongs to the shape
      expect(c.feedbackFor(64), KeyFeedback.correct);
    });
  });

  group('session end', () {
    test('a full chromatic traversal completes and fires onSessionEnd once',
        () {
      final c = make();
      var calls = 0;
      int? keys;
      Duration? elapsed;
      c.onSessionEnd = (k, e) {
        calls++;
        keys = k;
        elapsed = e;
      };
      c.start();
      for (var i = 0; i < 25; i++) {
        expect(c.stepNumber, i + 1);
        playCurrent(c);
      }
      expect(c.isComplete, isTrue);
      expect(c.running, isFalse);
      expect(c.keysCompleted, 25);
      expect(c.progress, 1.0);
      expect(c.stepNumber, 25); // readout holds at the end, doesn't overflow
      expect(c.currentStep.keyPc, 0); // finished back where it started
      expect(calls, 1);
      expect(keys, 25);
      expect(elapsed, isNotNull);
    });

    test('stopping early reports the keys landed so far, once', () {
      final c = make();
      var calls = 0;
      int? keys;
      c.onSessionEnd = (k, e) {
        calls++;
        keys = k;
      };
      c.start();
      playCurrent(c);
      playCurrent(c);
      playCurrent(c);
      c.stop();
      expect(calls, 1);
      expect(keys, 3);
      expect(c.running, isFalse);
      expect(c.isComplete, isFalse);
      c.stop(); // a second stop is a no-op
      expect(calls, 1);
    });

    test('a completed session does not fire again when stopped', () {
      final c = make();
      var calls = 0;
      c.onSessionEnd = (_, _) => calls++;
      c.start();
      for (var i = 0; i < 25; i++) {
        playCurrent(c);
      }
      c.stop();
      expect(calls, 1);
    });

    test('elapsed runs while playing and freezes at the end', () {
      final base = DateTime.utc(2026);
      var now = base;
      withClock(Clock(() => now), () {
        final c = make()..start();
        now = base.add(const Duration(seconds: 90));
        expect(c.elapsed, const Duration(seconds: 90));
        c.stop();
        now = base.add(const Duration(minutes: 10));
        expect(c.elapsed, const Duration(seconds: 90));
      });
    });
  });

  group('fifths sessions', () {
    test('run 12 keys and complete', () {
      final c = make(increment: KeyIncrement.fifths, startPc: 5)..start();
      expect(c.stepCount, 12);
      expect(c.keyLabel, 'F');
      for (var i = 0; i < 12; i++) {
        playCurrent(c);
      }
      expect(c.isComplete, isTrue);
      expect(c.keysCompleted, 12);
    });
  });

  group('keyboard rendering', () {
    test('target dots follow the current key', () {
      final c = make()..start();
      for (final n in [59, 64, 67, 72]) {
        expect(c.isTargetHint(n), isTrue);
      }
      expect(c.isTargetHint(60), isFalse);
      playCurrent(c);
      expect(c.isTargetHint(59), isFalse); // moved on to C#
      for (final n in c.currentStep.notes) {
        expect(c.isTargetHint(n), isTrue);
      }
    });

    test('a chord tone flashes, then stays lit for as long as it is held',
        () async {
      final c = make()..start();
      c.pressKey(59);
      expect(c.feedbackFor(59), KeyFeedback.correct); // the flash
      expect(c.feedbackFor(64), KeyFeedback.idle); // untouched key
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.feedbackFor(59), KeyFeedback.pressed); // flash faded, still held
      c.releaseKey(59);
      expect(c.feedbackFor(59), KeyFeedback.idle);
      c.dispose();
    });

    test('a wrong note stops flashing the moment it is released', () {
      final c = make()..start();
      c.pressKey(61);
      expect(c.feedbackFor(61), KeyFeedback.wrong);
      c.releaseKey(61);
      expect(c.feedbackFor(61), KeyFeedback.idle);
    });

    test('the keyboard never transposes mid-session', () {
      final c = make()..start();
      for (var i = 0; i < 5; i++) {
        expect(c.lowMidi, 48);
        playCurrent(c);
      }
    });
  });
}
