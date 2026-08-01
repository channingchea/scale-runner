# Reps Per Key (Scale Running) — Implementation Plan

## Overview
Add a "Reps per key" setting to the Scale Running drill that lets the player stay
on a single key for multiple passes before the key advances. Three options: 1x,
2x, 4x. At 2x the drill plays a full pass in the key twice, then moves to the next
key via the existing fifths/chromatic cycler. Default is 1x, so existing behavior
is unchanged for current users.

## Goals & Non-Goals
**Goals**
- A `repsPerKey` setting (1 / 2 / 4) persisted in SharedPreferences alongside the
  other run settings.
- The controller loops the same key `repsPerKey` times before advancing.
- A small on-screen rep counter ("C Major — 2/2") so the player knows where they
  are within the repeat.
- Per-key / per-mode weak-point tallies record on every pass (more reps = more
  data weight).
- Tests covering the loop-then-advance behavior.

**Non-Goals**
- No change to the 12-distinct-keys session length or the auto-end/summary.
- No per-mode or per-progression rep counts — one global setting.
- Not touching the Jam / Inversion / quiz modes.
- No change to timing thresholds (the deferred `onBeatMs`/`closeMs` discussion is
  separate).

## User Flow / UX
1. Player opens Scale Running settings → new "Reps per key" section shows a
   1x / 2x / 4x `SegmentedButton` (default 1x).
2. Selecting a value persists immediately and rebuilds the controller (same
   pattern as every other run setting).
3. On Start, the drill begins in the starting key. With reps = 2, the player
   completes a full pass (one scale run with chords off, or one full progression
   pass with chords on), then the same key repeats once more before advancing.
4. Near the key label, a counter shows the current rep, e.g. "2/2", and is hidden
   (or shows nothing extra) at 1x.
5. Session still ends after 12 distinct keys; at 2x that's 24 total passes and
   takes roughly twice as long.

## Technical Approach
A "rep" maps cleanly onto the existing notion of a pass: in `_advance()`, when
`_stepIndex >= _steps.length`, the current code immediately bumps the key. We
gate that bump on a rep counter.

**`lib/runner/scale_run_controller.dart`**
- Add constructor field `final int repsPerKey;` (default 1), passed through from
  the screen. Clamp/guard to the allowed set defensively but trust the setting.
- Add state `int _keyRepsDone = 0;` reset in `start()` and `resetScores()`.
- Add public getters for the UI:
  - `int get repIndex` → current rep number, 1-based (`_keyRepsDone + 1`).
  - `int get repsPerKeyCount` → `repsPerKey` (for "x/N" display).
- In `_advance()`, when `_stepIndex >= _steps.length` (a full pass just finished):
  - increment `_keyRepsDone`.
  - if `_keyRepsDone < repsPerKey`: **loop the same key** — set `_stepIndex = 0`,
    rebuild not required (same key, steps unchanged), and do NOT touch `_keyPc` or
    `keysCompleted`.
  - else (reps satisfied): reset `_keyRepsDone = 0`, then run the existing
    branch — bump `keysCompleted`, check the 12-key auto-end, advance `_keyPc`
    via the cycler, `_rebuildSteps()`, `_stepIndex = 0`.
- `keysCompleted` still counts distinct keys only, so the `sessionKeys` (12)
  auto-end is unchanged.
- Weak-point tallies are recorded per beat/bar inside the pass, so they
  automatically accumulate across reps with no extra code — matching "count every
  pass."
- Cross-bar lookahead (`_expectedPcAt` for beat 8 of the last bar): when a rep
  will loop, the "next" note is beat 0 of the same key's first step, not the next
  key. Update `_expectedPcAt` so that when the upcoming pass is a repeat (i.e.
  `_keyRepsDone + 1 < repsPerKey` at the moment of lookahead), it returns the
  current key's first step's `runPcs[0]` instead of computing the next key. This
  keeps early-hit judging correct on the boundary beat.

**`lib/quiz/quiz_settings.dart`**
- Add key `static const _runRepsKey = 'run_reps';`.
- `Future<int> runRepsPerKey()` → stored int, default 1, clamped to {1, 2, 4}
  (fall back to 1 if an unexpected value is read).
