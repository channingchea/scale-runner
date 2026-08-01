# Phase 3 UX Fixes — Implementation Plan

## Overview
Four small, independent UX fixes from the 2026-07-04 audit (see
`IMPROVEMENT_PLAN.md` Phase 3): screens can sleep mid-drill, the home
header's info button opens an About page instead of real settings, the
on-screen keyboard is cramped in portrait, and the metronome's haptic tick
can't be turned off.

## Goals & Non-Goals
In scope: wakelock on all 4 practice screens, a real Settings screen
(version, note-sound toggle, timing difficulty, haptic-tick toggle, Restore
Purchases, Privacy Policy sub-page), removal of the now-duplicated
note-sound/timing-difficulty controls from the 4 per-mode settings sheets,
and a dismissible portrait rotate-hint banner on all 4 practice screens.

Out of scope: a global "reset all stats" button (per-mode reset stays where
it is), forcing landscape, a redesigned portrait keyboard layout.

## User Flow / UX
- Practice screens (Quiz, Scale Running, Inversion Running, Jam Mode): screen
  stays awake for the whole session; in portrait, a small dismissible banner
  reads "Rotate for bigger keys" until dismissed once (then never again,
  persisted).
- Home header info button becomes a gear-style "Settings" entry: version,
  Sound (note-sound + haptic-tick toggles), Timing (easy/normal/strict
  selector), Restore Purchases, and a "Privacy Policy" row pushing the
  existing policy text as a sub-page.
- Per-mode settings sheets (Quiz/Scale Running/Inversion Running/Jam) drop
  their note-sound and timing-difficulty rows; everything else (hints, dots,
  stats bar, per-mode reset) is unchanged.

## Technical Approach
- **Wakelock:** add `wakelock_plus`; each of the 4 practice screens calls
  `WakelockPlus.enable()` in `initState` and `WakelockPlus.disable()` in
  `dispose`. Screens never nest, so this is safe without phase-tracking.
- **Settings screen:** add `package_info_plus` for the version string.
  Rebuild `lib/screens/settings_screen.dart` with the controls above; move
  the current privacy-policy body into a `_PrivacyPolicyScreen` pushed from a
  list row. `home_screen.dart`'s existing info IconButton is retargeted
  (icon → `Icons.settings_outlined`, tooltip → "Settings").
- **Haptic toggle:** `QuizSettings.tickHapticEnabled()` /
  `setTickHapticEnabled()` (bool, default true). `MetronomeController` gets a
  `hapticEnabled` field (default true) checked in `_tickNow` before calling
  `HapticFeedback.lightImpact()`. Each practice screen reads the stored value
  when constructing its `MetronomeController`.
- **Sheet consolidation:** remove the note-sound `SwitchListTile` and
  `TimingDifficultySelector` block plus their backing state/params from each
  of the 4 settings sheets; the 4 screens stop wiring
  `onNoteSoundChanged`/timing-difficulty callbacks through those sheets and
  instead read `QuizSettings.noteSoundEnabled()` /
  `QuizSettings.timingDifficulty()` directly at screen open (same as today,
  just no longer editable from the sheet).
- **Rotate-hint banner:** new small stateless-ish widget
  (`lib/widgets/rotate_hint_banner.dart`) shown when
  `MediaQuery.orientationOf(context) == Orientation.portrait`; dismiss writes
  `QuizSettings`'s new `rotateHintDismissed()` / `setRotateHintDismissed()`
  (SharedPreferences bool, same pattern as `introSeen`).

## Task Breakdown
- [ ] `flutter pub add wakelock_plus package_info_plus`
- [ ] Wire wakelock enable/disable into the 4 practice screens
- [ ] `QuizSettings`: add `tickHapticEnabled`/`setTickHapticEnabled`,
      `rotateHintDismissed`/`setRotateHintDismissed`
- [ ] `MetronomeController`: add `hapticEnabled` field, gate the haptic call
- [ ] New `RotateHintBanner` widget; add to the 4 practice screens
- [ ] Rebuild `SettingsScreen` (version, sound section, timing section,
      restore purchases, privacy sub-page); update `home_screen.dart` icon
- [ ] Strip note-sound + timing-difficulty UI/state from the 4 settings
      sheets and their call sites in the 4 screens
- [ ] `flutter analyze` + `flutter test`, fix until clean
- [ ] On-device sanity check (wakelock holds, settings persist, banner
      dismisses, haptic toggle silences the tick)

## Edge Cases & Failure Modes
- `package_info_plus` failing to read version (unlikely, but fall back to
  showing nothing rather than crashing the screen).
- Restore Purchases with no prior purchase: reuse the existing
  `paywall_sheet.dart` snackbar copy ("No previous purchase found to
  restore.").
- Rotate banner should not show on tablets/large-width portrait if it would
  be visually wrong — reuse the same width check already implicit in the
  screens' existing responsive layout code rather than inventing a new
  breakpoint.

## Success Criteria
`flutter analyze` clean, `flutter test` passing, and on-device confirmation
that all four practice screens stay awake, the new Settings screen's
controls actually change behavior (including Restore Purchases), the
rotate-hint banner appears once in portrait and stays dismissed, and turning
off haptic tick silences the metronome's vibration.

## Open Questions / Risks
None outstanding — scope was confirmed via interview before starting
(consolidate settings, package_info_plus for version, wakelock always-on,
rotate-hint on all 4 screens, dismiss persisted).
