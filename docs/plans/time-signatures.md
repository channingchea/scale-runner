# Time Signatures — Implementation Plan

## Overview
The metronome gains a meter: No accent (today's behavior, still the default),
3/4, 4/4, 5/8 and 6/8. In any meter other than No accent, beat 1 of each bar
plays a higher-pitched click with a stronger haptic; every other beat is the
normal click (downbeat only, no secondary accents). A meter chip in the
expanded metronome bar picks it in every mode and the choice is remembered
globally, like BPM. A row of beat dots shows where you are in the bar. Jam
Mode bars and every count-in become one bar of the chosen meter; Scale
Running keeps its 8-note bars and restarts the accent cycle on each new scale.

## Non-goals / Out of scope
- No secondary accents (6/8 beat 4, 5/8 grouping) and no custom meters.
- BPM always means clicks per minute. In 5/8 and 6/8 each click is an eighth
  note, so 6/8 at 120 feels like a dotted-quarter pulse of 40. The picker
  subtitle says so; no tempo conversion.
- Scale Running's 8-note bar does not change shape (see Open questions).
- No change to BeatJudge timing windows, scoring or session length.

## What Scale Running needs to consider (asked for explicitly)
- Its bar is 8 clicks (7 degrees + octave), which fits 4/4 (accents on degree
  1 and 5) but not 3/4, 5/8 or 6/8. Chosen approach: the drill tells the
  metronome "next tick is a downbeat" at every bar rollover, so the accent
  cycle restarts with each new scale and the downbeat always lands on
  degree 1. In 3/4 that gives accents on degrees 1, 4, 7 then 1 again; in
  6/8 on 1 and 7; in 5/8 on 1 and 6.
- Its count-in is currently a hard-coded 4 beats (`beatsPerBar` default);
  it becomes one bar of the meter (3, 4, 5 or 6) so the first downbeat is the
  accented click. The count-in numbers UI reads `beatsUntilDownbeat`, which
  already derives from `beatsPerBar`.
- The chord-hold check on beat 1 and all the per-beat timing math are
  unaffected: they are per-click, not per-bar.
- Changing the meter mid-session would desync the count; the chip is disabled
  while a drill is counting in or running (Free Play and the quizzes can
  switch live).

## Phase 1: Meter model, accent sound, metronome engine
- [ ] `lib/runner/meter.dart`: `enum Meter { none, threeFour, fourFour,
      fiveEight, sixEight }` with `beatsPerBar` (4 for none, so drills keep
      today's count-in), `label` ("No accent", "3/4", ...), `accents` (true
      when not none).
- [ ] `tool/gen_click_samples.py` (sibling of `gen_note_samples.py`):
      regenerate `click.wav` byte-identical as a check, and write
      `click_accent.wav` as the same click a fifth higher with a slightly
      longer decay. Commit the asset; `assets/audio/` is already in
      `pubspec.yaml`.
- [ ] `MetronomeController`: `meter` field (setter re-aligns to beat 0 when
      idle, applies from the next bar when running), `beatInBar` getter
      (0-based), `barBeats`, and `markNextTickDownbeat()` for the Scale
      Running realignment. Second preloaded `AudioPlayer` for the accent
      sample. In `_tickNow`: advance `beatInBar`, call `onBeat` first (so a
      drill's `markNextTickDownbeat` from the previous tick has landed and
      the drill's state is current), then play the accent or normal click
      and `HapticFeedback.mediumImpact` vs `lightImpact`. `start()` resets
      `beatInBar` to 0 so the first tick is always the downbeat.
- [ ] `test/metronome_controller_test.dart`: beatInBar cycles at the meter's
      length; `none` never accents; `markNextTickDownbeat` resets the cycle
      on the following tick and not earlier; meter change while running takes
      effect at the next bar; drift test still passes with the accent path.
- [ ] `quiz_settings.dart`: `meter()` / `setMeter(Meter)` on key
      `metronome_meter`, default `Meter.none`.

## Phase 2: Metronome bar UI
- [ ] `metronome_bar.dart` expanded controls gain a meter chip after the "+"
      button: a `PopupMenuButton<Meter>` showing the current label ("4/4",
      or a struck-through metronome glyph for No accent) with the five
      options and the eighth-note tempo note as a subtitle on 5/8 and 6/8.
      Selecting persists via `QuizSettings.setMeter` (controller callback
      `onMeterChanged`, mirroring `onBpmChanged`).
- [ ] Beat dots: a row of `barBeats` 6 px dots under the BPM number (inside
      the pill, so the Row width does not grow), current beat lit in the
      accent color, dot 1 drawn larger. Hidden when the meter is No accent.
      On compact/landscape phones the pill is already tight; if the dots do
      not fit, drop them there first.
- [ ] `MetronomeBar` takes an optional `meterLocked` flag; drill screens pass
      true while their controller is counting in or running.
- [ ] Every screen that builds a `MetronomeController` (Quiz, Scale Run,
      Inversion Run, Jam, Voicings drill, Free Play) sets `meter` from the
      pref at bootstrap. The latency-calibration screen keeps `Meter.none`
      so its measurement stays a plain click.

## Phase 3: Drill integration
- [ ] `scale_run_screen.dart`: pass `beatsPerBar: meter.beatsPerBar` to
      `ScaleRunController`; wire a new `onBarStart` controller callback (fired
      in `_advance` when `_beatIndex` wraps, and at the count-in's downbeat)
      to `metronome.markNextTickDownbeat()` so the next click is accented.
      Since the count-in is one bar, the first drill downbeat is already
      aligned; the callback matters from bar 2 on.
- [ ] `jam_mode_screen.dart`: `beatsPerBar: meter.beatsPerBar` so one chord
      spans one bar of the meter; the count-in dots widget at line ~558
      already loops over `c.beatsPerBar`. Session length stays `sessionBars`
      chords regardless of bar length.
- [ ] `inversion_run_screen.dart`: `beatsPerBar: meter.beatsPerBar` for the
      opening count-in. The 2-beat inter-chord count-in stays; the drill
      calls `markNextTickDownbeat` on each cycle's step 0 so the root-position
      strike is the accented click even though a cycle's length does not fit
      the meter.
- [ ] Voicings drill and Chords/Scales quiz: accent only, no bar logic (their
      metronome is a plain click).
- [ ] Controller tests: `ScaleRunController` fires `onBarStart` at the right
      ticks for 3-, 5- and 6-beat count-ins; `JamModeController` judges one
      chord per 3/5/6 beats; `InversionRunController` opening count-in
      honors `beatsPerBar`.

## Phase 4: Verify
- [ ] `flutter analyze` + `flutter test` via Desktop Commander.
- [ ] On-device with a BLE keyboard: accent audible and the haptic
      distinguishable in every mode; Jam in 3/4 and 6/8 for a full session;
      Scale Running in 3/4 confirms the accent lands on degree 1 every bar;
      re-run the drift test scenario by ear (10 min at 120 in 6/8).
- [ ] Log the milestone to project memory.

## Open questions / risks
- Two `AudioPlayer`s firing on the same tick is fine (the note player already
  runs a pool of ten), but on Android low-latency mode the accent sample must
  be preloaded like the click or the first downbeat will be late. Preload
  both in the constructor.
- If a future version wants Scale Running bars to follow the meter for real
  (rests padded in, or a note per beat spilling across bars), that is a
  separate plan; this one keeps the 8-note bar.
- Secondary accents for 6/8 and 5/8 were deliberately left out; adding them
  later is a per-meter accent mask in `Meter` plus a third, quieter sample.
