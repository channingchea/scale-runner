# Stats Labels & Shareable Mode Scores — Implementation Plan

## Overview
Two related improvements. (1) The accuracy bars on the Stats screen show
unlabeled numbers (`76% · 1080`) — make them self-explanatory and consistently
aligned. (2) Introduce an overview score per practice mode (Scale Running, Jam,
Inversion Running) that blends lifetime accuracy with practice volume, shown on
your own Stats screen and synced so friends see it when they visit your profile
— same pattern as the existing streak / weekly-stats sync.

## Non-goals / Out of scope
- No leaderboard changes (scores appear on profiles only).
- Quiz scores stay separate — not folded into overview scores.
- No share-image/export; "shareable" means friend-visible in-app.

## Phase 1: Label + align the stat bars
- In `stats_screen.dart` `_StatBar`, change `'$pct% · $attempts'` to
  `'$pct% accuracy · $attempts plays'`.
- Right-align the value text consistently on every row across the Scale
  Running, Jam, and Inversion cards; name ellipsizes, numbers never wrap.

## Phase 2: Mode score model (local)
- Add `modeScore(attempts, correct)` and a `ModeStats` model (raw per-mode
  counts + score getters) in `social_models.dart`:
  `score = round(100 × accuracy × min(1, √(attempts / 300)))`; returns null
  under 10 attempts (rendered as "—"). Full volume credit at ~300 plays, so
  100% on 4 plays scores far below 76% on 1080.
- Add `QuizSettings.modeStats()` that sums the existing lifetime maps into one
  `(attempts, correct)` per mode (keys for Scale Running, qualities for Jam,
  chords for Inversion — one map each, no double-counting).
- New three-tile "Mode scores" row at the top of the Stats screen
  (Scale Run / Jam / Inversion), labeled, "—" for unplayed modes.
- Unit tests for the formula (0 attempts, tiny sample, large sample).

## Phase 3: Sync + profile display
- New Supabase `mode_stats` table: `user_id` PK, `run_attempts`,
  `run_correct`, `jam_attempts`, `jam_correct`, `inv_attempts`, `inv_correct`,
  `updated_at`; RLS mirrors `weekly_stats` (self insert/update, self-or-friends
  read via `are_friends`). Raw counts stored, score computed client-side.
- `SocialBackend.upsertModeStats` / `fetchModeStats` on the Supabase backend,
  mock backend (seeded), and the test fake.
- Push at practice-session end alongside the weekly-stats push, with the same
  dirty-flag / offline-queue pattern; flush on refresh.
- "Mode scores" card on `friend_profile_screen.dart`; unplayed modes show "—".
- Run `flutter analyze` + full test suite.

## Open questions / risks
- The 300-play ramp and 10-attempt minimum are tunable constants.
- Mock preview (`kMockSocialData`) must be flipped off before real builds.
