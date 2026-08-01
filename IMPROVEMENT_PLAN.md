# Scale Runner — Improvement Plan (from 2026-07-04 audit)

Ordered by dependency and value. Each phase is independently shippable; run
`flutter analyze` + `flutter test` after every phase.

## Status checklist

- [x] 1.1 Cancel QuizController flash timers on dispose
- [x] 1.2 Silent top keys in Jam Mode
- [x] 1.3 Parse multi-message MIDI packets
- [x] 1.4 Dev paywall bypass safety (`kDebugMode`)
- [x] 1.5 Bundle fonts / stop runtime fetching
- [x] 2.1 Drift-free metronome clock
- [x] 2.2 BLE-only latency fix (immediate fix)
- [x] 2.2 Latency calibration screen (built 2026-07-07: `lib/screens/latency_calibration_screen.dart`, per-device storage in `QuizSettings`, entry point in MIDI monitor)
- [x] 2.3 Difficulty setting (timing windows)
- [x] 3.1 Wakelock during drills
- [x] 3.2 Fix About button + real Settings screen
- [x] 3.3 Portrait keyboard usability (rotate-hint banner)
- [x] 3.4 Metronome tick haptic toggle
- [x] 4.1 Scoped rebuilds + repaint isolation
- [x] 4.2 Minor cleanups (MidiService device-list caching)
- [x] 5.1 Lifetime stats screen (code complete; on-device check pending)
- [x] 5.2 Key selection in quiz modes (code complete; on-device check pending)
- [x] 5.3 Paywall trial sessions (code complete; on-device + real RevenueCat
      keys still needed to exercise for real)
- [x] 5.4 Accessibility pass

Everything is done except the on-device verification passes noted above (2-4
for Phase 5, dot-glyph/perf feel for Phase 4).

---

## Phase 1 — Bug fixes (do first, small and safe) — ✅ DONE 2026-07-05

### 1.1 Cancel QuizController flash timers on dispose
**File:** `lib/quiz/quiz_controller.dart`
`_flashWrong` (line ~229) creates an anonymous 450ms `Timer` that can fire
`notifyListeners()` after dispose (e.g. rebuilding the controller from the
settings sheet while a red flash is pending).
- Replace the per-note anonymous timers with a single stored `Timer? _wrongFlashTimer`
  that clears the whole `_wrongFlash` set (same pattern as `ScaleRunController._flash`).
- Cancel it in `dispose()`.
- Test: press wrong note, dispose controller before 450ms, pump — no assert.

### 1.2 Silent top keys in Jam Mode
**Files:** `lib/audio/note_player.dart`, `assets/audio/`
Samples stop at `note_72.wav`; Jam's 2.5-octave keyboard reaches F5 (77).
- Generate `note_73.wav` … `note_77.wav` with the same synthesis script
  (same envelope/level as existing samples), register nothing new in pubspec
  (whole `assets/audio/` dir is already included).
- Set `NotePlayer.highMidi = 77`.

### 1.3 Parse multi-message MIDI packets
**File:** `lib/midi/midi_service.dart` (`_handlePacket`, line ~181)
BLE MIDI coalesces simultaneous note-ons (chords) into one packet; the current
parser reads only bytes 0–2.
- Rewrite as a loop: walk the byte array; on a status byte (>= 0x80) update
  current status, then consume 2 data bytes per Note On/Off message; support
  running status (data bytes with no new status byte reuse the last status).
  Skip non-note status types by their known lengths (ignore unknown gracefully).
