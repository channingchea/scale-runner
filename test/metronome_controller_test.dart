import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/runner/meter.dart';
import 'package:scale_runner/widgets/metronome_bar.dart';

/// The metronome's drift-free clock: beats are scheduled at absolute ideal
/// times, so error never accumulates and judgment is against the ideal beat.
/// `silent: true` skips the audio player + haptics so tests run headless;
/// fake_async fakes both `clock.now()` and every Timer.
void main() {
  MetronomeController make({int bpm = 100}) =>
      MetronomeController(bpm: bpm, silent: true);

  test('zero cumulative drift over 10 simulated minutes', () {
    fakeAsync((async) {
      final m = make(); // 100 bpm → 600ms period
      var ticks = 0;
      m.onBeat = () => ticks++;
      m.start(); // tick 1 fires immediately at ideal time 0
      async.elapse(const Duration(minutes: 10));
      // 600_000ms / 600ms = exactly 1000 further ticks; any per-tick error
      // in a relative (Timer.periodic-style) clock would compound here.
      expect(ticks, 1 + 1000);
      m.stop();
      m.dispose();
    });
  });

  test('msSinceLastTick measures from the ideal beat time', () {
    fakeAsync((async) {
      final m = make()..start();
      async.elapse(const Duration(milliseconds: 250));
      expect(m.msSinceLastTick, 250);
      // Cross a beat boundary: 600ms period → at 850ms we're 250ms past tick 2.
      async.elapse(const Duration(milliseconds: 600));
      expect(m.msSinceLastTick, 250);
      m.stop();
      m.dispose();
    });
  });

  test('nudge rebases: next beat lands one new period after the last ideal '
      'tick', () {
    fakeAsync((async) {
      final m = make(); // 600ms period
      var ticks = 0;
      m.onBeat = () => ticks++;
      m.start();
      async.elapse(const Duration(milliseconds: 1300)); // ticks at 0, 600, 1200
      expect(ticks, 3);
      m.nudge(20); // 120 bpm → 500ms period; next beat ideal = 1200 + 500
      async.elapse(const Duration(milliseconds: 350)); // t=1650, before 1700
      expect(ticks, 3);
      async.elapse(const Duration(milliseconds: 100)); // t=1750, past 1700
      expect(ticks, 4);
      m.stop();
      m.dispose();
    });
  });

  test('registerHit judges with the injected difficulty windows', () {
    fakeAsync((async) {
      final strict = TimingDifficulty.strict; // 50 / 100
      final m = make()
        ..onBeatMs = strict.onBeatMs
        ..closeMs = strict.closeMs
        ..start();

      async.elapse(const Duration(milliseconds: 60)); // 60ms after the beat
      m.registerHit();
      expect(m.flash, BeatAccuracy.close); // ≤100 but >50

      async.elapse(const Duration(milliseconds: 540)); // next beat
      async.elapse(const Duration(milliseconds: 120));
      m.registerHit();
      expect(m.flash, BeatAccuracy.off); // >100 strict, would be close normal

      // Easy windows accept the same 120ms press as close, 60ms as on-beat.
      m
        ..onBeatMs = TimingDifficulty.easy.onBeatMs
        ..closeMs = TimingDifficulty.easy.closeMs;
      m.registerHit();
      expect(m.flash, BeatAccuracy.close);
      m.stop();
      m.dispose();
    });
  });

  test('difficulty enum carries the agreed windows', () {
    expect(TimingDifficulty.easy.onBeatMs, 100);
    expect(TimingDifficulty.easy.closeMs, 200);
    expect(TimingDifficulty.normal.onBeatMs, 70);
    expect(TimingDifficulty.normal.closeMs, 150);
    expect(TimingDifficulty.strict.onBeatMs, 50);
    expect(TimingDifficulty.strict.closeMs, 100);
  });

  group('meter', () {
    test('beatInBar cycles at the meter length and beat 0 is the accent', () {
      fakeAsync((async) {
        final m = MetronomeController(bpm: 100, silent: true)
          ..meter = Meter.threeFour;
        final beats = <int>[];
        final accents = <bool>[];
        m.onBeat = () {
          beats.add(m.beatInBar);
          accents.add(m.accentNow);
        };
        m.start();
        async.elapse(const Duration(milliseconds: 3100)); // ticks at 0..3000
        expect(beats, [0, 1, 2, 0, 1, 2]);
        expect(accents, [true, false, false, true, false, false]);
        m.stop();
        m.dispose();
      });
    });

    test('No accent never accents but still counts four to a bar', () {
      fakeAsync((async) {
        final m = MetronomeController(bpm: 100, silent: true);
        expect(m.meter, Meter.none);
        expect(m.barBeats, 4);
        final accents = <bool>[];
        m.onBeat = () => accents.add(m.accentNow);
        m.start();
        async.elapse(const Duration(milliseconds: 2500));
        expect(accents, everyElement(isFalse));
        expect(accents.length, 5);
        m.stop();
        m.dispose();
      });
    });

    test('markDownbeat from inside onBeat makes that very tick the accent',
        () {
      fakeAsync((async) {
        final m = MetronomeController(bpm: 100, silent: true)
          ..meter = Meter.fourFour;
        final accents = <bool>[];
        var ticks = 0;
        m.onBeat = () {
          ticks++;
          // A drill whose bar is 3 ticks long, restarting its cycle.
          if (ticks % 3 == 1) m.markDownbeat();
          accents.add(m.accentNow);
        };
        m.start();
        async.elapse(const Duration(milliseconds: 4200)); // 8 ticks
        expect(accents,
            [true, false, false, true, false, false, true, false]);
        expect(m.beatInBar, 1);
        m.stop();
        m.dispose();
      });
    });

    test('a meter picked while ticking waits for the bar to end', () {
      fakeAsync((async) {
        final m = MetronomeController(bpm: 100, silent: true)
          ..meter = Meter.fourFour;
        final beats = <int>[];
        m.onBeat = () => beats.add(m.beatInBar);
        m.start(); // beat 0 at t=0
        async.elapse(const Duration(milliseconds: 700)); // beat 1 at 600
        m.meter = Meter.threeFour;
        expect(m.meter, Meter.threeFour); // the chip shows it at once
        expect(m.barBeats, 4); // but the bar in progress finishes as 4/4
        async.elapse(const Duration(milliseconds: 3000)); // beats at 1200..3600
        expect(beats, [0, 1, 2, 3, 0, 1, 2]);
        expect(m.barBeats, 3);
        m.stop();
        m.dispose();
      });
    });

    test('a meter picked while idle applies at once, and start resets the bar',
        () {
      fakeAsync((async) {
        final m = MetronomeController(bpm: 100, silent: true);
        m.meter = Meter.sixEight;
        expect(m.barBeats, 6);
        expect(m.beatInBar, 0);
        var changes = 0;
        final n = MetronomeController(
          bpm: 100,
          silent: true,
          onMeterChanged: (_) => changes++,
        );
        n.meter = Meter.fiveEight;
        n.meter = Meter.fiveEight; // no-op
        expect(changes, 1);
        n.start();
        async.elapse(const Duration(milliseconds: 1300));
        expect(n.beatInBar, 2);
        n.stop();
        n.start();
        expect(n.beatInBar, 0);
        n.stop();
        m.dispose();
        n.dispose();
      });
    });

    test('drift stays zero with the accent path in place', () {
      fakeAsync((async) {
        final m = MetronomeController(bpm: 100, silent: true)
          ..meter = Meter.sixEight;
        var ticks = 0;
        m.onBeat = () => ticks++;
        m.start();
        async.elapse(const Duration(minutes: 10));
        expect(ticks, 1 + 1000);
        expect(m.beatInBar, 1000 % 6);
        m.stop();
        m.dispose();
      });
    });
  });

  test('Meter carries its bar lengths and labels', () {
    expect(Meter.none.beatsPerBar, 4);
    expect(Meter.threeFour.beatsPerBar, 3);
    expect(Meter.fourFour.beatsPerBar, 4);
    expect(Meter.fiveEight.beatsPerBar, 5);
    expect(Meter.sixEight.beatsPerBar, 6);
    expect(Meter.none.accents, isFalse);
    expect(Meter.fourFour.accents, isTrue);
    expect(Meter.sixEight.clicksEighths, isTrue);
    expect(Meter.threeFour.clicksEighths, isFalse);
    expect(Meter.fromName('sixEight'), Meter.sixEight);
    expect(Meter.fromName('waltz'), Meter.none);
    expect(Meter.fromName(null), Meter.none);
  });
}
