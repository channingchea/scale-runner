# Social Features (Friends, Applause, Leaderboard) — Implementation Plan

Status: **implemented (all 5 phases), 2026-07-14** — analyze/test clean (294 tests).
Remaining manual setup + on-device verification: see `docs/social-setup.md`.

Implementation notes / deviations from plan:
- `accept_invite` shipped as an atomic `security definer` SQL function
  (`accept_invite_tx`) called via RPC instead of an edge-function wrapper —
  same guarantees, one less moving part. A `delete_account` edge function
  was added instead (account deletion needs the admin API).
- Leaderboard ranks by current streak for now; the weekly-GPA ranking amendment
  activates when the Weekly Progress Report ships (W5).
- Supabase project: `scale-runner` (`mbikuewjbvxndzhdorav`, us-west-1, free tier).
- Invite redirect page: static files under `web_hosting/hostinger/`, served
  from Hostinger at `scalerunner.c1gnus.com` (AASA + assetlinks + landing
  page). The original plan called for a Cloudflare Worker; that was dropped
  because the domain's DNS is on Hostinger. `web_hosting/worker.js` remains
  as an undeployed alternative.

## Overview
Add Duolingo-style social to Scale Runner: mutual friends via invite links, one-tap applause on friends' streaks, and a friends leaderboard ranked by current streak. The app today is fully offline, so this introduces its first backend (Supabase), optional sign-in, and cloud sync of streak data — while keeping the app 100% usable without an account.

## Non-goals / Out of scope (v1)
- Push notifications (in-app activity only; push is a fast-follow)
- Weekly leagues/divisions, XP, or any global leaderboard
- Profile photos, username search, chat/DMs
- Server-side streak validation (client is trusted; friends-only visibility)
- Pro-gating of any social feature

