import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/quiz/quiz_controller.dart' show KeyFeedback;
import 'package:scale_runner/runner/free_play_controller.dart';
import 'package:scale_runner/theory/chord_namer.dart';

void main() {
  group('FreePlayController — live (latch off)', () {
    test('readout follows the held set and release clears it', () {
      final c = FreePlayController();
      expect(c.readout, isNull);

      c.pressKey(60);
      expect(c.readout!.title, 'C4');
      c.pressKey(64);
      expect(c.readout!.title, 'Major 3rd');
      c.pressKey(67);
      expect(c.readout!.title, 'C Major');
      expect(c.readout!.detail, '1-3-5');

      c.releaseKey(67);
      expect(c.readout!.title, 'Major 3rd');
      c.releaseKey(64);
      c.releaseKey(60);
      expect(c.readout, isNull);
      expect(c.sounding, isEmpty);
    });

    test('taps and MIDI merge into one sounding set', () {
      final c = FreePlayController();
      c.pressKey(60);
      c.noteOn(64);
      c.noteOn(67);
      expect(c.sounding, {60, 64, 67});
      expect(c.readout!.title, 'C Major');
      c.noteOff(64);
      expect(c.sounding, {60, 67});
      expect(c.readout!.title, 'Perfect 5th');
    });

    test('feedback is pressed for sounding notes, idle otherwise, never a '
        'target hint', () {
      final c = FreePlayController();
      c.pressKey(60);
      expect(c.feedbackFor(60), KeyFeedback.pressed);
      expect(c.feedbackFor(61), KeyFeedback.idle);
      expect(c.isTargetHint(60), isFalse);
    });

    test('onAnyPress fires for taps and MIDI alike', () {
      final c = FreePlayController();
      final pressed = <int>[];
      c.onAnyPress = pressed.add;
      c.pressKey(60);
      c.noteOn(64);
      c.releaseKey(60);
      expect(pressed, [60, 64]);
    });

    test('notifies listeners on every change', () {
      final c = FreePlayController();
      var n = 0;
      c.addListener(() => n++);
      c.pressKey(60);
      c.releaseKey(60);
      c.releaseKey(60); // already up: nothing to say
      expect(n, 2);
    });
  });

  group('FreePlayController — Arpeggiated Notes (latch on)', () {
    test('tapped notes stay after release and build a chord', () {
      fakeAsync((async) {
        final c = FreePlayController(latchTaps: true);
        c.pressKey(60);
        c.releaseKey(60);
        expect(c.sounding, {60});
        expect(c.feedbackFor(60), KeyFeedback.pressed);
        c.pressKey(64);
        c.releaseKey(64);
        c.pressKey(67);
        c.releaseKey(67);
        expect(c.readout!.title, 'C Major');
        c.dispose();
      });
    });

    test('a second tap on a latched key releases it', () {
      fakeAsync((async) {
        final c = FreePlayController(latchTaps: true);
        final pressed = <int>[];
        c.onAnyPress = pressed.add;
        c.pressKey(60);
        c.releaseKey(60);
        c.pressKey(60);
        c.releaseKey(60);
        expect(c.sounding, isEmpty);
        expect(c.readout, isNull);
        // Putting a note out makes no sound.
        expect(pressed, [60]);
        c.dispose();
      });
    });

    test('two seconds with no new tap clears the latch', () {
      fakeAsync((async) {
        final c = FreePlayController(latchTaps: true);
        var n = 0;
        c.addListener(() => n++);
        c.pressKey(60);
        async.elapse(const Duration(milliseconds: 1500));
        c.pressKey(64); // restarts the clock
        async.elapse(const Duration(milliseconds: 1500));
        expect(c.sounding, {60, 64});
        async.elapse(const Duration(milliseconds: 600));
        expect(c.sounding, isEmpty);
        expect(c.readout, isNull);
        expect(n, 3); // two presses + the clear
        c.dispose();
      });
    });

    test('MIDI notes never latch, even with the setting on', () {
      fakeAsync((async) {
        final c = FreePlayController(latchTaps: true);
        c.noteOn(60);
        c.noteOff(60);
        expect(c.sounding, isEmpty);
        // ...and a held MIDI note survives the latch timeout.
        c.noteOn(67);
        c.pressKey(60);
        async.elapse(const Duration(seconds: 3));
        expect(c.sounding, {67});
        c.dispose();
      });
    });

    test('turning the setting off drops the latched notes', () {
      fakeAsync((async) {
        final c = FreePlayController(latchTaps: true);
        c.pressKey(60);
        c.pressKey(64);
        c.latchTaps = false;
        expect(c.sounding, isEmpty);
        c.pressKey(67);
        c.releaseKey(67);
        expect(c.sounding, isEmpty);
        c.dispose();
      });
    });

    test('the readout is a Readout from the chord namer', () {
      fakeAsync((async) {
        final c = FreePlayController(latchTaps: true);
        c.pressKey(52);
        c.pressKey(55);
        c.pressKey(57);
        c.pressKey(60);
        final r = c.readout!;
        expect(r.kind, ReadoutKind.chord);
        expect(r.title, 'A Minor 7th / E');
        c.dispose();
      });
    });
  });
}
