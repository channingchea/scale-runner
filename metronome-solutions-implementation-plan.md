# Metronome & Timing Score — Solutions Implementation Plan

## Overview
The 2026-07-07 audit found that "metronome scoring is too hard" is not
primarily a BLE-lag problem — it's a regression. `lib/runner/scale_run_controller.dart`
is byte-for-byte unchanged since commit `4f228ab`, while everything around it
(`lib/screens/scale_run_screen.dart`, `test/scale_run_controller_test.dart`,
`lib/quiz/quiz_settings.dart`, `IMPROVEMENT_PLAN.md`) was updated as if a
rewrite had already landed. The clearest proof: `lib/runner/inversion_run_controller.dart`
line 10 does `import 'scale_run_controller.dart' show RunTally, RunTier,
runTierFor;` — none of those three names exist in the current file, so the
project does not compile today. An orphaned, untracked
`lib/runner/scale_run_controller.dart.patch` (a diff against a ~500-line
version of the file, with grace-note rescue and `_expectedPcAt`) confirms a
larger version once existed and was lost.

Two concrete, verifiable bugs explain the "too hard" symptom on top of that:
1. No controller subtracts input latency when judging beat timing —
   `ScaleRunController.inputLatencyMs` and `defaultBleLatencyMs` don't exist,
   even though the screen already tries to set them. BLE notes are judged
   exactly when received, eating most of the 50–100ms Strict/Normal window.
2. `ScaleRunController.onBeatMs`/`closeMs` are hardcoded `static const 70/150`
   instead of constructor-injected, unlike `InversionRunController` and
   `JamModeController` — so the Settings timing-difficulty picker (Easy /
   Normal / Strict) silently does nothing in Scale Running.

This plan rebuilds the controller to match what the rest of the app already
expects, then closes the latency gap everywhere else it's missing.

**Prior art found in the repo:** two more implementation plans already exist —
`scale-running-scoring-implementation-plan.md` (2026-06-29, specs the
`RunTally`/tier/weakest-key-mode/summary-sheet/auto-end-at-12-keys layer) and
`reps-per-key-implementation-plan.md` (2026-06-30, specs `repsPerKey`/
`repIndex`/the `_expectedPcAt` boundary fix). Both are fully designed and
neither is marked done — and neither ever mentions latency or difficulty
injection at all (`reps-per-key`'s own Non-Goals explicitly defers that "to a
separate discussion"). So this scope was designed **three separate times**
(these two docs plus `IMPROVEMENT_PLAN.md` Phase 2.2/2.3) and never once
landed in the file. Phase 1 below treats those two docs as authoritative for
their slices and only adds new spec for the parts they don't cover (latency,
difficulty injection, backward grace).

## Goals & Non-Goals
**In scope:** restoring `ScaleRunController` to compile and match
`scale_run_screen.dart` / `test/scale_run_controller_test.dart`; adding
`inputLatencyMs` to `InversionRunController` and `JamModeController`;
relocating the BLE-latency constant so three screens can share it; a
per-device calibration screen (the deferred item from `IMPROVEMENT_PLAN.md`
2.2); a cross-controller regression test; a pass over `IMPROVEMENT_PLAN.md`'s
other "✅ DONE" claims.

**Out of scope:** Quiz mode (untimed, no metronome, unaffected). Changing the
Easy/Normal/Strict window values themselves. `flutter_midi_command` /
native BLE plugin internals — the packet parser and drift-free metronome
clock were already audited and are sound.

## Status checklist
- [x] Phase 1 — Rebuild `ScaleRunController` (restores compilation + fixes both confirmed bugs)
- [x] Phase 2 — Extend `inputLatencyMs` to Inversion Running & Jam Mode
- [x] Phase 3 — Per-device latency calibration screen (optional follow-up)
- [x] Phase 4 — Cross-controller latency-parity regression test
- [x] Phase 5 — Re-verify `IMPROVEMENT_PLAN.md`'s other "done" items against the actual files; retire the orphaned `.patch`

