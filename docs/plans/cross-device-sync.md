# Cross-Device Sync — Implementation Plan

## Overview
Scale Runner keeps everything in SharedPreferences on the device. Users who sign in (Apple / Google / email, already built for Friends) get their voicings library, practice configuration, and progress stats mirrored to Supabase and pulled down on any other signed-in device. The device stays the source of truth: saving never waits on the network, the app works fully offline, and signing out or deleting the account never touches local data. One sync engine replaces the three ad-hoc push paths SocialService has today (streak, weekly stats, mode stats).

Merge rules, decided: per-record **newest edit wins** for voicings and settings; **per-device buckets summed on read** for counters; a **position** field carries list order across devices.

## Non-goals / Out of scope
- Realtime push while both devices are open (pull happens on launch, foreground, sign-in, and after local writes).
- Syncing device-local preferences: instrument, left-handed, sounds, haptics, metronome BPM/meter, reminder time, onboarding/guide flags, MIDI settings, expanded-folder UI state.
- Conflict UI ("keep both"). Newest wins silently.
- Any change to the Friends product surface; friends still read the same `streaks`, `weekly_stats`, `mode_stats` tables.
- Server-side merging (no edge functions); the client does all merging.

## Phase 0: Make local data sync-ready (no behavior change, shippable)
- [x] Add a stable per-install `device_id` (random 128-bit hex via `Random.secure()`, prefs key `sync_device_id`, generated on first read).
- [x] `VoicingSpec` and `VoicingLabel`: add `updatedAt` (DateTime) and `position` (double). `encode`/`decode` round-trip them; decode defaults `updatedAt = createdAt` and `position` = index in the stored list so existing libraries migrate on first load.
- [x] Tombstones: prefs list `voicing_deleted` of `{id, kind, deletedAt}` written by voicing / folder / tag delete. Pruned once the delete has been pushed (Phase 2).
- [x] `upsertVoicing`, `reorderVoicings`, folder/tag upsert & rename stamp `updatedAt = now` and assign `position` (midpoint between neighbours; renumber 0..n only when a gap collapses below 1e-6).
- [x] Tests: existing voicings tests pass; old-format line decodes with sane defaults; reorder keeps positions monotonic.

## Phase 1: Supabase schema and security
Single migration `supabase/migrations/<ts>_sync_v1.sql` kept in the repo.
- [x] `library_items` — `user_id uuid references auth.users on delete cascade`, `id text`, `kind text check (kind in ('voicing','folder','tag'))`, `data jsonb`, `position double precision`, `updated_at timestamptz`, `deleted boolean default false`; PK `(user_id, id)`; index `(user_id, updated_at)`; check `length(data::text) < 4096`.
- [x] `user_settings` — `user_id`, `key text`, `value text`, `updated_at`; PK `(user_id, key)`.
- [x] `device_stats` — `user_id`, `device_id text`, `key text`, `data jsonb`, `updated_at`; PK `(user_id, device_id, key)`.
- [x] RLS on all three: `using (auth.uid() = user_id) with check (auth.uid() = user_id)` for select/insert/update/delete. Owner-only; no friend read.
- [x] Clock-clamp trigger: `before insert or update` on all three tables sets `updated_at = least(updated_at, now() + interval '5 minutes')` so a wrong device clock can't win conflicts forever.
- [x] Confirm delete-account cascades (FK `on delete cascade` from `auth.users`); SQL check with two test users that A cannot read or write B's rows.
- [x] Migration header notes: app ships only the publishable key; service role never in the app.

## Phase 2: Sync engine + voicings library
- [x] `lib/sync/sync_backend.dart` interface: `pullLibrary(since)`, `pushLibrary(items)`, `pullSettings(since)`, `pushSettings(entries)`, `pullStats()`, `pushStats(deviceId, key, data)`.
- [x] `lib/sync/supabase_sync_backend.dart` (real) and `lib/sync/mock_sync_backend.dart` (in-memory "server" so tests can simulate two devices).
- [x] `lib/sync/sync_service.dart` singleton `ChangeNotifier`:
  - `markDirty(kind, id)` appends to prefs set `sync_pending`; called from every QuizSettings write that touches synced data.
  - `sync()` = push pending → pull since `sync_last_pull_at` → merge → save → notify. One in-flight at a time; a second request sets a "run again" flag.
  - Library merge: remote `updated_at` > local → take remote; remote `deleted` removes local; local tombstones push as `deleted = true`. Ties go to remote.
  - Triggers: launch (after `SocialService.init`), `AppLifecycleState.resumed`, sign-in success, 2 s debounce after any `markDirty`.
  - Failures: swallow, keep pending, backoff 5 s → 30 s → 2 min → stop until next trigger. Exposes `lastSyncedAt` and `state` (`idle | syncing | waiting`).
  - No-op when signed out.
- [x] First sign-in = pull everything, union with local under the same rule.
- [x] Voicings screen rebuilds on `SyncService` notify (sync writes into the same prefs).
- [x] `test/sync_service_test.dart` with the mock backend: create on A → on B; edit both offline, newer wins; delete on A doesn't resurrect from B; reorder on A shows on B; offline push retries; signed-out no-op.

