import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/quiz/quiz_settings.dart';
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
}