- `Future<void> setRunRepsPerKey(int reps)`.

**`lib/screens/scale_run_screen.dart`**
- In the controller build block, add
  `repsPerKey: await settings.runRepsPerKey(),`.
- In the prompt area (near the key label, `_buildPrompt`), render the rep counter
  when `repsPerKey > 1` and the drill is running/counting — e.g. a small muted
  "rep 2/4" or "2/2" chip/text consistent with existing label styling.

**`lib/widgets/scale_run_settings_sheet.dart`**
- Load `_reps` in `_init()`.
- Add a "Reps per key" section (header + `SegmentedButton<int>` with segments
  1x / 2x / 4x), styled like the existing "Key change" `SegmentedButton`.
- On change: `setState`, persist via `setRunRepsPerKey`, call `onChanged()`.
- Short helper text: "How many times to repeat each key before moving on."

## Task Breakdown
- [ ] Controller: add `repsPerKey` field + `_keyRepsDone` state, reset in
      `start()`/`resetScores()`.
- [ ] Controller: gate the key-advance branch in `_advance()` on the rep counter;
      loop same key until reps satisfied.
- [ ] Controller: add `repIndex` / `repsPerKeyCount` getters.
- [ ] Controller: fix `_expectedPcAt` boundary lookahead for an upcoming repeat.
- [ ] Settings: add `_runRepsKey`, `runRepsPerKey()` (default 1, clamp to
      {1,2,4}), `setRunRepsPerKey()`.
- [ ] Screen: pass `repsPerKey` into the controller build.
- [ ] Screen: render the rep counter near the key label when reps > 1.
- [ ] Settings sheet: add "Reps per key" 1x/2x/4x SegmentedButton section + load
      + persist + onChanged.
- [ ] Tests: appended to `test/scale_run_controller_test.dart` — see below.
- [ ] `flutter analyze` clean, `flutter test` green.

## Edge Cases & Failure Modes
- **reps = 1**: behavior byte-for-byte identical to today (counter hidden, key
  advances after one pass). Guard the new branch so the 1x path is unchanged.
- **Unexpected stored value** (e.g. legacy/garbage int): `runRepsPerKey()` clamps
  to {1,2,4}, defaulting to 1.
- **Changing reps mid-session**: settings change rebuilds the controller (drill
  stops/resets), so no live mutation of an in-flight session — consistent with
  all other run settings.
- **Boundary lookahead on the last bar of a pass that will repeat**: handled by
  the `_expectedPcAt` fix so early hits on the wrap beat judge against the same
  key, not the next.
- **12-key auto-end**: unaffected — `keysCompleted` only increments when reps are
  satisfied and the key actually changes.
- **Chords off**: a pass is a single step (one scale run), so reps loop that one
  step N times — the same gating logic applies.

## Success Criteria
- With reps = 2, chords off: the same key's scale run plays twice, then the key
  advances; session ends after 12 distinct keys (24 passes).
- With reps = 2, chords on: the full progression plays twice in the key, then
  advances.
- reps = 1 is indistinguishable from current behavior.
- Rep counter shows correct "x/N" and is hidden at 1x.
- Per-key/per-mode tallies reflect both passes.
- `flutter analyze` clean; `flutter test` green including new tests.

## Test Plan (test/scale_run_controller_test.dart)
- reps = 2 loops the same `keyPc` for two full passes before `keyPc` changes
  (drive `onBeat` through the bars with a fake clock, assert `keyPc` stays then
  advances).
- `keysCompleted` increments once per two passes at reps = 2 (distinct-key count).
- `repIndex` reports 1 then 2 across the two passes, resets to 1 on key change.
- reps = 1 path matches existing single-pass advance (regression guard).
- Auto-end still fires at 12 distinct keys with reps = 2.

## Open Questions / Risks
- Exact placement/styling of the rep counter is a small UI judgment call; will
  match the existing key-label treatment and keep it muted/subtle.
- None blocking.