- Keep the vel-0-is-off rule.
- Unit-test the parser with: single note, two note-ons in one packet,
  running-status packet, interleaved note-off. (Extract parsing into a pure
  function `List<MidiNoteEvent> parseMidiBytes(Uint8List, {int lastStatus})`
  so it's testable without the plugin.)
- Verify on-device with a BLE keyboard playing chords in Chords quiz.

### 1.4 Dev paywall bypass safety
**File:** `lib/purchases/purchase_service.dart`
- Change `static const bool _devUnlockAll = true;` to
  `static const bool _devUnlockAll = kDebugMode;` (**recommended** — impossible
  to ship accidentally in a release build; a release TestFlight build shows the
  real paywall).
- Alternative (not recommended): keep the manual flag and add it to the ship
  checklist.

### 1.5 Bundle fonts / stop runtime fetching
**Files:** `pubspec.yaml`, `lib/theme/app_theme.dart`, new `assets/fonts/`
`google_fonts` fetches Inter + Space Grotesk over the network, contradicting
the privacy policy ("does not connect to the internet").
- **Recommended:** download the Inter and Space Grotesk .ttf files (weights
  actually used: Inter 400/500/600/700, Space Grotesk 500/700), put them in
  `assets/fonts/`, declare them under `flutter: fonts:` in pubspec, and replace
  `GoogleFonts.*` calls with plain `TextStyle(fontFamily: 'Inter' / 'SpaceGrotesk')`.
  Then remove the `google_fonts` dependency entirely — one less package, fully
  offline, policy stays true.
- Alternative: keep google_fonts, bundle fonts in `google_fonts/` asset dir and
  set `GoogleFonts.config.allowRuntimeFetching = false`. Less code churn but
  keeps the dependency.

---

## Phase 2 — Timing accuracy (one coherent batch) — ✅ DONE 2026-07-07

*Note: Phase 2 includes the 2026-07-07 "Metronome & Timing Score — Solutions Implementation Plan" which rebuilt ScaleRunController, extended latency compensation to Inversion Running & Jam Mode, and added a cross-controller latency-parity regression test.*

These three interact; do together, in this order.

### 2.1 Drift-free metronome clock
**File:** `lib/widgets/metronome_bar.dart` (`MetronomeController`)
Replace `Timer.periodic` + `DateTime.now()` with absolute scheduling:
- On `start()`: `_epoch = Stopwatch()..start(); _tickCount = 0;`
- Each tick schedules the next as a one-shot
  `Timer(Duration(ms: nextIdealMs - _epoch.elapsedMilliseconds), _tick)` where
  `nextIdealMs = (++_tickCount) * _periodMs`. Late timer firings self-correct
  instead of accumulating.
- `msSinceLastTick` becomes `_epoch.elapsedMilliseconds - _lastIdealTickMs`
  (judged against the *ideal* beat time, not the jittery actual fire time).
- On `nudge()` while running: rebase the epoch so the next beat lands one new
  period after the previous ideal tick (avoids a stutter on tempo change).
- Existing controllers need no changes — they consume `msSinceLastTick` /
  `beatPeriodMs` through the same getters.
- Test with a fake clock: 10 minutes of simulated ticks, assert zero cumulative
  drift; late-fire simulation self-corrects.

### 2.2 Per-transport latency + calibration screen — ✅ DONE 2026-07-07 (both parts)
**Files:** `lib/screens/scale_run_screen.dart` (line ~83), new
`lib/screens/latency_calibration_screen.dart`, `lib/quiz/quiz_settings.dart`
- Immediate fix: only apply `defaultBleLatencyMs` when the connected device is
  actually BLE (`MidiDevice.type` exposes the transport); USB gets 0.
- Calibration screen (built): metronome ticks 8 beats, user taps/plays along,
  app records the median offset (clamped at 0) and stores it via
  `QuizSettings.setInputLatencyMs()` (per device name). All three run screens
  read the stored value first, falling back to `defaultBleLatencyMs`. Entry
  point: "Calibrate Timing" button on the MIDI monitor screen.
- 2026-07-07 audit fixes: latency-shifted presses that wrap past a tick
  (struck before it, delivered after) are now judged as early hits on the
  current beat in Scale Running and are rescuable by grace in Inversion
  Running; count-in downbeat judging also subtracts latency. Covered by the
  "Latency wrap" group in `test/latency_parity_test.dart`.

### 2.3 Difficulty setting (timing windows)
**Files:** `lib/quiz/quiz_settings.dart`, `lib/widgets/quiz_settings_sheet.dart`
(Challenge tab) + the three run settings sheets, threshold consumers.
- Add `enum TimingDifficulty { easy, normal, strict }` with windows
  (on-beat/close ms): easy 100/200, normal 70/150 (current), strict 50/100.
  **Recommended:** one global setting (key `timing_difficulty`), not per-mode —
  simpler mental model, and the thresholds are currently shared anyway.
- Replace the duplicated `onBeatMs`/`closeMs` consts in `MetronomeController`,
  `ScaleRunController`, `JamModeController` with values injected at construction
  (controllers get `this.onBeatMs`/`closeMs` ctor params, defaulting to 70/150
  so existing tests pass unchanged).
- Scale `graceMs` with the close window (grace = closeMs).
- UI: three-way segmented control in each mode's settings sheet (shared widget).

---

## Phase 3 — UX fixes (small, independent) — ✅ DONE 2026-07-05

### 3.1 Wakelock during drills
**Files:** `pubspec.yaml` (+`wakelock_plus`), the three run screens + quiz screen.
- Enable when a session starts (`RunPhase/JamPhase != idle`, or on quiz screen
  entry), disable on stop/dispose. **Recommended:** enable for all four practice
  screens while mounted — simpler than tracking phase, and a practice screen in
  the foreground is always "in use."

### 3.2 Fix About button + consolidate a real Settings screen
**Files:** `lib/screens/home_screen.dart` (line ~234), `lib/screens/settings_screen.dart`
- Tooltip "Settings" → "About", or better: grow `SettingsScreen` into a real
  settings page — app version, note-sound toggle (currently buried per-mode),
  timing difficulty (Phase 2.3), Restore Purchases button (Apple requires one
  to be findable), privacy policy in a sub-page. **Recommended.**

### 3.3 Portrait keyboard usability
**File:** `lib/screens/quiz_screen.dart` + `lib/widgets/piano_keyboard.dart`
Options:
  a) Rotate-hint banner in portrait ("rotate for bigger keys").
  b) 1-octave portrait keyboard with octave-shift buttons.
  c) Re-force landscape on phones (was removed).
- **Recommended: (a)** — cheapest, no logic changes, MIDI users don't care
  about on-screen key size. Revisit (b) only if analytics/feedback show heavy
  tap-input use in portrait.