**2026-07-07 post-completion audit:** all phases verified in code. Three fixes
applied on top: (1) `ScaleRunController._judgePress` no longer wraps a
latency-shifted press past the tick — a note struck just before a tick but
delivered after it (BLE lag) is judged as an early hit on the current beat
instead of a wrong note on the next; (2) `InversionRunController`'s grace
rescue now reaches those wrapped presses; (3) the calibration screen clamps a
negative median offset to 0, and `_judgeFirstDownbeatPress` subtracts
`inputLatencyMs`. Regression tests: "Latency wrap" group in
`test/latency_parity_test.dart`. One deliberate deviation from Phase 2's task
list: per-mode fake-latency tests live consolidated in
`latency_parity_test.dart` rather than duplicated into each mode's test file.

---

## Phase 1 — Rebuild ScaleRunController
**Priority: first.** This is the actual bug; nothing else in the plan matters
until the project compiles again.

**Files:** `lib/runner/scale_run_controller.dart` (rewrite), cross-checked
against `lib/screens/scale_run_screen.dart`, `test/scale_run_controller_test.dart`,
`lib/widgets/scale_run_session_summary_sheet.dart`, `lib/quiz/quiz_settings.dart`,
`lib/runner/inversion_run_controller.dart` (the `show RunTally, RunTier,
runTierFor` import).

### Technical approach
Four sub-phases, ordered so each is independently testable against
`test/scale_run_controller_test.dart`'s existing groups. Build to green
rather than guessing at the API — the test file is the executable spec.

**1a. Scoring tallies, tier, auto-end, snapshots** — follow
`scale-running-scoring-implementation-plan.md` directly (still fully valid,
not superseded by anything since). Adds `RunTally`, `keyScores`/`modeScores`,
`accuracy`/`onTimeRate`/`tier` (`RunTier`/`runTierFor` — the exact symbols
`InversionRunController` already imports from this file), `weakestKey`/
`weakestMode`, `keySnapshot`/`modeSnapshot`, `keysCompleted`, `onSessionEnd`,
auto-end at 12 distinct keys. Its own Task Breakdown (10 items) and Test Plan
sections are the checklist — don't re-derive them here.

**1b. Reps per key** — follow `reps-per-key-implementation-plan.md`
directly. Adds the `repsPerKey` ctor field, `_keyRepsDone` state, `repIndex`/
`repsPerKeyCount` getters, the gated key-advance branch in `_advance()`, and
critically the `_expectedPcAt` boundary-lookahead fix for a pass that's
about to repeat rather than advance. Build 1a first — 1b's gating logic
sits inside the same `_advance()` branch 1a modifies for `keysCompleted`.

**1c. Latency + difficulty injection** — the piece neither prior plan
covers (both explicitly deferred it). Add `onBeatMs`/`closeMs` as ctor
params (default 70/150), replacing the hardcoded `static const` pair —
matches the pattern already used by `InversionRunController` and
`JamModeController`. Add `int inputLatencyMs = 0;` and
`static const int defaultBleLatencyMs = <TBD>;` (placeholder — see Phase 3
for a real number instead of a guess). In `_judgePress`, subtract
`inputLatencyMs` before computing `since`/`offBy`, wrapping into
`[0, period)` the same way `MetronomeController.registerHit` already does —
port that math, don't reinvent it.

**1d. Backward-note rescue ("grace")** — the one piece with no prior plan
doc at all, evidenced only by the test file's "backward grace" group and
the orphaned `.patch`. Add `graceMs` (= `closeMs`), `_graceBeat`,
`_graceStepIndex`, `_graceExpectedPc`, and `_rescueGraceBeat()` so a note
struck just after the next tick can still rescue the beat that just went
missed, mirroring `JamModeController`'s grace window. The `.patch` sketches
the out-of-bounds `targetBeat` guard this needs
(`targetBeat < 0 || targetBeat >= 8`) — reuse that guard, but note the
`.patch`'s base version predates 1a/1b/1c, so its `_judgePress` diff will
need re-adapting to whatever `_judgePress` looks like after 1a–1c land, not
applied as-is.

**Count-in display:** add `beatsUntilDownbeat` getter alongside 1a/1b (the
screen calls `c.beatsUntilDownbeat`; today only `countInBeat` exists) —
spec'd by "beatsUntilDownbeat counts down 4,3,2,1 to the downbeat". Keep the
existing `_expectedPcAt` bar-line lookahead as the base 1b modifies.