## Phase 3: Practice configuration
- [x] `lib/sync/synced_settings.dart` allow-list: `enabled_scales`, `enabled_chords`, `enabled_keys_scales`, `enabled_keys_chords`, `jam_families`, `jam_key`, `jam_any_tones`, `jam_freestyle`, `jam_session_bars`, `inv_chords`, `inv_tempo`, `run_chords`, `run_progression`, `run_sevenths`, `run_start_key`, `run_reps`, `run_increment`, `voicing_start_key`, `voicing_increment`, `timing_difficulty`, `arpeggiated_notes`.
- [x] Each key gets `<key>_updated_at` locally; setters stamp it and `markDirty('setting', key)`.
- [x] Engine pushes dirty keys as `user_settings` rows; pull applies rows newer than local.
- [x] Test: `jam_key` on A, `run_reps` on B, both sync, both end with both.

## Phase 4: Stats buckets, and retiring the old push paths
- [x] Local stats unchanged (this device's counters). Engine pushes them as this device's bucket: `run_key_stats`, `run_mode_stats`, `inv_chord_stats`, `jam_degree_stats`, `jam_quality_stats`, `quiz_score:<mode>`, `best_streak:<mode>`, `weekly:<isoWeek>`, `daily_streak`.
- [x] `QuizSettings.mergedStats()`: own counters + other devices' buckets (cached in prefs `sync_remote_stats` after each pull), summed per key; scores / best streaks use max. Stats screens and mode-score labels read from it.
- [x] Daily streak: `current` = newest, `best` = max, `totalDays` = max (documented approximation).
- [x] After each pull, write summed totals into existing `mode_stats`, `weekly_stats`, `streaks` rows via the existing backend so Friends screens change nothing.
- [x] Remove from SocialService: `syncStreak`, `_flushPendingStreak`, `_pushWeekly`, `_flushWeekly`, mode-stats push, and `social_*_dirty` / `social_pending_streak` keys (one-time flush of anything pending on upgrade). `recordWeeklySession` stays local + `markDirty`.
- [x] Reset buttons reset this device's bucket only; label "Reset this device's stats".
- [x] Tests: two buckets sum; reset on A doesn't zero B; friend-facing `mode_stats` equals the sum.

## Phase 5: Account UI, Pro link, and disclosures
- [x] Settings → **Account** section: signed out → "Sign in to back up and sync" (existing sign-in sheet); signed in → display name, "Last synced …" / "Waiting for connection" / "Syncing…", **Sync now**, **Sign out**. Delete account stays on Friends, copy mentions synced data.
- [x] Sign out clears `sync_pending`, `sync_last_pull_at`, `sync_remote_stats`; local data untouched.
- [x] Pro follows account: `Purchases.logIn(userId)` after sign-in, `Purchases.logOut()` on sign-out, guarded by `PurchaseService.isConfigured`.
- [x] Privacy text: add "Your saved voicings, practice settings, and practice statistics" to the account bullets; keep "Without an account, nothing ever leaves your device."
- [ ] App Store Connect privacy labels + Google Play Data safety: add User Content (linked, not tracking).
- [x] One-time toast after first successful sign-in sync: "Your library is backed up."

## Phase 6: Verification and release
- [ ] Hardware matrix (iPhone + Mac/iPad): create/edit/delete/reorder both directions; airplane-mode edits on both then reconnect; reinstall + sign in; delete account then reinstall.
- [x] Full test suite green; no `dart format` on existing files.
- [x] Update `docs/plans/social-features.md` to point at the new engine for streak/weekly/mode stats.
- [x] Log milestone in project memory.

## Status (2026-09-11)
Phases 0-5 BUILT: 711 tests + `flutter analyze` clean, migration `sync_v1` applied to the
`scale-runner` Supabase project and RLS verified with two users. UNCOMMITTED.
Left for Channing: hardware QA matrix below, App Store Connect / Play data-safety labels.

Deviations from the draft, all deliberate:
- Pulls are full, not `since`-based. The library is a few KB, and a watermark on device
  timestamps would miss rows pushed late from an offline device.
- Quiz score is now written by `recordQuizWin` (+1) instead of an absolute `setQuizStats`,
  so it can be summed across devices like the other counters; best streak is a max.
- The daily streak isn't approximated: `StreakService.adoptSynced` takes the streak of
  whichever device practiced most recently, so both devices show the same number and the
  next session extends it from there. A streak that already lapsed elsewhere arrives as 0
  without a "streak lost" sheet.
- Sign-in still lives on the Friends screen; the Settings Account row leads there.
- The friends-facing `weekly_stats` row is refreshed for the current week only.

## Open questions / risks
- Daily streak convergence assumes a sync happens between the two devices' sessions; two devices practicing on alternating days while offline will disagree until one syncs, then the most recent wins.
- A `library_items.data` row is capped at 4 KB. A pathological voicing name could make a push fail every time; a client-side name cap would close that.
- Friends' `mode_stats` semantics change from "this device" to "all devices" — intended; check weekly-report grading still reads sensibly.
- Reinstall creates a new device id; the old bucket lingers (harmless, still counted). A "Devices" list could prune later.
- Delete-account lives only on the Friends screen; add a Settings link if support questions appear.
