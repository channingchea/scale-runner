# Practice Streaks & Notifications — Implementation Plan

## Overview
Add a daily practice streak (kept alive by completing any quiz or drill session) plus local notifications to bring users back: a daily reminder at a user-chosen time, a streak-at-risk evening nudge, and a win-back notification after inactivity. Streaks tie into conversion via a Pro-only auto streak-freeze and a "Pro would have saved your streak" recovery moment. Milestone celebrations include a share option that spreads the app to friends. Local-only notifications — no backend, fits the existing SharedPreferences/ChangeNotifier architecture.

## Non-goals / Out of scope
- Push notifications / Firebase (code structured so it could slot in later)
- Practice-day calendar view (only counters + minimal day history in v1)
- macOS/Windows notifications
- Analytics/event tracking

## Phase 1: Streak engine (data + logic)
- Add `lib/streak/streak_service.dart`: `StreakService` singleton (`ChangeNotifier`, matching `PurchaseService` pattern) with `currentStreak`, `bestStreak`, `totalPracticeDays`, `lastPracticedDate`, `recordPractice()`, `evaluateOnAppOpen()`.
- Storage in `QuizSettings` (new keys): `daily_streak_current`, `daily_streak_best`, `daily_streak_last_date` (yyyy-MM-dd, local time), `daily_streak_total_days`, `daily_streak_freeze_used_week` (ISO week string), plus a small rolling list of recent practiced days for freeze/risk logic. Named `daily_*` to avoid collision with the existing in-session `streak` concept.
- Day rule: local calendar day, midnight boundary. Gap of exactly 1 day + Pro + freeze unused this week → auto-repair (mark freeze used, streak continues). Gap ≥ 1 day otherwise → streak resets (previous value kept for the recovery screen).
- Hook `StreakService.recordPractice()` into the four session-end points: `quiz_screen.dart`, `scale_run_screen.dart`, `inversion_run_screen.dart`, `jam_mode_screen.dart` (same spots that call `setQuizStats`/`merge*Stats`).
- Milestone detection in `recordPractice()`: fires at 3, 7, 14, 30, 100; returns an event the UI layer reacts to.
- Unit tests for streak transitions: consecutive days, missed day, freeze repair, freeze already used, tz-change leniency (never break a streak from clock changes alone), milestone triggers. Use the existing `clock` package for testable time.

## Phase 2: Streak UI + milestone sharing
- Home screen: streak badge (flame + count) near the title in `home_screen.dart`; dimmed state when today's practice isn't done yet.
- Stats screen: "Practice streak" section (current, best, total days) at top of `stats_screen.dart`.
- Milestone celebration bottom sheet (`lib/widgets/streak_milestone_sheet.dart`), shown after the session summary sheet when a milestone fired.
- Share button on the milestone sheet: add `share_plus` to pubspec; opens the native share sheet with a message like "🔥 I've practiced piano N days in a row with Scale Runner! Join me: <app link>". Link comes from a single `appShareUrl` constant (platform-aware: App Store link on iOS, Play Store link on Android) so it's one-line to update at launch.
- Streak-saved moment for Pro freeze ("Streak saved — Pro freeze used") shown on app open.
- Streak-lost recovery sheet for free users on app open after a break: shows lost streak + "Pro protects your streak with a weekly freeze" → `PaywallSheet.show()`. This is the main conversion surface.

## Phase 3: Notification infrastructure
- Add `flutter_local_notifications` + `timezone` to pubspec.
- Android: `POST_NOTIFICATIONS` + `SCHEDULE_EXACT_ALARM` (fallback to inexact) permissions, boot-completed receiver in manifest so schedules survive reboot.
- iOS: permission request wiring in `AppDelegate`/plugin init (no Info.plist background modes needed for local notifications).
- Add `lib/notifications/notification_service.dart`: init, permission request, and three schedules:
  - Daily reminder (id 1) at the user-chosen time; cancelled for today once practice is recorded.
  - Streak-at-risk nudge (id 2, ~8:30pm), only scheduled when a streak ≥2 exists and today isn't practiced yet.
  - Win-back (id 3): scheduled 4 days out after every recorded practice; each new practice cancels and reschedules it, so it only ever fires after 4 days of inactivity. Copy: friendly, practice-focused (e.g. "Your scales miss you — pick up where you left off").
- `cancelToday()` called from `recordPractice()`; `rescheduleAll()` called on app start (local notifications can't check conditions at fire time, so state is re-evaluated on every launch).
- Reminder copy: practice/streak focused, no Pro promos (soft paywall tie-in).

## Phase 4: Permission flow + settings
- Post-first-session prompt (once ever, tracked via a `QuizSettings` flag): after the first completed session's summary sheet → "Keep your streak going — daily reminder?" sheet with a required time picker (default 6:00 PM shown, user confirms/adjusts) → OS permission dialog → schedule.
- Settings screen additions: "Practice reminders" toggle + reminder time picker row (opens the same picker). Toggle off cancels all scheduled notifications (daily, streak-at-risk, and win-back all ride this toggle).
- Handle permission-denied gracefully: toggle shows off state with a hint to enable in system settings.

## Phase 5: Verification
- `flutter analyze` + full test suite.
- On-device (per project practice — timing/scheduled behavior can't be verified in tests): permission flow on iOS and Android 13+, daily reminder fires at chosen time, reminder cancelled after practicing, streak-at-risk fires only when applicable, win-back fires after inactivity window and is cancelled by new practice, share sheet opens with correct message/link on both platforms, schedules survive device reboot (Android), streak transitions across a real midnight.

## Open questions / risks
- App store links don't exist yet (app unpublished); `appShareUrl` ships as a placeholder constant to be filled at launch. Until then the share message can link to a landing page if one exists.
- `SCHEDULE_EXACT_ALARM` on Android 14+ needs user grant; plan falls back to inexact alarms (may fire minutes late — acceptable for reminders).
- Freeze week = ISO calendar week (Mon–Sun); one repair per week regardless of streak length.
- RevenueCat keys are still placeholders, so the freeze/recovery conversion loop is only fully testable once keys are configured (debug builds bypass via `_devUnlockAll`).
- Win-back window fixed at 4 days for v1; could become configurable or multi-step (day 4, day 10) later.