## Phase 1: Supabase backend foundation
- Create Supabase project; enable Sign in with Apple + Google (Apple requires offering Apple sign-in if Google is offered)
- Tables: `profiles` (id → auth.users, `display_name`, `avatar_seed`, `created_at`), `friendships` (`user_a`, `user_b`, ordered pair, unique), `invites` (`code`, `inviter_id`, `expires_at`, `used_by`), `applause` (`from_id`, `to_id`, `streak_days`, `created_at`, `seen_at`), `streaks` (`user_id`, `current`, `best`, `total_days`, `updated_at`)
- Row-level security: streaks/applause readable only by friends; profiles readable by friends + valid invite lookups; all writes owner-only
- Edge function `accept_invite(code)`: validates code, creates the friendship atomically
- Verify: RLS tested with two test users via SQL (friend can read, stranger can't)

## Phase 2: App-side identity + streak sync
- New `lib/social/` module: `SocialService` singleton (`ChangeNotifier`), mirroring existing service pattern
- Add `supabase_flutter`; optional sign-in screen (Apple/Google) reachable from stats screen — app never blocks on it
- On sign-in: create profile with display name + auto-generated color/emoji avatar
- Push streak to `streaks` table from the existing `StreakService.onPracticeRecorded` hook (fire-and-forget, queued when offline)
- Sign-out and account-deletion flows (deletion is an App Store requirement)
- Verify: analyze/test clean; sign in → practice → row appears in Supabase

## Phase 3: Friends via invite links
- Small hosted redirect page on your domain (needed for Universal/App Links) + `apple-app-site-association` / `assetlinks.json`
- Configure Universal Links (iOS) and App Links (Android) in the Flutter app; route `.../invite/<code>` → accept-friend screen
- "Invite a friend" button generates an invite row + share sheet message (extends the existing `share_plus` streak-share flow)
- Accept screen: shows inviter's name/streak, one tap → mutual friendship via edge function
- Friends list screen with remove-friend option
- Verify: on-device — device A shares link, device B taps it, both see each other

## Phase 4: Applause + activity
- Tap a friend's streak → insert `applause` row (rate-limited: one per friend per day)
- Activity list (applause received, friends joined) with unread badge on the social tab; `seen_at` marks read
- Fetch activity + friends' streaks on app open / pull-to-refresh
- Verify: on-device between two accounts

## Phase 5: Leaderboard + polish
- Friends leaderboard: you + friends ranked by current streak, applaud directly from a row
  - **Amended 2026-07-14:** once the Weekly Progress Report ships (see plan below), the leaderboard ranks by weekly GPA (tie-break: graded-mode count) and resets weekly; streak stays visible on profiles
- Empty states (no friends yet → invite CTA), loading/error states, offline behavior pass
- Final verification: `flutter analyze` + full test suite; two-device end-to-end run of invite → applause → leaderboard

## Open questions / risks
- **Domain**: Universal Links need a domain you control for the redirect page — which domain (c1gnus.com?)
- **`appShareUrl` placeholders**: store URLs must be real before invite links are useful to non-installed users
- **Display names are user-generated content**: v1 ships with just a length/character filter; a report mechanism may be needed for App Store review

# Weekly Progress Report & Grading System — Implementation Plan

Status: planned, not started (2026-07-14). Phases W1–W4 are standalone (local-only); Phase W5 depends on Social Phases 1–3 above.

## Overview
Replace daily-streak emphasis with a weekly report card: A–F grades per practice mode (all five: Scales quiz, Chords quiz, Scale Running, Inversion Running, Jam Mode), a volume-weighted overall GPA, and expandable granular detail (modes, chord families, keys). Grades update live during the week, finalize Sunday night into a locally stored, offline-viewable history, and are shareable both as an image card and to friends via the social system. Lives in a new Progress tab (bottom nav), which also hosts the social/Friends pages.

## Non-goals / Out of scope
- Backfilling history from existing lifetime stats (no timestamps exist — history starts at feature launch)
- Server-side grade validation (client-computed, consistent with social plan's trust model)
- Push notifications ("report ready" uses the existing local NotificationService)
- Monthly/yearly rollups

## Phase W1: Per-week data capture
- Add `attempts`/`correct` tracking to `QuizController` for Scales/Chords (today it only tracks score/best-streak — no accuracy exists to grade)
- New `lib/progress/` module: `WeeklyProgressService` singleton (`ChangeNotifier`), mirroring existing service pattern
- `WeekRecord` model: ISO week id (Monday start, local time — matches the streak-freeze ISO-week convention), per-mode `{attempts, correct}`, plus granular bucket maps reusing the exact keys already tallied (mode names, keys, jam quality/degree, inversion chord types)
- Persist as JSON via SharedPreferences (consistent with `QuizSettings` convention): `week_current` + `week_history` list, unlimited retention
- Hook the four session-end sites (`quiz_screen`, `scale_run_screen`, `jam_mode_screen`, `inversion_run_screen`) to also feed `WeeklyProgressService.recordSession(...)`
- Rollover: on app open and session end, if stored week id ≠ current week id, finalize old week into history and start fresh; zero-practice weeks are simply absent from history (no F-week entries)
- Verify: unit tests for rollover (incl. multi-week gaps and timezone change), bucket accumulation

## Phase W2: Grading engine
- `Grade` mapper: accuracy → A/B/C/D/F (draft thresholds ≥95/85/75/65/<65, modeled on the existing `runTierFor` bands; constants in one place for tuning)
- Minimum-attempts gate per mode: **7 attempts**; below it the mode shows "X attempts to unlock grade" instead of a letter (kills the one-perfect-run-equals-A exploit while staying motivating)
- Weekly GPA: volume-weighted average of graded modes only (ungraded modes excluded)
- Verify: unit tests for thresholds, gate edges, GPA weighting, all-ungraded weeks

## Phase W3: Progress tab + bottom navigation
- Refactor: new root scaffold with `NavigationBar` — **Practice** (current Home), **Progress**, and **Settings** tabs; do the nav refactor as its own commit early in the phase
- Progress > **My Report**: current week live card (per-mode grades, GPA, days-practiced dots), expandable detail sheet per mode (modes run, chord families, keys, weakest bucket — reusing `_AccuracyBarList` patterns from Stats)
- History: scrollable past-week list, tap to open any week's full report (all offline)
- Absorb lifetime Stats as an "All-time" section within Progress; retire the separate stats route; Settings tab absorbs the current settings route
- Pro-gated runner modes appear as locked slots in free users' reports with an "unlock to complete your report" upsell into the existing paywall
- Verify: `flutter analyze` + tests; manual pass on all tabs, free vs Pro states

## Phase W4: Sharing
- Share-as-image: render report card widget via `RepaintBoundary` → PNG → existing `share_plus` flow (works signed-out)
- "Report ready" local notification Monday morning via existing `NotificationService` (respects its permission/settings pattern)
- Verify: shared image renders correctly on both platforms

## Phase W5: Social sync (depends on Social Phases 1–3)
- Supabase `weekly_reports` table (`user_id`, `week_id`, per-mode grades JSON, `gpa`, `finalized_at`); RLS friends-only read
- Sync current week live (same fire-and-forget queue as streak sync) + finalize at rollover
- Progress > **Friends** sub-tab: friends' current reports, applaud a report, activity feed
- Leaderboard ranks by weekly GPA (tie-break: graded-mode count), resetting weekly — replaces current-streak ranking; streak stays visible on profiles
- Verify: two-device end-to-end — practice → friend sees live grade → applaud → Monday reset

## Open questions / risks (weekly report)
- Grade thresholds are draft values — tune after real use
- The bottom-nav refactor touches Home's scaffold — keep it an isolated, reviewable commit
- Later (cheap in W5): restore local history from Supabase on a new device for signed-in users
