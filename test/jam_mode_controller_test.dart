import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/runner/jam_mode_controller.dart';
import 'package:scale_runner/quiz/quiz_controller.dart' show KeyFeedback;
import 'package:scale_runner/theory/jam_mode.dart';

JamModeController makeController({
  int keyPc = 0,
  Set<JamFamily>? families,
  int seed = 1,
  int sessionBars = 1000, // large so the session doesn't auto-end mid-test
  bool freestyle = false,
  int Function()? sinceBeat,
}) {
  final c = JamModeController(
      keyPc: keyPc,
      families: families,
      seed: seed,
      sessionBars: sessionBars,
      freestyle: freestyle);
  c.beatPeriodMs = () => 600;
  c.msSinceBeat = sinceBeat ?? () => 0;
  return c;
}

/// Advance exactly one chord cycle: tick to the next downbeat (which judges the
/// current chord) and on into the next chord's count-in, leaving a fresh chord
/// shown and ready to be judged on the next downbeat.
///
/// If the downbeat opens a grace window (chord not complete on the beat), this
/// closes it synchronously via [JamModeController.debugResolveGrace] — standing
/// in for the real 150ms timer, which in the app fires *between* beats — so each
/// call judges exactly one chord and the count-in stays aligned.
void advanceOneChord(JamModeController c) {
  c.onBeat(); // the downbeat: judges the armed chord
  if (c.judging) c.debugResolveGrace();
  // The strike tick doubled as beat 1 of the next chord's bar; tick its
  // remaining count-in beats so the next chord is armed again.
  for (var i = 0; i < c.beatsPerBar - 1; i++) {
    c.onBeat();
  }
}

/// Start the drill and tick the count-in to the beat just before the first
/// chord's downbeat. After this, [c.currentChord] is the chord that the *next*
/// [c.onBeat] will judge, so a test can hold it then call [c.onBeat] once.
void armFirstChord(JamModeController c) {
  c.start();
  // The chord is drawn at start() and gets a full beatsPerBar-beat count-in;
  // the tick AFTER the count of beatsPerBar is its downbeat (same as Scale
  // Running: count 1-2-3-4, play on the next downbeat).
  for (var i = 0; i < c.beatsPerBar; i++) {
    c.onBeat();
  }
}

/// Back-compat name used across tests: arm the first chord ready to be judged.
void countIn(JamModeController c) => armFirstChord(c);

/// Freestyle helper: hold an arbitrary pitch-class set (root position, octave
/// 4). Pitch class 0 maps to MIDI 60.
void holdPcs(JamModeController c, Iterable<int> pcs) {
  for (final pc in pcs) {
    c.pressKey(60 + pc);
  }
}

/// Release every possible MIDI note — defensive cleanup between bars in tests
/// that build chords by raw pitch class rather than via [holdCurrentChord].
void releaseAll(JamModeController c) {
  for (final n in List.generate(128, (k) => k)) {
    c.releaseKey(n);
  }
}

/// Hold the prompted chord (root position, octave 4) so it's sounding on the
/// beat. Pitch class 0 maps to MIDI 60.
void holdCurrentChord(JamModeController c) {
  for (final pc in c.currentChord!.pitchClasses) {
    c.pressKey(60 + pc);
  }
}

