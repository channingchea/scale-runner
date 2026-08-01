# Scale Running Scoring System — Implementation Plan

## Overview

Bring Jam Mode's full scoring/wrap-up layer to Scale Running. Scale Running already judges every note in real time (on-beat / close / off-time / missed) and shows a live streak + best streak, but it has none of the session-level scoring Jam Mode got: no end-of-session summary, no performance tier, no per-category weak-point breakdown, and no lifetime persistence. This adds those four things, structured to fit Scale Running's key-cycling design rather than Jam's fixed N-chord session.

The work mirrors the Jam Mode files (`jam_mode_controller.dart`, `jam_session_summary_sheet.dart`, the `jam_*_stats` helpers in `quiz_settings.dart`, and the summary wiring in `jam_mode_screen.dart`) so the two modes stay architecturally consistent.

## Goals & Non-Goals

### Goals
- Weak-point tracking along **two dimensions**: per **key** (C Major, G Major, …) and per **mode/degree** (Ionian/1, Dorian/2, …).
- A session = **one full lap of all 12 keys**. It auto-ends when the 12th key completes and shows the summary. It also ends on manual Stop or metronome collapse.
- **Accuracy** = right pitch within 150ms (on-beat or close). Off-time, missed, and wrong-pitch all count against. Identical to Jam Mode's definition.
- When chords are ON, the **chord hold folds into the same accuracy + weak-point stats** as run notes (a missed chord dings that bar's key and mode).
- End-of-session **summary sheet**: performance tier, overall accuracy, on-time %, best streak, weakest key + weakest mode.
- Performance **tier** with the same names and thresholds as Jam Mode: Opening Act (<70%), Local Legend (70–94%), International Recording Star (95–100%).
- **Lifetime persistence** of per-key and per-mode stats, with a reset action in Scale Running settings.

### Non-Goals (this pass)
- No new difficulty settings or timing thresholds — reuse the proven 70/150ms buckets already in the controller.
- No change to the run mechanics, key-cycle logic, count-in, or keyboard.
- No per-beat-position tracking and no separate chord-vs-run-hand score (considered and declined: chord folds into the unified score).
- No selectable session length (Jam's 12/24/48) — Scale Running's session is fixed at "all 12 keys."
- No leaderboards, history log, or cross-mode aggregate stats.

## User Flow / UX

1. User opens Scale Running, optionally adjusts settings, presses **Start**. A 1-bar count-in runs (unchanged), then the drill begins in the chosen start key.
2. The drill plays exactly as today — chord + run per bar, one note per beat, live dots + streak — but now the controller is also accumulating per-key and per-mode tallies in the background.
3. Keys advance via the existing `KeyCycler` (chromatic or fifths). The controller counts **distinct keys completed**. When the 12th distinct key finishes its last bar, the drill **auto-stops** and the summary sheet appears.
4. The summary sheet shows: the tier headline (gradient), Accuracy / On-time / Keys stat boxes, Best streak, and a "WORK ON" section naming the weakest key and weakest mode. A **Done** button dismisses it.
5. If the user instead presses **Stop** (or collapses the metronome) before all 12 keys finish, the drill ends early and the same summary appears for the partial session.
6. Lifetime per-key and per-mode stats are merged on session end. Over time the weakest-key / weakest-mode in future summaries reflect accumulated history. Settings gets a **"Reset lifetime stats"** tile (confirm dialog) under a "Lifetime stats" section, mirroring Jam Mode.

## Technical Approach

Four touch points, all paralleling existing Jam Mode code.

### 1. `lib/runner/scale_run_controller.dart` — tallies, tier, auto-end, snapshots
- Add a `RunTally{attempts, correct}` (or reuse the same shape Jam uses) and two `Map<String, RunTally>` fields: `_keyStats` (key = `keyLabel`, e.g. `"C Major"`) and `_modeStats` (key = mode name, e.g. `"Dorian"`, derived from `modeNames[(degree-1)%7]`).
- Every judged event updates both maps for the current bar's key and mode:
  - Run note: `attempts++`; `correct++` when result is `onBeat` or `close`. Off-time / missed / wrong-pitch → attempt only.
  - Chord hold (chords ON): on leaving beat 0, `attempts++` for key+mode; `correct++` if `chordHeldCorrectly`, else attempt only (this is the existing `_chordMissedThisBar` branch in `_advance()`).
- Add session aggregates derived from the existing counters: `accuracy` = (notesOnBeat + notesClose + correct-chords) / total judged; `onTimeRate` = notesOnBeat / total. Reuse `bestStreak` as-is. (Confirm exact formula against the live counters during build; keep accuracy's "correct = on-beat OR close" definition.)
- Add `weakestKey` / `weakestMode` getters: lowest-accuracy entry with attempts > 0 (tie-break by most attempts), returning the label string or null.
- Add `RunTier` enum `{openingAct, localLegend, internationalRecordingStar}` with a `.label` extension and `tierFor(double acc)` (<0.70 / 0.70–0.949 / ≥0.95, boundaries inclusive at 0.70 and 0.95 — match Jam's `tierFor`). Add a `tier` getter = `tierFor(accuracy)`.
- **Auto-end at 12 keys**: track distinct keys completed. Increment a `_keysCompleted` counter at the point the cycle advances to the next key (the `_stepIndex >= _steps.length` branch in `_advance()`, and the chords-off equivalent where each run is one key). When `_keysCompleted >= 12`, call `stop()` instead of advancing, and fire an `onSessionEnd` callback. Chords-off: each completed run = one key, so 12 runs. Chords-on: each completed progression = one key, so 12 progressions. "12 keys regardless."
- Add `qualitySnapshot`/`degreeSnapshot`-style getters (`keySnapshot` / `modeSnapshot`) returning `Map<String,(int,int)>` from the tally maps, for merging into prefs.
- Add `onSessionEnd` callback fired from `stop()` only when `wasActive` (phase != idle), so both stop paths (Stop button + metronome collapse) surface the summary exactly once — identical to Jam's guard.
- Reset all new tallies/counters in `start()` and `resetScores()`.

### 2. `lib/quiz/quiz_settings.dart` — persistence helpers
- Add keys `run_key_stats` and `run_mode_stats`, each a `List<String>` of `"key|attempts|correct"` (key names contain no `|`).
- Add `runKeyStats()` / `runModeStats()` → `Map<String,(int,int)>`, `mergeRunStats(key, mode)`, `resetRunStats()`. Reuse the existing private `_encodeStats` / `_decodeStats` / `_mergeStats` statics already in the file (built for Jam) — no new codec needed.

### 3. `lib/widgets/scale_run_session_summary_sheet.dart` — NEW
- Copy `jam_session_summary_sheet.dart`'s structure: a `RunSessionStats` plain snapshot (`.from(controller)` capturing accuracy / onTimeRate / bestStreak / tier / weakestKey / weakestMode / keysCompleted BEFORE reset) + a `ScaleRunSessionSummarySheet` modal.
- Headline = tier label (gradient). Stat boxes: Accuracy, On-time, Keys (count completed). Best streak wide box. "WORK ON" rows: Weakest key, Weakest mode. Done button.

### 4. `lib/screens/scale_run_screen.dart` — wire it up
- Set `controller.onSessionEnd = () => _endSession()`; `_endSession` guarded by an `_endingSession` bool, snapshots `RunSessionStats.from(c)`, `await settings.mergeRunStats(keySnapshot, modeSnapshot)`, then shows `ScaleRunSessionSummarySheet`. On auto-end also call `_metronome.stop()` (the metronome keeps ticking otherwise; the existing collapse listener's `phase != idle` guard prevents a double `onSessionEnd`).
- Stop button path: `c.stop()` then `m.stop()` — single `onSessionEnd` fire, same as Jam.

### 5. `lib/widgets/scale_run_settings_sheet.dart` — reset tile
- Add a "Lifetime stats" section with a reset ListTile → AlertDialog confirm → `settings.resetRunStats()` + snackbar. Copy Jam's settings-sheet section verbatim, renamed.

### Verification approach
Sandbox has no Dart SDK, so logic is **Python-verified first** (port the controller's tally/tier/auto-end state machine + the prefs codec round-trip, run all scenarios), then the user runs `flutter analyze` + `flutter test`. New tests go in `test/scale_run_controller_test.dart`: tally accumulation, accuracy/tier math, weakest-key/mode selection, auto-end at exactly 12 keys (chords-on and chords-off), `onSessionEnd` fires once on active stop / not when idle, snapshot round-trip.

## Task Breakdown

- [ ] Controller: add `RunTally`, `_keyStats`/`_modeStats`, update on every judged run note + chord hold.
- [ ] Controller: add `accuracy` / `onTimeRate` / `weakestKey` / `weakestMode` getters.
- [ ] Controller: add `RunTier` enum + `.label` + `tierFor` + `tier` getter.
- [ ] Controller: track distinct keys completed; auto-stop + `onSessionEnd` at 12 (both chords modes).
- [ ] Controller: add `keySnapshot` / `modeSnapshot` getters; reset new state in `start()` / `resetScores()`.
- [ ] Settings: `run_key_stats` / `run_mode_stats` keys + `runKeyStats` / `runModeStats` / `mergeRunStats` / `resetRunStats` (reuse existing codec).
- [ ] New `scale_run_session_summary_sheet.dart` (`RunSessionStats` + `ScaleRunSessionSummarySheet`).
- [ ] Screen: `onSessionEnd` → `_endSession` (snapshot, merge, show sheet); auto-end stops metronome; single-fire guard.
- [ ] Settings sheet: "Lifetime stats" + reset tile with confirm dialog.
- [ ] Tests in `test/scale_run_controller_test.dart`; Python-verify the state machine + codec first.
- [ ] User runs `flutter analyze` + `flutter test`; confirm on-device.

## Edge Cases & Failure Modes

- **Early stop before 12 keys**: summary shows the partial session; `keysCompleted` reflects only finished keys; stats still merge. Mid-key partial bars count toward accuracy but the in-progress key only counts as "completed" once its last bar finishes.
- **Double session-end** (auto-end fires, then metronome collapse listener also fires): prevented by the `wasActive` / `phase != idle` guard in `stop()` plus the `_endingSession` bool, exactly as Jam Mode handles it.
- **Empty session** (Start then immediate Stop, nothing judged): accuracy denominator is 0 → guard to avoid divide-by-zero (accuracy = 0, tier = Opening Act); summary's "WORK ON" rows show "—" when weakest getters return null (sheet already handles null).
- **Chords-off key counting**: each single run = one key; ensure the counter increments once per run, not per bar (there's only one bar per key in chords-off, so this is naturally aligned — verify).
- **Key label collision in stats**: keys are stored by `keyLabel` ("C Major"); chromatic vs fifths increment visits the same 12 labels, so a chromatic session and a fifths session merge into the same per-key buckets — intended.
- **Non-ASCII / pipe safety in codec**: key names ("C# Major") and mode names ("Locrian") contain no `|`; reuse Jam's codec which already round-trips such strings (Python-verify).

## Success Criteria

- A full 12-key session auto-ends and shows a summary with a tier, accuracy %, on-time %, keys count, best streak, and weakest key + mode.
- Accuracy matches the on-beat-or-close definition (manually traceable from the live counters).
- Stopping early shows a correct partial summary; no double summary in any stop path.
- Per-key and per-mode stats persist across app restarts; the settings reset clears them.
- `flutter analyze` clean, `flutter test` (incl. new scale-run scoring tests) green.
- Behaves correctly with chords ON and OFF, and with both key-increment modes.

## Open Questions / Risks

- **Exact accuracy denominator**: confirm during build whether the live `notesJudged` already includes chord-miss events (it does in `_advance()`), so accuracy = (onBeat + close + correctChords) / (notesJudged + chordAttempts) without double-counting. Resolve by reading the counters carefully before wiring — low risk, no design impact.
- **"Keys completed" definition at the 12th key**: auto-end should fire after the 12th key's final bar is judged, not when it's merely entered. Pin this down against `_advance()`'s key-advance branch so the last key's notes are fully scored before the summary.
- **Memory note**: this feature isn't yet built as of this plan; the existing [[scale-runner-scale-running-mode]] memory should be updated once shipped.
