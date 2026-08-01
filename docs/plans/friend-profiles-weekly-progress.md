# Friend Profiles & Weekly Progress — Implementation Plan

## Overview
Tapping a friend anywhere in the Friends UI opens a profile screen showing their streak plus weekly progress — days practiced this week, sessions, and accuracy — with a short trend across recent weeks. The app currently stores only lifetime running totals (nothing time-windowed), so this adds week-bucketed tracking that syncs to Supabase so friends can see each other's weeks. Also adds a picker so people can choose their own avatar instead of the random one.

## Key decisions
- Metrics: days practiced this week (0–7), sessions this week, accuracy this week (% correct), plus existing streak stats.
- History: one aggregate row per user per ISO week, keep ~12 weeks → small trend sparkline. Not a full session log.
- What counts: Scale Running, Jam, Inversion only. Quizzes excluded.
- Privacy: weekly numbers visible to friends automatically, same as streaks.

## Non-goals / out of scope
- Quizzes in the weekly numbers.
- Full per-session history or charts beyond the ~12-week trend.
- Multi-device same-week merging (client owns its current week; last-write-wins).
- Avatar photo uploads (stays emoji+color).
- A weekly-reset leaderboard (see open questions).

## Phase 1: Weekly tracking — data model + sync
- DB: weekly_stats table (user_id, iso_week, week_start, days_mask 7-bit, sessions, attempts, correct, updated_at; PK user_id+iso_week). RLS mirrors streaks (self write; self-or-friends read).
- Local mirror in QuizSettings (current-week aggregate + dirty flag); resets on ISO-week rollover.
- Recording hook at end of Scale Running / Jam / Inversion sessions (set weekday bit, +1 session, +attempts, +correct) via SocialService.recordWeeklySession; push current-week row; queue + flush when offline.
- SocialBackend: upsertWeeklyStats + fetchWeeklyStats across Supabase / Mock / test Fake.
- Verify: analyze + unit tests (day-bit idempotency, accuracy math, week rollover, offline flush).

## Phase 2: Friend profile detail screen
- Models: WeeklyStat, FriendProfileDetail.
- SocialService.loadFriendProfile(friendId): streak row + last ~12 weekly rows.
- friend_profile_screen: avatar+name header, streak row (current/best/total), "This week" card (days X/7, sessions, accuracy %), days-per-week trend sparkline, applaud button, friends-since, remove-friend.
- Entry points: tappable leaderboard rows + manage-friends rows.
- Seed MockSocialBackend with weekly data for preview.
- Verify: analyze + service test.

## Phase 3: Avatar picker
- Picker sheet (16 emoji × 8 colors), current choice highlighted.
- Tappable avatar/edit control on own profile card → upsertProfile(name, newSeed) → refresh.
- Verify: analyze + test.

## Open questions / risks
- Weekly leaderboard: recommend keeping the all-time streak leaderboard for v1; weekly numbers live on the profile. Add later as its own phase if wanted.
- "Days practiced this week" (practice-modes-only) can differ slightly from the streak's day count (which includes quizzes) — consistent by definition.
- Old-week rows are bounded (~52/user/yr); read last 12, prune later if needed.