void main() {
  group('start / idle gating', () {
    test('start arms a count-in with the first chord already shown', () {
      final c = makeController();
      expect(c.phase, JamPhase.idle);
      c.start();
      expect(c.phase, JamPhase.countingIn);
      // The chord is on screen for its whole count-in.
      expect(c.currentChord, isNotNull);
    });

    test('presses are ignored while idle', () {
      final c = makeController();
      c.pressKey(60);
      expect(c.barsJudged, 0);
      expect(c.notesWrong, 0);
    });

    test('onBeat is inert while idle', () {
      final c = makeController();
      c.onBeat();
      expect(c.phase, JamPhase.idle);
    });
  });

  group('count-in', () {
    test('the chord is shown through the count-in and judged on its downbeat',
        () {
      final c = makeController();
      c.start();
      expect(c.currentChord, isNotNull);
      // Tick through the full count-in: still counting in, same chord.
      final shown = c.currentChord!;
      for (var i = 0; i < c.beatsPerBar; i++) {
        c.onBeat();
        expect(c.phase, JamPhase.countingIn);
        expect(c.barsJudged, 0);
        expect(c.currentChord!.key, shown.key);
      }
      // Build the chord during the count-in, then the next tick (the downbeat)
      // judges the shown chord immediately.
      holdCurrentChord(c);
      c.onBeat();
      expect(c.barsJudged, 1);
    });

    test('presses during the count-in ARE judged (you build the chord early)',
        () {
      final c = makeController();
      c.start();
      // A non-chord press during count-in flashes wrong, as you prep the chord.
      final extra = List.generate(12, (i) => 60 + i)
          .firstWhere((n) => !c.currentChord!.pitchClasses.contains(n % 12));
      c.pressKey(extra);
      expect(c.notesWrong, 1);
      // But no bar is judged until the downbeat.
      expect(c.barsJudged, 0);
    });
  });

  group('beat-driven judging — timing buckets', () {
    test('chord held on the beat scores onBeat', () {
      final c = makeController();
      countIn(c);
      holdCurrentChord(c);
      c.onBeat();
      expect(c.barsOnBeat, 1);
      expect(c.barsJudged, 1);
      expect(c.streak, 1);
    });

    test('held within 150ms but past 70ms scores close', () {
      var since = 0;
      final c = makeController(sinceBeat: () => since);
      countIn(c);
      c.onBeat(); // Empty hands -> opens grace window
      since = 100; // Pressed 100ms late
      holdCurrentChord(c);
      expect(c.barsClose, 1);
      expect(c.barsOnBeat, 0);
      expect(c.streak, 1);
    });

    test('exactly 70ms is still onBeat; exactly 150ms is still close', () {
      var since = 0;
      final c = makeController(sinceBeat: () => since);
      countIn(c);
      c.onBeat(); // Empty hands -> opens grace window
      since = 70; // 70ms late is still onBeat!
      holdCurrentChord(c);
      expect(c.barsOnBeat, 1);

      var since2 = 0;
      final c2 = makeController(sinceBeat: () => since2);
      countIn(c2);
      c2.onBeat(); // Empty hands -> opens grace window
      since2 = 150; // 150ms late is exactly the edge of close!
      holdCurrentChord(c2);
      expect(c2.barsClose, 1);
    });

    test('nothing held when the beat passes is a miss', () {
      final c = makeController();
      countIn(c);
      c.onBeat(); // empty hands → opens the grace window
      expect(c.judging, isTrue);
      expect(c.barsJudged, 0); // not yet scored
      c.debugResolveGrace(); // grace closes with nothing played
      expect(c.barsMissed, 1);
      expect(c.streak, 0);
    });

    test('held very late (>150ms) misses', () {
      var since = 0;
      final c = makeController(sinceBeat: () => since);
      countIn(c);
      c.onBeat(); // Empty hands -> opens grace window
      since = 200; // Pressed 200ms late
      holdCurrentChord(c);
      expect(c.barsMissed, 1);
    });
  });

  group('octave-free validation, no extra notes', () {
    test('chord an octave up still matches', () {
      final c = makeController();
      countIn(c);
      for (final pc in c.currentChord!.pitchClasses) {
        c.pressKey(72 + pc); // octave above
      }
      expect(c.currentChordMatched, isTrue);
      c.onBeat();
      expect(c.barsOnBeat, 1);
    });

    test('doubled chord tone across octaves still matches', () {
      final c = makeController();
      countIn(c);
      final pcs = c.currentChord!.pitchClasses.toList();
      for (final pc in pcs) {
        c.pressKey(60 + pc);
      }
      c.pressKey(72 + pcs.first); // double the root an octave up
      expect(c.currentChordMatched, isTrue);
    });

    test('a single extra non-chord tone fails the match', () {
      final c = makeController();
      countIn(c);
      holdCurrentChord(c);
      expect(c.currentChordMatched, isTrue);
      // Add a pitch class guaranteed not in the chord.
      final extra = List.generate(12, (i) => i)
          .firstWhere((pc) => !c.currentChord!.pitchClasses.contains(pc));
      c.pressKey(60 + extra);
      expect(c.currentChordMatched, isFalse);
      c.onBeat(); // incomplete on the downbeat → grace window opens
      c.debugResolveGrace(); // still incomplete (extra note held) → miss
      expect(c.barsMissed, 1);
      expect(c.notesWrong, 1);
    });
  });

  group('wrong-note flashes', () {
    test('non-chord press flashes wrong, breaks streak, no bar judged', () {
      final c = makeController();
      countIn(c);
      holdCurrentChord(c);
      c.onBeat(); // streak = 1
      expect(c.streak, 1);
      final extra = List.generate(12, (i) => 60 + i)
          .firstWhere((n) => !c.currentChord!.pitchClasses.contains(n % 12));
      c.pressKey(extra);
      expect(c.notesWrong, 1);
      expect(c.streak, 0);
      expect(c.feedbackFor(extra), KeyFeedback.wrong);
    });
  });

  group('prompt picking', () {
    test('never repeats the same prompt on consecutive chords', () {
      final c = makeController(seed: 99);
      armFirstChord(c);
      var prev = c.currentChord!;
      for (var i = 0; i < 200; i++) {
        advanceOneChord(c); // judges prev, draws next
        expect(c.currentChord!.key == prev.key, isFalse);
        prev = c.currentChord!;
      }
    });

    test('every prompt stays within the enabled family set', () {
      final c = makeController(families: {JamFamily.triad}, seed: 5);
      armFirstChord(c);
      for (var i = 0; i < 50; i++) {
        expect(c.currentChord!.family, JamFamily.triad);
        advanceOneChord(c);
      }
    });
  });

  group('scoring by quality and degree', () {
    test('a judged bar records under its quality and degree keys', () {
      final c = makeController();
      countIn(c);
      final chord = c.currentChord!;
      holdCurrentChord(c);
      c.onBeat();
      expect(c.qualityScores[chord.qualityKey]!.attempts, 1);
      expect(c.qualityScores[chord.qualityKey]!.correct, 1);
      expect(c.degreeScores[chord.degreeKey]!.attempts, 1);
    });

    test('a miss records an attempt but not a correct', () {
      final c = makeController();
      countIn(c);
      final chord = c.currentChord!;
      c.onBeat(); // nothing held → grace opens
      c.debugResolveGrace(); // closes as a miss
      expect(c.qualityScores[chord.qualityKey]!.attempts, 1);
      expect(c.qualityScores[chord.qualityKey]!.correct, 0);
    });

    test('weakest quality/degree surfaces the lowest-accuracy bucket', () {
      final c = makeController(families: {JamFamily.triad}, seed: 5);
      armFirstChord(c);
      // Play a mix of hits and misses across several chords.
      for (var i = 0; i < 20; i++) {
        if (i.isEven) holdCurrentChord(c);
        advanceOneChord(c); // judges the held/empty chord, arms the next
        // release everything so the next chord starts clean
        for (final n in List.generate(128, (k) => k)) {
          c.releaseKey(n);
        }
      }
      expect(c.weakestQuality, isNotNull);
      expect(c.weakestDegree, isNotNull);
    });
  });

  group('tier boundaries', () {
    test('exactly 70% is Local Legend, just under is Opening Act', () {
      expect(tierFor(0.70), JamTier.localLegend);
      expect(tierFor(0.699), JamTier.openingAct);
    });
    test('exactly 95% is International Recording Star, just under is Legend', () {
      expect(tierFor(0.95), JamTier.internationalRecordingStar);
      expect(tierFor(0.949), JamTier.localLegend);
    });
    test('0% Opening Act, 100% International Recording Star', () {
      expect(tierFor(0.0), JamTier.openingAct);
      expect(tierFor(1.0), JamTier.internationalRecordingStar);
    });
  });

  group('accuracy + onTimeRate', () {
    test('accuracy = correct bars / judged bars', () {
      final c = makeController();
      armFirstChord(c);
      holdCurrentChord(c);
      advanceOneChord(c); // 1 correct, next chord armed
      for (final n in List.generate(128, (k) => k)) {
        c.releaseKey(n);
      }
      advanceOneChord(c); // 1 miss (empty hands)
      expect(c.barsJudged, 2);
      expect(c.accuracy, 0.5);
    });
  });

  group('reset + stop', () {
    test('resetScores clears all tallies and counters', () {
      final c = makeController();
      countIn(c);
      holdCurrentChord(c);
      c.onBeat();
      c.resetScores();
      expect(c.barsJudged, 0);
      expect(c.qualityScores, isEmpty);
      expect(c.degreeScores, isEmpty);
    });

    test('stop returns to idle and ignores ticks', () {
      final c = makeController();
      countIn(c);
      c.stop();
      expect(c.phase, JamPhase.idle);
      c.onBeat();
      expect(c.phase, JamPhase.idle);
    });
  });

  group('fixed session length + auto-end', () {
    test('auto-ends and tallies after the configured number of chords', () {
      final c = makeController(sessionBars: 3);
      var ended = 0;
      c.onSessionEnd = () => ended++;
      armFirstChord(c);
      // Play 3 chords; the 3rd downbeat should end the session.
      for (var i = 0; i < 3; i++) {
        holdCurrentChord(c);
        advanceOneChord(c);
        for (final n in List.generate(128, (k) => k)) {
          c.releaseKey(n);
        }
      }
      expect(c.barsJudged, 3);
      expect(c.phase, JamPhase.idle); // auto-stopped
      expect(ended, 1);
    });

    test('does not draw a chord past the final downbeat', () {
      final c = makeController(sessionBars: 2);
      armFirstChord(c);
      advanceOneChord(c); // chord 1 judged
      expect(c.phase, JamPhase.countingIn);
      advanceOneChord(c); // chord 2 judged → session ends
      expect(c.phase, JamPhase.idle);
      // Further ticks are inert.
      c.onBeat();
      expect(c.barsJudged, 2);
    });

    test('barsRemaining counts down to zero', () {
      final c = makeController(sessionBars: 3);
      expect(c.barsRemaining, 3);
      armFirstChord(c);
      advanceOneChord(c);
      expect(c.barsRemaining, 2);
    });
  });

  group('verdict confirmation flash', () {
    test('lastVerdict is set on the downbeat reflecting the judgement', () {
      final c = makeController();
      armFirstChord(c);
      holdCurrentChord(c);
      c.onBeat(); // downbeat judges chord 1 (held on beat)
      expect(c.lastVerdict, JamResult.onBeat);
    });

    test('a missed chord flashes a missed verdict', () {
      final c = makeController();
      armFirstChord(c);
      c.onBeat(); // empty hands on the downbeat → grace opens
      c.debugResolveGrace(); // closes unplayed → miss
      expect(c.lastVerdict, JamResult.missed);
    });
  });

  group('late-press grace window', () {
    test('a late press inside the grace window scores the CURRENT chord', () {
      var since = 0;
      final c = makeController(sinceBeat: () => since);
      armFirstChord(c);
      final chord = c.currentChord!;
      c.onBeat(); // downbeat, hands empty → grace window opens
      expect(c.judging, isTrue);
      expect(c.barsJudged, 0);
      // Now play the chord, slightly late — it should score THIS chord.
      since = 100; // 100ms late evaluates as close
      holdCurrentChord(c);
      expect(c.barsJudged, 1);
      expect(c.barsClose, 1); // properly evaluated based on 100ms offset
      // It was recorded under the chord that was showing, not a new one.
      expect(c.qualityScores[chord.qualityKey]!.correct, 1);
    });

    test('a late completion does not register as an attempt on the next chord',
        () {
      final c = makeController();
      armFirstChord(c);
      c.onBeat(); // grace opens on chord 1
      final next = c.currentChord!; // still chord 1 while judging
      holdCurrentChord(c); // late hit resolves chord 1, advances
      // Exactly one bar judged; the freshly-armed chord is untouched.
      expect(c.barsJudged, 1);
      expect(c.currentChord!.key == next.key, isFalse);
      expect(c.qualityScores[c.currentChord!.qualityKey], isNull);
    });

    test('grace window timing out unplayed is a miss for the current chord', () {
      final c = makeController();
      armFirstChord(c);
      c.onBeat(); // grace opens
      c.debugResolveGrace(); // timeout, nothing played
      expect(c.barsMissed, 1);
      expect(c.lastVerdict, JamResult.missed);
    });

    test('an early staccato stab within the grace window scores even after '
        'release', () {
      var since = 0;
      final c = makeController(sinceBeat: () => since);
      armFirstChord(c);
      since = 500; // struck 100ms before the downbeat → close
      final notes = [
        for (final pc in c.currentChord!.pitchClasses) 60 + pc,
      ];
      for (final n in notes) {
        c.pressKey(n);
      }
      for (final n in notes) {
        c.releaseKey(n); // staccato: hands off before the beat lands
      }
      since = 0;
      c.onBeat(); // the downbeat
      expect(c.barsClose, 1);
      expect(c.barsMissed, 0);
    });

    test('a chord completed on the downbeat needs no grace window', () {
      final c = makeController();
      armFirstChord(c);
      holdCurrentChord(c);
      c.onBeat(); // complete on the beat → judged immediately, no judging phase
      expect(c.judging, isFalse);
      expect(c.barsOnBeat, 1);
    });
  });

  group('session-end hook + snapshots', () {
    test('onSessionEnd fires once when an active session stops', () {
      final c = makeController();
      var fired = 0;
      c.onSessionEnd = () => fired++;
      countIn(c);
      c.stop();
      expect(fired, 1);
    });

    test('onSessionEnd does not fire when already idle', () {
      final c = makeController();
      var fired = 0;
      c.onSessionEnd = () => fired++;
      c.stop(); // never started
      expect(fired, 0);
    });

    test('snapshots mirror the session tallies as (attempts, correct)', () {
      final c = makeController();
      countIn(c);
      final chord = c.currentChord!;
      holdCurrentChord(c);
      c.onBeat(); // one correct bar
      final q = c.qualitySnapshot;
      final d = c.degreeSnapshot;
      expect(q[chord.qualityKey], (1, 1));
      expect(d[chord.degreeKey], (1, 1));
    });

    test('snapshots are empty before any bar is judged', () {
      final c = makeController();
      expect(c.qualitySnapshot, isEmpty);
      expect(c.degreeSnapshot, isEmpty);
    });
  });

  group('Freestyle mode', () {
    test('promptLabel reads Freestyle; there is no fixed currentChord', () {
      final c = makeController(freestyle: true);
      c.start();
      expect(c.promptLabel, 'Freestyle');
      expect(c.currentChord, isNull);
    });

    test('bar one: any diatonic chord from an enabled family scores a hit',
        () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      holdPcs(c, {0, 4, 7}); // I (C major triad)
      advanceOneChord(c);
      expect(c.barsOnBeat, 1);
      expect(c.barsMissed, 0);
    });

    test('a different degree after a hit is legal', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      holdPcs(c, {0, 4, 7}); // I
      advanceOneChord(c); // hit; forbidden degree becomes 1
      holdPcs(c, {2, 5, 9}); // ii
      advanceOneChord(c);
      expect(c.barsOnBeat, 2);
      expect(c.barsMissed, 0);
    });

    test('repeating the same degree next bar scores a miss, even in a '
        'different family', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      holdPcs(c, {0, 4, 7}); // I
      advanceOneChord(c); // hit; forbidden degree becomes 1
      holdPcs(c, {0, 4, 7, 11}); // Imaj7 — same degree (I)
      advanceOneChord(c);
      expect(c.barsMissed, 1);
      expect(c.barsOnBeat, 1);
    });

    test('a chord from a disabled family scores a miss even though diatonic',
        () {
      final c = makeController(freestyle: true, families: {JamFamily.triad});
      armFirstChord(c);
      holdPcs(c, {0, 4, 7, 11}); // Imaj7 — seventh family, disabled
      advanceOneChord(c);
      expect(c.barsMissed, 1);
    });

    test('a non-diatonic cluster never completes and times out as a miss',
        () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      holdPcs(c, {0, 1, 6}); // not a real diatonic chord shape
      c.onBeat(); // downbeat: incomplete → opens the grace window
      expect(c.judging, isTrue);
      c.debugResolveGrace();
      expect(c.barsMissed, 1);
    });

    test('liveChordMatch reflects the recognized chord while building', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      expect(c.liveChordMatch, isNull);
      holdPcs(c, {2, 5, 9}); // ii = Dm
      expect(c.liveChordMatch, isNotNull);
      expect(c.liveChordMatch!.chord.name, 'Dm');
      expect(c.liveChordMatch!.enabled, isTrue);
    });

    test(
        'liveChordIsRepeat flags the forbidden degree before the downbeat '
        'locks it in', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      holdPcs(c, {0, 4, 7}); // I
      advanceOneChord(c); // hit; forbidden degree becomes 1
      holdPcs(c, {0, 4, 7, 11}); // Imaj7 — same degree (I)
      expect(c.liveChordIsRepeat, isTrue);
    });

    test('a judged bar records the recognized chord under its quality and '
        'degree keys', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      holdPcs(c, {2, 5, 9}); // ii = Dm (minor triad)
      advanceOneChord(c);
      expect(c.qualityScores['m']!.attempts, 1);
      expect(c.qualityScores['m']!.correct, 1);
      expect(c.degreeScores['ii']!.attempts, 1);
    });

    test('freestyleForbiddenLabel is empty on bar one, then names the last '
        'legal chord', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      expect(c.freestyleForbiddenLabel, '');
      holdPcs(c, {2, 5, 9}); // ii = Dm
      advanceOneChord(c);
      expect(c.freestyleForbiddenLabel, 'not ii (Dm)');
    });

    test('a repeat miss does not clear the forbidden degree', () {
      final c = makeController(freestyle: true);
      armFirstChord(c);
      holdPcs(c, {0, 4, 7}); // I
      advanceOneChord(c); // hit; forbidden degree becomes 1
      holdPcs(c, {0, 4, 7, 11}); // Imaj7 — repeat, miss
      advanceOneChord(c);
      expect(c.freestyleForbiddenLabel, 'not I (C)'); // unchanged
    });
  });
}