### Task breakdown
- [ ] 1a: implement per `scale-running-scoring-implementation-plan.md`'s own Task Breakdown.
- [ ] 1b: implement per `reps-per-key-implementation-plan.md`'s own Task Breakdown.
- [ ] 1c: add `onBeatMs`/`closeMs` ctor params + `inputLatencyMs` field + `defaultBleLatencyMs` placeholder constant; port latency subtraction into `_judgePress`.
- [ ] 1d: add backward-grace rescue (`graceMs`, `_graceBeat`, `_rescueGraceBeat`), including the out-of-bounds `targetBeat` guard.
- [ ] Add `beatsUntilDownbeat`.
- [ ] Run `test/scale_run_controller_test.dart` unmodified — every group should pass without editing the test file.
- [ ] `flutter analyze` clean — confirms `InversionRunController`'s `RunTally`/`RunTier`/`runTierFor` import resolves and the whole project compiles.
- [ ] Delete or fold in `lib/runner/scale_run_controller.dart.patch` once superseded (see Phase 5).

### Edge cases & failure modes
- A press whose shifted timestamp (`since - inputLatencyMs`) wraps past the
  bar boundary must still resolve to a valid beat, not `< 0` or `>= 8` —
  guard as the `.patch` does.
- Grace rescue must not leak across a fresh `start()` (separate test case
  already covers this).
- Grace rescue only applies within the same bar, and never to a beat whose
  slot is already judged — don't let it overwrite a correct hit.
- `repsPerKey` floors below 1 to 1 (a `0` or negative setting shouldn't
  freeze the drill on one key forever).

### Success criteria
- `flutter analyze` and `flutter test` both clean, with zero edits to
  `test/scale_run_controller_test.dart`.
