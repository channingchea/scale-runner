# Phase 5 — Features — Implementation Plan

## Overview
Three features from IMPROVEMENT_PLAN.md's Phase 5, built one checkpoint at a
time with on-device verification between each: a lifetime stats screen, quiz
key selection, and paywall trial sessions. A prerequisite checkpoint adds
session tracking to Inversion Running, which currently has none, so all three
Pro modes behave consistently for the stats screen and the trial gate.

## Goals & Non-Goals
In scope: Inversion Running session-end hook + per-chord-type lifetime stats;
a stats screen covering Scale Running, Jam, Inversion Running, and Quiz; root
pitch-class filtering for the Scale/Chord quiz modes; a 1-free-session trial
per Pro mode with an auto-shown paywall on trial completion.
Out of scope (explicitly deferred): Phase 5.4 accessibility pass, Phase 4
performance hardening, dated session-history/time-series stats (v1 ships
aggregates only), per-root-pc tracking for Inversion Running (chord-type only).


## User Flow / UX

**Inversion Running tracking (invisible plumbing + 1 new sheet).** Playing a
session and hitting Stop (or backing out) now shows a summary sheet — accuracy,
best streak, weakest chord type — same shape as Scale Run/Jam's. No visible
change otherwise.

**Stats screen.** Tap a new bar-chart icon in the home header (next to
Settings/Help). Four sections, each sorted by accuracy ascending: Scale Running
(per-key + per-mode bars), Jam (per-quality + per-degree bars), Inversion
Running (per-chord-type bars), Quiz (score + best streak per Scale/Chord mode).
Bars with fewer than 5 attempts show their accuracy but aren't eligible to be
flagged "weakest" or sorted to the very top. Sections with no data yet show a
placeholder line instead of an empty/zero bar.

