# Home Sections, Between-Key Count-In & Mode Onboarding — Implementation Plan

## Overview
Three UX changes to Scale Runner. (1) The home screen splits its single
"Practice" list into **Practice** (Free Play, Scales, Chords, Voicings) and
**Drills** (Scale Running, Inversion Running, Jam Mode). (2) Scale Running
gets a one-bar count-in before each new key, mirroring the opening count-in,
with the upcoming key shown and scoring paused. (3) Every mode gets a
first-entry guide sheet — a few lines of copy plus a looping,
instrument-aware demo built on `InstrumentSurface` — replayable from a "?"
button next to each mode's settings button.

## Non-goals / Out of scope
- No Skip Key control in Scale Running (the count-in is built so a future
  one can call the same entry point).
- No between-key count-in changes to Inversion Running or Jam Mode.
- No account-synced "seen" state; guide flags are per-device in
  `shared_preferences`.
- No interactive "play to continue" tutorial, no video assets.
- No "reset all guides" setting; the "?" button is the replay path.
- No changes to Pro gating, trial counters, or paywall flow.

## Phase 1: Home screen — Practice vs Drills
- [x] `home_screen.dart`: extract the inline `Text('Practice', …)` header
      into a `_SectionHeader(title, {caption})` widget (titleLarge/w700,
      optional 12px `textSecondary` caption).