- On a BLE keyboard, Scale Running's on-beat rate visibly improves at Normal
  difficulty once `defaultBleLatencyMs` is set to a non-zero placeholder
  (even before Phase 3's real calibration).
- Switching Timing Difficulty in Settings measurably changes Scale Running's
  windows (confirm via a quick on-device Easy vs. Strict comparison).

---

## Phase 2 — Extend latency compensation to Inversion Running & Jam Mode
**Files:** `lib/runner/inversion_run_controller.dart`,
`lib/runner/jam_mode_controller.dart`, `lib/screens/inversion_run_screen.dart`,
`lib/screens/jam_mode_screen.dart`.

The audit found neither of these controllers nor screens attempt BLE latency
correction at all today — only Scale Running was ever planned for it.

### Technical approach
- Add `int inputLatencyMs = 0;` to both controllers.
- Subtract it in `InversionRunController._settleAndAdvance` and
  `JamModeController._scoreCurrent`, same wrap-into-`[0, period)` pattern as
  Phase 1.
- **Relocate `defaultBleLatencyMs`** out of `ScaleRunController` — three
  screens needing a constant from an unrelated mode's controller is an
  awkward cross-dependency. Recommend moving it to `MidiService` (it's
  already the home of `isBleConnected`) or a small new
  `lib/midi/ble_latency.dart`. Update `scale_run_screen.dart`'s reference
  accordingly.
- Wire `widget.midi.isBleConnected ? <relocated constant> : 0` into
  `inversion_run_screen.dart` and `jam_mode_screen.dart`'s
  `_rebuildController`, matching the pattern already in `scale_run_screen.dart`.

### Task breakdown
- [ ] Relocate `defaultBleLatencyMs` to a shared location; update `scale_run_screen.dart`.
- [ ] Add `inputLatencyMs` field to `InversionRunController`; subtract in `_settleAndAdvance`.
- [ ] Add `inputLatencyMs` field to `JamModeController`; subtract in `_scoreCurrent`.
- [ ] Wire latency into `inversion_run_screen.dart` and `jam_mode_screen.dart`.
- [ ] Extend each mode's test file with a fake-latency case mirroring Scale Running's.
- [ ] `flutter analyze` + `flutter test` clean.

### Success criteria
All three beat-driven drills apply the same BLE latency correction; a BLE
user's experience is consistent across Scale Running, Inversion Running, and
Jam Mode.

---

## Phase 3 — Per-device latency calibration screen (optional follow-up)
Already flagged as deferred in `IMPROVEMENT_PLAN.md` 2.2. A hardcoded
`defaultBleLatencyMs` is a guess; real BLE MIDI latency varies by keyboard
and connection interval.

### Technical approach
- New `lib/screens/latency_calibration_screen.dart`: metronome ticks 8
  beats, user taps/plays along, app records the median offset.
- Persist via a new `QuizSettings.inputLatencyMs(deviceName)` /
  `setInputLatencyMs(deviceName, ms)`, keyed by MIDI device name (matches
  the existing `_lastDeviceName` auto-reconnect pattern in
  `MidiService`).
- All three screens read the stored per-device value instead of the shared
  constant, falling back to the constant (or 0) when no calibration exists
  yet for the connected device.
- Entry point: MIDI monitor screen ("Calibrate timing" button) — it's
  already the device-management surface.

### Task breakdown
- [ ] Build the calibration screen + median-offset capture.
- [ ] Add `QuizSettings` per-device latency storage.
- [ ] Wire all three run screens to read the stored value first, constant as fallback.
- [ ] Add an entry point from the MIDI monitor screen.
- [ ] `flutter analyze` + `flutter test` clean; on-device check with a real BLE keyboard.

### Success criteria
A user who calibrates their specific keyboard once gets consistently
accurate scoring across sessions and across all three drills, without
needing to know or guess a latency number.

---

## Phase 4 — Cross-controller latency-parity regression test
**Files:** new test, e.g. `test/latency_parity_test.dart` (or added to each
mode's existing test file).

Once Phase 1 and 2 both provide `inputLatencyMs`, add a test that fails if a
controller's judged beat timing doesn't shift by exactly the injected
latency — this is what would have caught today's drift the moment
`scale_run_screen.dart` started assuming a field the controller didn't have.

### Task breakdown
- [ ] Parametrized (or triplicated) test: for each of the three controllers, a press at a fixed `msSinceBeat` value judges differently (or identically) as `inputLatencyMs` changes, matching hand-computed expected verdicts.
- [ ] Add to CI-equivalent `flutter test` run.

### Success criteria
A future edit that adds latency handling to one controller but not another
(or silently drops it, as happened here) fails this test immediately.

---

## Phase 5 — IMPROVEMENT_PLAN.md hygiene + cleanup
**Files:** `IMPROVEMENT_PLAN.md`, `lib/runner/scale_run_controller.dart.patch`.

This file diverged silently once already while its plan doc still claimed
"done." Worth a trust-but-verify pass on the rest of the checklist before
relying on it again.

### Task breakdown
- [ ] Spot-check each "✅ DONE" item in `IMPROVEMENT_PLAN.md` Phases 1, 3, 4,
      and 5 against the actual current file (not just Phase 2, which this
      plan already disproved) — confirm the code is really there, not just
      checked off.
- [ ] Once Phase 1 above supersedes it, delete
      `lib/runner/scale_run_controller.dart.patch` (or, if it turns out to
      contain logic not otherwise captured, fold the relevant piece into
      Phase 1's rebuild before deleting it).
- [ ] Update `IMPROVEMENT_PLAN.md` to reflect this plan's completion once
      shipped, so the two documents don't drift apart again.

### Success criteria
`IMPROVEMENT_PLAN.md` accurately reflects the state of the code, and the
repo has no orphaned/untracked patch files describing work that isn't in
any tracked source file.

---

## Suggested sequencing
| Order | Work | Why |
|---|---|---|
| 1 | Phase 1 | Project doesn't compile without it; both confirmed "too hard" bugs live here |
| 2 | Phase 2 | Closes the same gap for the other two drills |
| 3 | Phase 4 | Cheap once 1 & 2 exist; locks in the fix |
| 4 | Phase 3 | Real calibration > hardcoded guess, but not blocking |
| 5 | Phase 5 | Housekeeping; do once the dust settles |

Run `flutter analyze` + `flutter test` after every phase, matching the
convention already established in `IMPROVEMENT_PLAN.md`.
