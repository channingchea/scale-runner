/// The single timing-scoring engine shared by every metronome-driven mode
/// (Scale Running, Jam Mode, Inversion Running).
///
/// Owns all press-vs-beat math: input-latency subtraction, the BLE "wrap"
/// case (key struck before a tick but delivered after it), early-for-next-beat
/// detection, and the on-beat / close / off verdict thresholds. Modes keep
/// their own musical validation (which pitches or chords are correct) and ask
/// this engine only *when* a correct unit landed.
///
/// Clock-agnostic like the controllers: [msSinceBeat], [beatPeriodMs], and
/// [latencyMs] are injected closures, so screens wire the metronome and tests
/// inject fakes.
library;

/// Timing verdict for a judged event.
enum BeatVerdict { onBeat, close, off }

/// Where a press landed relative to the metronome grid.
class PressTiming {
  const PressTiming({
    required this.early,
    required this.wrapped,
    required this.offBy,
  });

  /// The press is in the back half of the beat window: it targets the NEXT
  /// tick (an early hit for the coming beat).
  final bool early;

  /// The key was struck BEFORE the most recent tick but the event arrived
  /// after it (BLE delivery lag). Targets the CURRENT beat as an early hit;
  /// never [early], and never eligible to rescue an already-missed beat.
  final bool wrapped;

  /// Distance in ms from the target tick.
  final int offBy;
}

class BeatJudge {
  BeatJudge({
    required this.msSinceBeat,
    required this.beatPeriodMs,
    required this.latencyMs,
    required this.onBeatMs,
    required this.closeMs,
  });

  /// Milliseconds since the most recent metronome tick's ideal time.
  int Function() msSinceBeat;

  /// Beat period in ms at the current tempo.
  int Function() beatPeriodMs;

  /// Estimated input latency (ms) from key-strike to event delivery,
  /// subtracted before judging. Read per-press so screens can set it late.
  int Function() latencyMs;

  /// Verdict thresholds (ms), from the global timing-difficulty setting.
  final int onBeatMs;
  final int closeMs;

  /// Grace window: how long after a tick a late press can still score the
  /// beat that just passed. Matches [closeMs] in every mode.
  int get graceMs => closeMs;

  /// Judge a press that just arrived against the beat grid.
  ///
  /// A negative latency-shifted time means the key was struck before the
  /// current tick (BLE lag): that's an early hit on the CURRENT beat, judged
  /// directly. It must NOT wrap around and be attributed to the next beat —
  /// that would score a slightly-early correct note as a wrong pitch and
  /// leave its real beat to settle missed.
  PressTiming judgePress() {
    final period = beatPeriodMs();
    final rawSince = msSinceBeat().clamp(0, period);
    final shifted = rawSince - latencyMs();
    if (shifted < 0) {
      return PressTiming(early: false, wrapped: true, offBy: -shifted);
    }
    final since = shifted % period;
    final early = since > period / 2;
    return PressTiming(
      early: early,
      wrapped: false,
      offBy: early ? period - since : since,
    );
  }

  /// How far ahead of the COMING tick a press landed, for judging an early
  /// hit during the last count-in window (the key was struck [latencyMs]
  /// before the event arrived, i.e. even further ahead of the tick).
  int offByBeforeNextTick() {
    final period = beatPeriodMs();
    final since = msSinceBeat().clamp(0, period);
    return period - since + latencyMs();
  }

  /// Map a distance from the target tick to a verdict.
  BeatVerdict verdictFor(int offBy) => offBy <= onBeatMs
      ? BeatVerdict.onBeat
      : (offBy <= closeMs ? BeatVerdict.close : BeatVerdict.off);

  /// Whether a distance is close enough to rescue or pre-claim a beat.
  bool withinGrace(int offBy) => offBy <= graceMs;
}