- [x] Render two sections in `build()`: **Practice** → Free Play, Scales,
      Chords, Voicings (existing order); **Drills** (caption: "Timed
      exercises against the metronome") → Scale Running, Inversion Running,
      Jam Mode. 24px gap between sections; 14px between cards is unchanged.
- [x] Update the `// The three below are Pro` comment to note that the
      Drills section is the Pro set today, but the grouping is by exercise
      type, not gating.
- [x] `test/home_screen_test.dart`: assert both headers render and that
      Free Play/Scales/Chords/Voicings appear above "Drills" and the three
      drill cards appear below it (compare `tester.getTopLeft` y-offsets).

## Phase 2: Scale Running — between-key count-in

Controller (`lib/runner/scale_run_controller.dart`)
- [x] Add constructor param `bool keyCountInEnabled = true` and fields
      `int _countInTotal = 0`, `bool _openingCountIn = false` (same names
      as `InversionRunController`).
- [x] Add `void _enterKeyCountIn()`: sets `_phase = RunPhase.countingIn`,
      `_countInTotal = _countInRemaining = beatsPerBar`,
      `_openingCountIn = false`, `_stepIndex = 0`, `_beatIndex = 0`,
      `_pendingNext = null`. This is the single entry point a future Skip
      Key button would call.
- [x] In `_advance()`, at the key-advance branch (`_keyPc =
      KeyCycler(increment).next(_keyPc); _rebuildSteps();`): if
      `keyCountInEnabled`, call `_enterKeyCountIn()` after rebuilding steps
      instead of resetting `_stepIndex` inline; otherwise keep today's
      immediate rollover. The 12th-key auto-`stop()` runs before this branch
      and is unchanged (no count-in after the final key).
- [x] `start()`: set `_countInTotal = beatsPerBar` and
      `_openingCountIn = true`.
- [x] `onBeat()` countingIn case: fire `onBarStart` on the first count-in
      tick for both opening and key count-ins (`_countInRemaining ==
      _countInTotal`) so the accented click lands on it; on the downbeat
      tick set `_openingCountIn = false` before switching to running.
- [x] Backward-grace across the boundary: in `pressKey`, when `_phase ==
      countingIn && !_openingCountIn && _graceBeat != null`, route the press
      through the existing grace-rescue path (last note of the previous key
      keeps its one-beat second chance); clear grace on the next tick via the
      existing `_clearGrace()`.
- [x] Public getter `bool get isKeyTransition => _phase ==
      RunPhase.countingIn && !_openingCountIn;` — `keyLabel` already
      reflects the new key since `_keyPc` is advanced before the count-in.
- [x] Confirm `_absBeat`, `notesJudged`, streak and tallies are untouched
      during the count-in (no `_settleBeat` runs) — scoring pauses for free.
      Note this in a doc comment on `_enterKeyCountIn`.

Settings
- [x] `quiz_settings.dart`: `static const _runKeyCountInKey =
      'run_key_count_in'`; `Future<bool> runKeyCountIn()` (default `true`)
      / `setRunKeyCountIn(bool)`.
- [x] `scale_run_settings_sheet.dart`: add a `SwitchListTile` "Count in
      between keys" — subtitle "One bar of clicks before each new key so you
      can reset your hands" — placed after the reps-per-key control.
- [x] `scale_run_screen.dart` `_buildController()`: pass
      `keyCountInEnabled: await settings.runKeyCountIn()`.

Screen (`lib/screens/scale_run_screen.dart`)
- [x] `_buildRunControl` countingIn case: when `c.isKeyTransition`, replace
      the "Count-in…" label with "Next: ${c.keyLabel}" in `accent2`; keep
      the big `beatsUntilDownbeat` number.
- [x] `_buildPrompt`: during a key transition show the new key's first
      chord/scale prompt (steps are already rebuilt), so the target dots and
      prompt preview the upcoming key rather than going blank.

Tests
- [x] `test/scale_run_controller_test.dart`: after
      `steps.length × 8 × repsPerKey` running ticks, `phase == countingIn`,
      `isKeyTransition == true`, `keyPc` advanced by the increment; after
      `beatsPerBar` more ticks, `phase == running`, `beatIndex == 0`,
      `stepIndex == 0`.
- [x] `keyCountInEnabled: false` reproduces today's immediate rollover.
- [x] `notesJudged`/`notesMissed`/`streak` unchanged across the count-in
      ticks; `onBarStart` fires exactly once on the first count-in tick and
      once on the downbeat.
- [x] Early press in the last count-in window claims beat 0 of the new key
      (`_judgeFirstDownbeatPress` path).
- [x] Grace rescue: miss the last beat of key 1, press the expected note
      during count-in tick 1 → rescued.
- [x] 12th key completes → `stop()` fires with no trailing count-in.
- [x] `test/scale_run_settings_test.dart`: `runKeyCountIn` default/persist
      round-trip.

## Phase 3: Mode guide infrastructure

Model (`lib/onboarding/mode_guides.dart`)
- [x] `enum GuideMode { freePlay, scales, chords, voicings, scaleRunning,
      inversionRunning, jamMode }` with a `prefsKey` getter
      (`guide_seen_free_play`, …).
- [x] `class DemoFrame { final Set<int> midiNotes; final Duration hold;
      final String? caption; }` and `class ModeGuide { final String title;
      final List<String> lines; final List<DemoFrame> demo; }`.
- [x] `const Map<GuideMode, ModeGuide> modeGuides` with 3–4 lines of copy
      and a 4–8 frame demo script per mode (draft copy in the appendix;
      frames are MIDI notes in the C4–C6 range so piano renders them
      directly and guitar maps by pitch class).

Persistence (`lib/quiz/quiz_settings.dart`)
- [x] `Future<bool> guideSeen(GuideMode m)` / `Future<void>
      setGuideSeen(GuideMode m)` using `m.prefsKey`. Leave `introSeen`
      untouched (it's the app-level welcome).

Demo widget (`lib/widgets/guide_demo.dart`)
- [x] `GuideDemo({required List<DemoFrame> frames, required Instrument
      instrument, leftHanded, twinMode, labels})`: `StatefulWidget` with a
      `Timer`-driven frame index that loops; renders `InstrumentSurface`
      inside `IgnorePointer`, with `isTargetHint` = the frame's hint set and
      `feedbackFor` returning the "correct" feedback for lit notes so they
      read as pressed. No-op `onKeyDown`/`onKeyUp`. Caption `Text` below,
      fading between frames via `AnimatedSwitcher`, sticky across frames
      with no caption of their own. Cancel the timer in `dispose`.
- [x] Piano: `lowMidi` = 60, `octaves` = 2. Guitar: `boxAtRoot` at the
      frame's lowest pitch class, lit/hinted by pitch class
      (`pitchClassOf`).
- [x] `ModeGuideSheet.show` reads `instrument`, `leftHanded`,
      `guitarTwinMode`, `fretboardLabels` from `QuizSettings` and passes
      them through, matching what the mode screens do.

Sheet (`lib/widgets/mode_guide_sheet.dart`)
- [x] `ModeGuideSheet.show(BuildContext, GuideMode)` —
      `showModalBottomSheet` with the same surface/radius/drag-handle/
      gradient-title styling as `WelcomeSheet`.
- [x] Layout: title → `GuideDemo` (120px phone / 160px tall-device for
      piano, 170/220px for guitar's taller box) → numbered lines →
      `FilledButton` "Got it". Honours the 0.85 × screen-height cap and
      scrolls.

Tests
- [x] `test/mode_guide_test.dart`: data invariants (every mode has 3–4
      lines and a non-empty demo within the piano span, unique prefs keys),
      `guideSeen`/`setGuideSeen` round-trip and independence, `GuideDemo`
      frame advancement/looping/caption-stickiness, timer-cancel-on-dispose,
      and the sheet's render/dismiss.
- [x] `guideSeen` default/persist covered in the same file (folded into
      `test/mode_guide_test.dart` rather than a separate quiz_settings file).

## Phase 4: Wire guides into every mode + "?" buttons
- [x] Shared helper `Future<void> maybeShowGuide(BuildContext, GuideMode)`
      in `mode_guide_sheet.dart`: loads settings, if unseen → mark seen →
      show. Called from a post-frame callback in each screen's `initState`,
      after `_bootstrap()`/`_load()`.
- [x] `free_play_screen.dart` → `GuideMode.freePlay`; `quiz_screen.dart` →
      `scales`/`chords` by `QuizMode`; `voicings_screen.dart` (collection,
      not capture/drill) → `voicings`; `scale_run_screen.dart` →
      `scaleRunning`; `inversion_run_screen.dart` → `inversionRunning`;
      `jam_mode_screen.dart` → `jamMode`.
- [x] `IconButton(Icons.help_outline, tooltip: '<Mode> guide')` added
      immediately before the settings `IconButton` in `quiz_screen`,
      `scale_run_screen`, `inversion_run_screen`, `jam_mode_screen`,
      `voicing_drill_screen` (replays the voicings guide). Trailing slot on
      `free_play_screen` (with a 48px balancer so the metronome bar stays
      centred) and in the `voicings_screen` AppBar actions.
- [x] Scale Running: guide only fires on entry, before Start; the "?"
      button works mid-run without interrupting it.
- [x] Copy finalized from the appendix; one Jam Mode line was corrected
      against `jam_mode_controller.dart` (see gotchas below).
- [x] `test/mode_guides_screens_test.dart`: fresh device shows the guide on
      first push (Free Play, Scales, Scale Running), seeded device stays
      quiet, "?" replays regardless of the seen flag.
- [ ] Manual QA on phone + tablet, piano + guitar, portrait + landscape —
      not yet done. In particular: does the Scale Running first-run guide
      feel crowded arriving alongside the free-trial snackbar; does the
      guitar demo fit the sheet height on a small phone.

## Follow-up from review
- [x] Header "NEXT UP" cue (Option 1, chosen over enlarging the "Next: …"
      countdown label): during `c.isKeyTransition` the prompt's instruction
      line is replaced by an orange, letter-spaced "NEXT UP" eyebrow above
      the (already-updated) key name; the beat dots and chord-hold pill
      fade to 35% opacity via `AnimatedOpacity`; the countdown's own label
      reverts to plain "Count-in…" since the header now carries the cue.

## Gotchas for next session
- Six existing screen tests (`guitar_latch_screens_test`,
  `free_play_screen_test`, `quiz_screen_latch_test`,
  `voicings_screen_test`, `voicing_drill_dots_test`,
  `voicing_capture_guitar_test`) tap the instrument right after pumping the
  screen, which now collides with the auto-shown first-run guide sheet.
  Fixed by seeding `SharedPreferencesAsyncPlatform.instance` with
  `test/helpers/guides_seen.dart`'s `prefsWithGuidesSeen()` (every
  `GuideMode.prefsKey` → true) in their `setUp`, instead of
  `InMemorySharedPreferencesAsync.empty()`. Any new screen test that
  interacts with a mode screen immediately needs this same seeding, or it
  will find a guide sheet instead of the mode UI.
- `dart format` (Dart 3.12's tall style) was run across whole directories
  mid-session. The repo is NOT format-clean under that formatter (~90 files
  still use the older short style), so the run only produced churn. The
  format-only files were reverted, and the 2026-09-11 audit also restored
  HEAD formatting on the 14 touched files that still carried it (the diff
  went from +2215/-489 to +1593/-81, no behaviour change). Do not run
  `dart format` on existing files in this repo; new files may use either
  style.
- Audit 2026-09-11 also: `maybeShowGuide(context, mode)` now loads
  `QuizSettings` itself, so screens hook it straight from `initState`'s
  post-frame callback with no per-screen wrapper; em dashes removed from
  the guide copy (house rule); `QuizScreen._guideMode` getter.
- Grace-rescue credit bug found while building the between-key count-in:
  `_rescueGraceBeat` was crediting the *current* key/mode's tally rather
  than the one the miss was originally tallied under. Fixed by snapshotting
  `_graceKeyLabel`/`_graceModeName` in `_armGrace`. This was a latent bug
  even without the count-in feature (a bar/key rollover between a miss and
  its grace-window rescue), not something the count-in introduced.
- Jam Mode's guide copy originally claimed "the next chord is named a bar
  ahead" — unverified against the controller, so it was replaced with what
  `jam_mode_controller.dart` actually shows (the chord is on screen during
  its own count-in; strike it on the downbeat; a slightly late hit still
  scores within the grace window).

## Open questions / risks
- Between-key count-in with `repsPerKey > 1`: count-in only fires on a key
  change, not between reps — confirm that's the intent.
- Meter changes: `beatsPerBar` is locked while active, so the key count-in
  always matches the opening one.
- `InstrumentSurface` in `compact` mode may still be wide on small phones
  inside a sheet; may need a scale-down `FittedBox`.
- Should Inversion Running / Jam Mode get the same "Next: …" label
  treatment for consistency later? (Out of scope now.)

## Appendix: draft guide copy (3–4 lines each)
- **Free Play** — Play anything. Whatever's sounding is named live. Two
  notes show the interval, three or more the chord. The metronome is a
  plain click, no scoring.
- **Scales** — A key and scale are named at the top. Play it from the
  root, one note at a time. Correct notes light green, wrong ones red.
  Finish to get the next key.
- **Chords** — Build the named chord. Play notes one at a time or all at
  once. Hold it until it lights up. Next chord follows.
- **Voicings** — Capture a shape you like on the keys. Save it, then drill
  it through all 12 keys. Tap a saved voicing to run it.
- **Scale Running** — Hold the chord with one hand, run its mode with the
  other. One note per click, eight per bar. A one-bar count-in leads each
  new key.
- **Inversion Running** — Play the chord, then walk it up through its
  inversions and back down. Each inversion is built from scratch. In tempo
  mode, one inversion per beat.
- **Jam Mode** — One diatonic chord per bar, in one key. Land it on beat 1.
  Any voicing counts.
