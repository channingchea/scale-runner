# Inversion Running — Tempo-Mode Next-Chord Preview — Implementation Plan

## Overview
Inversion Running's tempo mode currently drops a brand-new chord + root at
every cycle boundary with zero warning — much harsher than a single missed
beat, since the player then has to sight-read an unfamiliar chord while
already mid-climb at tempo. This plan adds a short, readable pause at cycle
boundaries (tempo mode only) during which the next chord is already on
screen before its first judged beat.

## Goals & Non-Goals
In scope: a short inter-chord count-in in tempo mode, triggered only at
cycle boundaries (not every step); correct on-screen countdown math for a
count-in whose length differs from the session-start count-in.
Out of scope: self-paced mode (unaffected — no beat to miss, chord is
already visible the instant it appears); per-step (every beat) previews;
disabling tempo mode.


## User Flow / UX
In tempo mode, when a cycle completes (the climb up and back down finishes)
and another chord follows, the drill no longer rolls straight into the next
chord's first beat. Instead: the next chord/root is picked immediately (as
today), the prompt area's chord name updates to it right away (it already
does this unconditionally, no new UI needed), and a brief 2-beat pause plays
with the existing "Get ready…" count-in treatment before judging resumes on
the downbeat. Self-paced mode is untouched: cycle rollover is instant, same
as today.

## Technical Approach
`lib/runner/inversion_run_controller.dart`:
- New field `final int interChordCountInBeats;` (ctor param, default 2) —
  deliberately separate from `beatsPerBar` (4), which stays the session-start
  count-in length.
- New internal `int _countInTotal` set whenever a count-in begins (`start()`
  sets it to `beatsPerBar`; the new cycle-boundary trigger sets it to
  `interChordCountInBeats`), and `countInBeat` reads `_countInTotal -
  _countInRemaining` instead of hardcoding `beatsPerBar` — fixes the display
  math for a count-in whose length isn't `beatsPerBar`.
- `_advanceStep()`: when a cycle completes (`_stepIndex >= _cycle.length`)
  and `tempoMode` is true, after `_buildCycle()`/`cyclesCompleted++`, instead
  of resetting straight into `running`, reset `_held`/`_results` for the new
  cycle and drop into `_phase = InversionPhase.countingIn` with
  `_countInRemaining = _countInTotal = interChordCountInBeats`. The existing
  `onBeat()` `countingIn` branch (already used by the session-start count-in)
  ticks it down and flips back to `running` on its own — no new beat-handling
  code needed. Self-paced's rollover branch (`!tempoMode`) is unchanged.
- No changes to `lib/screens/inversion_run_screen.dart` or
  `lib/widgets/inversion_session_summary_sheet.dart` — the prompt area
  already renders `c.chordLabel` unconditionally every frame, so the next
  chord's name is correct the instant `_buildCycle()` runs, before the pause
  even starts.

## Task Breakdown
- [x] Add `interChordCountInBeats` ctor param + `_countInTotal` tracking; fix `countInBeat` getter.
- [x] Branch `_advanceStep()`'s cycle-rollover: tempo mode enters the new count-in phase, self-paced unchanged.
- [x] Unit tests: inter-chord count-in fires only in tempo mode; its length is `interChordCountInBeats` not `beatsPerBar`; `countInBeat` displays correctly during both the session-start and inter-chord count-ins; self-paced rollover is byte-for-byte unchanged (existing tests should still pass unmodified).
- [x] `flutter analyze` + `flutter test` clean (231 tests pass).
- [ ] On-device check in tempo mode: confirm the next chord's name is visible during the pause, before its first beat.

## Edge Cases & Failure Modes
- Stopping mid-inter-chord count-in: identical to stopping mid-session-start
  count-in today — `stop()` just goes idle, `onSessionEnd` still fires
  correctly (guarded the same way as before).
- Metronome-collapse-stops-the-drill listener: already treats any
  non-`idle` phase as active, so an inter-chord count-in getting interrupted
  by the metronome bar collapsing works the same as it does today mid-cycle.
- `chordScores`/tally: count-in beats were never judged before and still
  aren't — no double-counting risk.

## Success Criteria
- In tempo mode, the next chord's name is visibly on screen for a full
  2-beat pause before its first beat is judged.
- Self-paced mode behaves identically to before this change (no new pause,
  no new getters used).
- `flutter analyze` clean; all existing tests plus new ones pass.

## Open Questions / Risks
- Whether 2 beats reads comfortably at faster tempos — easy to tune via the
  single `interChordCountInBeats` constant if it feels too short/long
  on-device.