**Quiz key selection.** In the Practice tab of the quiz settings sheet, a new
"Keys" group above the existing scale/chord toggles: 12 chips (C, C#, D...) per
mode, with All/None buttons, at least one always enabled. Rounds only draw
their random root from the enabled set.

**Paywall trial sessions.** Tapping a locked Pro mode card for the first time
opens it directly with a "1 free session" toast instead of the paywall. If
that trial session reaches its summary sheet, the trial is marked used and the
paywall auto-opens right after the summary closes ("Enjoyed it? Unlock…").
Backing out before finishing preserves the trial. Once used (or once Pro is
owned), the normal paywall-first flow applies.


## Technical Approach

**Checkpoint 1 — Inversion Running tracking.**
`lib/runner/inversion_run_controller.dart`: add `void Function()? onSessionEnd`,
fire it from `stop()` when `stepsCompleted > 0 || cyclesCompleted > 0`; add a
`Map<String,(int,int)> chordSnapshot` getter keyed by chord name (Major, Minor,
Major 7th, Minor 7th) built from a new internal per-chord attempts/correct
tally updated in `_advanceCorrect()`/`_settleAndAdvance()`/`_judgePress()`
(wrong presses count as an attempt against the current chord, same as
Scale Running's mode tally).
`lib/quiz/quiz_settings.dart`: new `_invChordStatsKey`, `invChordStats()`,
`mergeInversionStats(Map<String,(int,int)>)`, `resetInversionStats()` —
identical shape to `runModeStats`/`mergeRunStats`, reusing `_encodeStats`/
`_decodeStats`/`_mergeStats`.
New `lib/widgets/inversion_session_summary_sheet.dart`: `InversionSessionStats`
(accuracy, bestStreak, tier reused from existing tier logic if applicable,
weakestChord) + `InversionSessionSummarySheet`, modeled directly on
`scale_run_session_summary_sheet.dart`.
`lib/screens/inversion_run_screen.dart`: wire `next.onSessionEnd = () =>
_endSession(next)` and an `_endSession` method mirroring `ScaleRunScreen`'s
(snapshot stats, merge into settings, show sheet, guarded by `_endingSession`).

**Checkpoint 2 — Stats screen.**
New `lib/screens/stats_screen.dart`, reading `QuizSettings.runKeyStats()`,
`runModeStats()`, `jamQualityStats()`, `jamDegreeStats()`, `invChordStats()`
(new), `quizScore()`/`quizBestStreak()` for both `QuizMode`s. A shared
`_AccuracyBarList` widget takes a `Map<String,(int,int)>`, computes accuracy,
sorts ascending, and renders bars with a "weakest" badge gated on `attempts >=
5`. Entry point wired in `home_screen.dart`'s `_buildHeader` next to the
existing Settings/Help `IconButton`s.


**Checkpoint 3 — Quiz key selection.**
`lib/quiz/quiz_settings.dart`: new `_enabledKeysKeyFor(mode)`,
`enabledRootPcs(QuizMode)` (default: all 0-11, matching the `enabledNames`
absent-means-all convention), `setEnabledRootPcs(QuizMode, Set<int>)`.
`lib/quiz/quiz_controller.dart`: `QuizController` gains an `enabledRootPcs`
ctor param (default all 12, so existing tests are unaffected); `_nextRound`
picks `_rootMidi` from that set instead of `_rng.nextInt(12)`.
`lib/widgets/quiz_settings_sheet.dart`: new chip row above `_practiceTab`'s
scale/chord list, using `pitchClassNames` for labels, same All/None +
"keep at least one" pattern as `_toggle`/`_setAll`.

**Checkpoint 4 — Paywall trial sessions.**
New `lib/purchases/trial_gate.dart` (or methods added to `purchase_service.dart`
— will decide during implementation based on which reads cleaner): per-mode
`trialUsed(String mode)` / `markTrialUsed(String mode)` backed by
`QuizSettings` (`trial_used_<mode>` bool keys, e.g. `trial_used_scale_run`).
`lib/screens/home_screen.dart`'s `_open*Gated` methods: `isPro` → open;
`!trialUsed` → open + toast, no paywall; else → `PaywallSheet.show`. Each of
the three screens' `_endSession`/summary-close callers checks "was this a
trial session" (Pro not owned + trial not yet marked used) and, if so, marks
the trial used and calls `PaywallSheet.show` immediately after the summary
sheet's `Navigator.pop` resolves.

## Task Breakdown
- [x] Checkpoint 1: Inversion Running `onSessionEnd` + chord-tally + summary sheet + QuizSettings persistence + screen wiring; `flutter analyze` + `flutter test` clean (227 tests); on-device check CONFIRMED 2026-07-05.
- [x] Checkpoint 2: `stats_screen.dart` + home header entry icon; `flutter analyze` + `flutter test` clean (234 tests); on-device check still pending.
- [x] Checkpoint 3: key-selection persistence + controller filtering + settings-sheet chips; `flutter analyze` + `flutter test` clean (236 tests, +2 new); on-device check still pending.
- [x] Checkpoint 4: trial-gate persistence + home-screen gating + summary-close paywall hook across all 3 Pro modes; `flutter analyze` + `flutter test` clean (236 tests); on-device check still pending (needs a release/TestFlight build or a temporary `_devUnlockAll` flip — see below).

**All 4 checkpoints are code-complete as of 2026-07-05.** Remaining before
Phase 5 can be closed out: on-device verification of checkpoints 2-4, and
real RevenueCat API keys in `PurchaseService` (`PAYWALL_SETUP.md`) so the
trial/paywall flow in checkpoint 4 can actually be exercised — right now
`PurchaseService._devUnlockAll` (tied to `kDebugMode`) makes every debug
build report Pro, which bypasses the whole gate.


## Edge Cases & Failure Modes
- Turning off all 12 key chips: blocked, same "keep at least one" toast used
  elsewhere.
- Stats screen with zero data anywhere (fresh install): every section shows a
  placeholder, no divide-by-zero on accuracy.
- Trial session interrupted by app kill/crash mid-session: since trial is only
  marked used on reaching the summary sheet, a crash preserves the trial —
  acceptable (errs generous, matches "on completion" decision).
- Summary sheet shown twice / session-end fired twice: guarded by the existing
  `_endingSession` pattern (already used in Scale Run/Jam), reused for
  Inversion Running and for the trial-marking logic.
- User already owns Pro: trial-gate code path is skipped entirely, no behavior
  change from today.

## Success Criteria
- `flutter analyze` and `flutter test` clean after every checkpoint.
- Checkpoint 1: finishing an Inversion Running session shows a summary sheet
  with correct accuracy/streak/weakest-chord; stats persist across app
  restarts.
- Checkpoint 2: stats screen shows real lifetime numbers for all 4 sections
  matching what's independently visible in each mode's own summary sheets.
- Checkpoint 3: disabling a key chip stops that root from ever appearing in
  quiz rounds; re-enabling brings it back.
- Checkpoint 4: first visit to each Pro mode opens free with a toast; second
  visit (after the first trial session completes) shows the paywall; paywall
  auto-opens right after the first trial's summary closes.

## Open Questions / Risks
- Exact wording/placement of the "1 free session" toast and the post-trial
  paywall prompt copy — will draft something in the Scale Runner voice during
  Checkpoint 4 and can adjust.
- `RunTier`/`JamTier`-style tier label for Inversion Running's new summary
  sheet: will reuse the existing tier enum if it generalizes cleanly, otherwise
  ship without a tier label for v1 (accuracy/streak/weakest are the essentials).