### 3.4 Metronome tick haptic toggle
**Files:** `metronome_bar.dart`, `quiz_settings.dart`, settings sheets.
- `tick_haptic` bool (default true), checked in `MetronomeController._tick`.

---

## Phase 4 — Performance hardening — ✅ DONE 2026-07-05

### 4.1 Scoped rebuilds + repaint isolation
**Files:** all four practice screens, `piano_keyboard.dart`
- Wrap `PianoKeyboard` in a `RepaintBoundary`.
- Split each screen's single whole-body `AnimatedBuilder` into two
  `ListenableBuilder`s (prompt area, keyboard) so text layout doesn't rerun on
  every key glow. Keyboard rebuilds are the hot path; prompt only changes on
  round/beat boundaries.
- **Recommended scope:** do the `RepaintBoundary` everywhere now (one line);
  do the builder split only on `ScaleRunScreen` + `JamModeScreen` (the
  beat-driven, rebuild-heavy screens) and measure with DevTools before touching
  the quiz screens.

### 4.2 Minor cleanups (opportunistic, same PR)
- `MidiService._handleSetupChanged`: cache the `devices()` result and pass it
  to both `refreshConnectionState` and `_tryAutoReconnect` (halves the queries).
- `ScaleRunController._flash`: shared timer clears both flash sets 350ms after
  the *last* press, so earlier flashes linger during fast runs — per-set timers
  if it's visually noticeable; otherwise skip.

---

## Phase 5 — Features — ✅ CODE COMPLETE 2026-07-05 (on-device checks pending)

Full plan + per-checkpoint status: `phase5-features-implementation-plan.md`.
All 4 checkpoints (Inversion Running tracking, stats screen, quiz key
selection, paywall trial sessions) are built, `flutter analyze` clean, 236
tests pass. Checkpoint 1 confirmed on-device; checkpoints 2-4 still need an
on-device pass, and checkpoint 4's trial/paywall gate needs real RevenueCat
keys (see `PAYWALL_SETUP.md`) before it can be exercised for real — debug
builds currently bypass it via `PurchaseService._devUnlockAll`.

### 5.1 Lifetime stats screen (highest value)
**Files:** new `lib/screens/stats_screen.dart`, `quiz_settings.dart` (readers
exist: lifetime aggregates from `mergeRunStats`/`mergeJamStats`), home screen
entry point.
- Sections: Scale Running (per-key + per-mode accuracy bars, weakest
  highlighted), Jam (per-quality + per-degree), Quiz (score/best streak).
- Sort by accuracy ascending ("work on these first").
- **Recommended entry:** a bar-chart icon in the home header next to
  info/help.
- Persistence note: current prefs schema stores `(attempts, correct)` per
  bucket — enough for accuracy bars, not for time-series. **Recommended:** ship
  v1 with aggregates only; add dated session-history rows (a JSON list capped
  at ~100 sessions) later if trends are wanted.

### 5.2 Key selection in quiz modes
**Files:** `quiz_controller.dart` (`_nextRound`, line ~271), `quiz_settings.dart`,
`quiz_settings_sheet.dart` (Practice tab).
- Setting: enabled root pitch classes per mode (default all 12), stored like the
  enabled-formula lists. `_nextRound` picks from the enabled set.
- UI: 12 filter chips (C, Db, D…) with All/None, enforcing ≥1 like the formula
  toggles.

### 5.3 Paywall trial sessions
**Files:** `purchase_service.dart` or new `lib/purchases/trial_gate.dart`,
`home_screen.dart` gating methods, `quiz_settings.dart`.
- **Recommended design:** each Pro mode playable N=1 full session for free.
  Persist `trial_used_<mode>` bool; gated open flow becomes: pro → open;
  trial unused → open with a "1 free session" toast; else paywall. Show the
  paywall automatically on the trial session's summary sheet close ("Enjoyed
  it? Unlock…") — that's the highest-intent moment.

### 5.4 Accessibility pass — ✅ DONE 2026-07-05
**Files:** `piano_keyboard.dart`, beat-dot builders in run/jam screens.
- Wrap keys in `Semantics(label: noteName, button: true)`.
- Beat dots: encode result by shape/icon as well as color (e.g. check / half /
  x glyphs inside the dots) — colorblind-safe.
- Verify contrast of `textSecondary` on `surface` meets 4.5:1.

---

## Suggested sequencing

| Order | Work | Size |
|---|---|---|
| 1 | Phase 1 (five bug fixes) | S — one session |
| 2 | Phase 2 (clock, latency, difficulty) | M — the core quality batch |
| 3 | Phase 3 (wakelock, settings screen, portrait hint, haptic toggle) | S |
| 4 | Phase 5.1 stats screen | M |
| 5 | Phase 5.2 key selection, 5.3 trials | S–M each |
| 6 | Phase 4 perf + 5.4 accessibility | S, as-needed |

Ship checklist reminder (unchanged from before): RevenueCat keys + store
products, host privacy policy URL, App Privacy declaration — plus, after 1.5,
the declaration can truthfully say "no data collected, no network."
