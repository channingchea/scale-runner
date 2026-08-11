# Voicings — Implementation Plan

_Last updated: 2026-08-11 — **all 5 phases built** (`flutter analyze` clean, 411 tests pass). Phase 2's drill loop was confirmed working on device by Channing before Phase 5; the Phase 5 additions (settings sheet, summary, paywall) have not been played on hardware yet._

## Overview

A new standalone practice mode that drills one exact chord voicing through all 12 keys. In v1 every voicing is **built by the user** — you play a shape on the keyboard, tap which note is its root, name it, and Voicings walks you through it in every key.

Self-paced, piano only, and deliberately **not scored**: no accuracy, no mode score, no leaderboard, no friend feed. It is a woodshed tool. Sessions still keep the daily streak alive and count toward weekly practice.

The mode is free; a user may save **3 voicings** before Pro is required.

## Non-goals for v1

- [ ] Instruments other than piano
- [ ] The preset voicing library (researched and specced — see Appendix, deferred to v2)
- [ ] Automatic chord-name detection / analysis (the user names their own voicings)
- [ ] Any scoring, accuracy stat, mode score, leaderboard entry, or friend-feed post
- [ ] Tempo-driven judging — the metronome is a manual on/off click, as in Scales and Chords, wired to nothing
- [ ] Queues of multiple voicings per session
- [ ] Cloud sync of saved voicings

---

## Core mechanic

### Data model

`VoicingSpec` stores **two** representations of the same shape. Storing only one breaks either the display or the judging.

| Field | Meaning |
|---|---|
| `id` | stable String, assigned at save |
| `name` | user-supplied, required (Save stays disabled until non-empty) |
| `rootPc` | 0–11, chosen by the user |
| `offsets` | **signed** semitones from the root, ascending as voiced. **May be negative.** |
| `createdAt` | for stable ordering and future sync |
| `sig` (derived) | `offsets` re-based so the bass is 0 — the matching signature |

Negative offsets are normal, not an edge case: any drop voicing that puts a voice below its root produces one. Cmaj7 drop 2 with the 7th in the bass is `[-1, 4, 7, 12]`.

### The root rule

Choosing a root *pitch class* is not enough — computing offsets needs a root *pitch*.

> **`rootMidi` = the occurrence of the chosen pitch class nearest the lowest played note.**

Verified against three reference shapes:

| Played | Root | → offsets | Shape |
|---|---|---|---|
| B3 E4 G4 C5 | C | `[-1, 4, 7, 12]` | Maj7 drop 2, 7th in bass |
| C4 G4 E5 | C | `[0, 7, 16]` | open / spread triad |
| E4 G4 B4 D5 | C | `[4, 7, 11, 14]` | rootless A |

### Matching — octave-agnostic, order-strict

A played attempt is correct when **both** hold:

1. `sig(heldNotes) == spec.sig` — the interval spacing matches exactly
2. `lowestHeld.pitchClass == (keyPc + offsets.first) mod 12` — the right chord tone is in the bass

Consequence: the shape counts **anywhere on the keyboard**, but a close voicing can never pass for a drop 2. That is the point of the mode.

### Degree formula — free, no analysis

The bass-up formula derives mechanically from `offsets`: `offset mod 12` → degree label.

- [x] Reuse the existing `formulaOf()` in `lib/theory/music_theory.dart` — it already preserves order and handles the `#4`/`b5`, `#5`/`b6`, `bb7` respellings. Dart's `%` returns non-negative values, so negative offsets pass through correctly with no changes.
- [x] Add one rule on top: when `offset >= 12`, relabel colour tones as compound intervals — `2→9`, `b2→b9`, `4→11`, `#4→#11`, `6→13`, `b6→b13`. Leave `1 3 5 b7 7` alone.

Spot-checked: `7-3-5-1` (Maj7 drop 2, 7th bass), `1-5-3` (open triad), `3-5-7-9` (rootless A), `b7-9-b3-5` (rootless B min9), `1-4-b7-b3-5` (quartal), `1-b3-b5-bb7` (dim7).

### Key sequencing

- **Chromatic** — ascend `+0 … +12`, then descend `+11 … +0`. Apex played once. **25 steps.**
- **5ths** — always up a perfect 5th, 12 keys, no separate descent. When the suggested register would run off the top of the keyboard, the anchor drops an octave. Since matching ignores register, an out-of-range guess still counts.

### Keyboard

3 octaves, C3–C6 (MIDI 48–84), fixed for the whole session so the voicing visibly walks up and back down. Target dots fold down an octave when the climb would run off the top.

---

## Phase 1 — Theory core (pure Dart, no UI) ✅ done 2026-08-11

- [x] Create `lib/theory/voicings.dart`
- [x] `VoicingSpec` with `id`, `name`, `rootPc`, `offsets` (signed), `createdAt`
- [x] Derived getters: `sig`, `span`, `noteCount`, `bassPcIn(keyPc)`, `notesFrom(rootMidi)`
- [x] `rootMidiFor(notes, rootPc)` implementing the root rule
- [x] `offsetsFrom(notes, rootPc)`
- [x] `voicingFormula(offsets)` — wraps `formulaOf()` plus compound relabelling
- [x] `encode()` / `decode()` for SharedPreferences round-tripping
- [x] `VoicingCycle(spec, startPc, increment, keyboardLow, keyboardHigh)` → ordered `List<VoicingStep>` with `keyPc`, `notes`, `label`
- [x] Chromatic sequencing (25 steps, apex once) and 5ths sequencing (12 keys) with the octave-drop rule
- [x] `test/voicings_test.dart` — root rule against the three reference shapes; negative offsets survive encode/decode; formula spot-checks incl. `bb7` and compound relabelling; both increments from several start keys; octave-fold boundary

**Built beyond the checklist** (all pure theory, all tested — they belong here rather than in the controller):

- `signatureOf(notes)` and `VoicingSpec.matches(held, keyPc)` — the two-condition match itself. Phase 2's controller just wires `_held` into it.
- `VoicingSpec.fromNotes(...)` — capture-screen convenience (Phase 4).
- `VoicingSpec.copyWith(...)` — rename/edit without touching `id` or `createdAt` (Phase 3/4).
- `kVoicingKeyboardLow` / `kVoicingKeyboardHigh` (48 / 84) as the shared C3–C6 defaults.

**Decisions made while building:**

- `KeyIncrement` is reused from `scale_running.dart` (already what `quiz_settings` persists) and re-exported from `voicings.dart`, so Phase 3's `voicing_increment` setting needs no new enum.
- Tritone ties in the root rule resolve **downward**, so an ambiguous bass reads as `+6` rather than `−6`.
- `encode()` uses JSON, not the pipe-delimited format used for stats — `name` is free user text and can contain a pipe. `decode()` returns null on anything malformed so one bad line can't take the collection down.
- Octave-folding stops rather than pushing a shape off the *other* end of the keyboard: a voicing wider than 3 octaves still produces a step, it just can't fit.

## Phase 2 — Drill screen with one hardcoded voicing — built 2026-08-11, awaiting on-device check

Ordered first so the practice loop is validated on real hardware before any CRUD exists.

- [x] Create `lib/runner/voicing_run_controller.dart` — modelled on `InversionRunController` minus everything beat-related (no `BeatJudge`, no count-in, no tempo phase, no tally)
- [x] `_held` set fed identically by on-screen taps and MIDI (`bindMidi`)
- [x] `currentVoicingHeld` implementing the two-condition match
- [x] Wrong note → red flash, **no advance, no rewind**; block until correct
- [x] `stepIndex` / `stepCount` / `isComplete`; `onSessionEnd` carrying keys completed and elapsed duration
- [x] No `chordScores`, no `accuracy`, no `RunTally` — deliberately absent
- [x] Create `lib/screens/voicing_drill_screen.dart` with a hardcoded spec
- [x] `PianoKeyboard` at `lowMidi: 48`, `octaves: 3`, fixed for the session
- [x] Prompt: key name (large) + degree formula beneath it in `AppColors.accent`
- [x] Target dots via `isTargetHint`, octave-folded
- [x] Progress bar (`7 / 25`)
- [x] Optional `MetronomeBar` — manual toggle, `onBeat` **not** wired to the controller
- [x] MIDI binding + `RotateHintBanner`
- [x] `test/voicing_run_controller_test.dart` — right shape wrong register passes; right pitch classes wrong spacing fails; wrong bass fails; wrong note does not advance; full traversal fires `onSessionEnd` once
- [x] **On-device check** — done 2026-08-11 (after Phase 4). Channing confirms the loop works. The Phase 5 additions still need their own pass.

**Decisions made while building:**

- **Advance is press-driven *and* release-driven.** Releasing a stray note that was blocking an otherwise-correct shape advances the drill, so a fumble never leaves the player stuck holding the right chord with nothing happening. A subset can only ever match when the correct shape really is sounding, so this can't advance on a wrong answer.
- **"Wrong note" = a pitch class outside the key's chord tones.** Those flash red. Right tones in the wrong spacing or with the wrong bass flash back normally and simply don't advance — the shape is what's being judged, not the individual note.
- `onSessionEnd(keysCompleted, elapsed)` fires exactly once per session, on natural completion *and* on an early stop, and never twice. Phase 5 hangs `recordPractice()` off it; Phase 2 leaves it unwired and shows the same numbers inline.
- Elapsed time uses `package:clock`, so it's fake-clock testable like the metronome.
- The home-screen `_ModeCard` was pulled forward from Phase 3 (there was no other way to reach the screen on device). It is free/ungated as specced, sits last in the list, and **borrows the Chords icon** — Voicings needs artwork of its own. Its `onTap` opens the drill directly; Phase 3 re-points it at the collection screen.

**Watch for on device:** three octaves on a phone is 22 narrow white keys (plan risk #1), and whether blocking-until-correct feels like focus or feels like a wall.

## Phase 3 — Storage and the collection screen — built 2026-08-11

- [x] Add `voicing_customs` (StringList of encoded specs) to `quiz_settings.dart`, plus `voicing_start_key`, `voicing_increment`, `voicing_show_dots`, `voicing_show_formula`. **No stats key** — intentional.
- [x] CRUD helpers: `savedVoicings()`, `upsertVoicing()`, `deleteVoicing(id)`
- [x] Create `lib/screens/voicings_screen.dart` — the mode's home
- [x] Empty state: icon, "Build a voicing. Drill it in all 12 keys.", explainer, one large **Create your first voicing** button
- [x] Populated: one card per voicing — shape thumbnail, name, `{root} · {formula} · {n} notes`
- [x] Thumbnail widget: compact keyboard strip, chord tones in accent teal, **any octave of the root** in amber (a rootless voicing correctly shows none)
- [x] `⋮` menu → Edit · Rename · Duplicate · Delete
- [x] Footer: **+ New voicing** with `n of 3 free` (or `Pro · unlimited`)
- [x] Add the `_ModeCard` to `home_screen.dart` — `locked: false`, no `trialUsed` check _(done in Phase 2; still needs its own icon)_
- [x] Wire the drill screen to open from a card tap

**Decisions made while building:**

- The drill screen now reads `voicing_start_key` / `voicing_increment` / `voicing_show_dots` / `voicing_show_formula` — the settings are live even though the sheet that changes them is Phase 5.
- `savedVoicings()` skips lines that fail to decode rather than throwing, so one corrupt entry can't hide the whole collection. `upsertVoicing()` replaces by id **in place**, so renaming doesn't shuffle a voicing to the bottom of the list.
- The thumbnail is a `CustomPainter` (`lib/widgets/voicing_thumbnail.dart`), not a widget per key — it renders in a scrolling list. It always opens on a C and closes on a B so it reads as a keyboard, and widens to whatever the shape spans.
- The empty state carries a "Preview the drill with a sample voicing" text button. _(Phase 4 kept it, reworded to **"Try a sample voicing first"** — see below.)_
- `test/voicing_settings_test.dart` covers the CRUD round-trip, including a negative-offset shape and a name containing a pipe, plus one test asserting a saved voicing leaves every lifetime stat and `modeStats()` untouched.

## Phase 4 — Capture screen — built 2026-08-11

- [x] Create `lib/screens/voicing_capture_screen.dart`, doubling as edit mode
- [x] **① Play the voicing** — 3-octave keyboard; on-screen taps **latch** notes on/off; MIDI note-on latches the same way so holding a chord works. Live note readout + Clear.
- [x] **② Which note is the root?** — appears at 2+ notes. Row of **all 12 pitch-class chips** (so rootless voicings work), played ones emphasised, defaulting to the lowest played note's pitch class.
- [x] Live **Formula, bass up** readout. Never show raw offsets — user-facing UI shows degrees only.
- [x] **③ Name it** — text field; Save disabled until non-empty
- [x] Edit mode reconstructs playable notes from `offsets` + `rootPc` and prefills the name
- [x] Warn (don't block) when saving a shape whose `sig` + `rootPc` already exists
- [x] `_openCapture()` in `voicings_screen.dart` is real — both **+ New voicing** and **⋮ → Edit** now open the builder
- [x] `test/voicings_test.dart` — capture round-trip, keyboard placement for all 12 roots, `sameShapeAs` (10 new tests, 409 total)

**Decisions made while building:**

- **The capture screen never touches storage.** It pops the finished `VoicingSpec`; `voicings_screen.dart` calls `upsertVoicing()`. So an abandoned capture writes nothing, and persistence stays in one place. The collection passes itself in as `others` purely so the screen can run the duplicate check.
- **Two theory helpers, both pure and tested**, rather than layout maths in the screen:
  - `VoicingSpec.playableNotes({low, high})` — the inverse of capture. Reuses the drill's own octave-fold rule (`_baseRoot` / `_fitRoot` were lifted out of `VoicingCycle` into library-level functions), so editing a shape shows it in the same register the drill opens on.
  - `VoicingSpec.sameShapeAs(other)` — same `sig`, same bass tone, same root. Deliberately **octave-insensitive**: two captures of one shape an octave apart are the same voicing, because the drill genuinely can't tell them apart.
- **The round-trip is exact for everything capture can produce.** `offsetsFrom(spec.playableNotes(), rootPc) == spec.offsets` for all 12 roots. The one shape that would shift is `offsets.first == -6`, and the root rule's downward tie-break means capture can never produce it. Pinned by a test with a comment saying so.
- **The root chip defaults to the bass but doesn't stick there** — `_pickedRootPc` stays null until the user taps, so the default keeps tracking the lowest note as they build. Clear resets it.
- **Save needs 2+ notes and a name.** One note is a note, not a voicing.
- **Latching means note-*on* toggles.** Playing a note again removes it — the same gesture as tapping twice, so the MIDI and touch paths behave identically. Note-off is ignored entirely.
- **Kept the sample-voicing link** in the empty state, reworded to "Try a sample voicing first". This is the answer to open question #4 — a custom-only mode opens empty, and this lets a new user feel the drill before deciding what to build.
- Keyboard height is a fraction of `LayoutBuilder` constraints, not of screen height, so the soft keyboard shrinks the piano instead of shoving the name field off-screen.

## Phase 5 — Paywall, session end, and verification — built 2026-08-11

- [x] **+ New voicing** and **Duplicate** open `PaywallSheet` when `savedVoicings().length >= 3 && !isPro`. Never delete over-limit voicings — only block creating more.
- [x] `VoicingSessionSummarySheet`: voicing name, keys completed, time practiced. No accuracy, no share. "Run it again" / "Pick another voicing".
- [x] On session end: `StreakService.instance.recordPractice()` (+ milestone sheet, as in `inversion_run_screen.dart`)
- [x] `SocialService.instance.recordWeeklySession(0, 0)` — marks the day and increments the session count **without** touching `attempts`/`correct`, so accuracy and the leaderboard are untouched. This is what makes "counts for practice, not scored" work with zero changes to the social layer.
- [x] Drill settings sheet: **Keys** (start key + Chromatic/5ths) and **Challenge** (dots on/off, formula on/off) — two sections only
- [x] `flutter analyze` + `flutter test` clean (via Desktop Commander) — 411 tests
- [ ] **On-device pass with a real MIDI keyboard** — the drill loop was confirmed on device before this phase; the settings sheet, the summary and the paywall have not been touched on hardware
- [x] Verify a Voicings session bumps the streak but leaves Stats, mode scores, and the friend feed untouched
- [x] Log to project memory

**Decisions made while building:**

- **The settings sheet distinguishes a restart from a redraw.** Start key and increment define the whole `VoicingCycle`, so changing either rebuilds the controller and starts over; the dots/formula toggles only `setState`. The screen remembers `_startPc` / `_increment` purely to tell those two cases apart — flipping a hint mid-run must not throw the run away.
- **The increment picker shows its consequence.** Chromatic and By fifths sit in a `SegmentedButton` with a line underneath spelling out what each means and how many keys it is (25 vs 12) — the difference between them is length as much as order.
- **Backing out mid-drill still counts as practice.** `dispose()` fires `_markPractice()` silently when the drill was running with keys landed. Without it, someone who drills 20 keys and hits back loses their streak day. `_markPractice()` is the *only* thing a Voicings session writes anywhere, which makes the "never scored" claim easy to audit — it's one four-line method.
- **A session that landed zero keys is not a session.** No streak day, no summary sheet — hitting Start then Stop shouldn't claim anything.
- **Editing is never paywalled, only creating.** `_clearedFreeLimit()` guards **+ New voicing** and **Duplicate**; ⋮ → Edit skips it, because locking someone out of a shape they already own is a different (and worse) product.
- `ReminderPromptSheet.maybeShow` is called after the summary, matching every other practice mode. It's self-gating (once ever, and only after a practice day exists) — leaving it out would have made Voicings the one mode that never offers a reminder.
- **The "never scored" proof is two tests on `WeeklyStat`**, not a widget test: a `(0, 0)` session marks the day and the session count, leaves `accuracy` **null** rather than 0%, and cannot move an accuracy earned in a scored mode. That's the whole mechanism, pinned.

---

## Open questions / risks

1. **Three octaves on a phone is 22 narrow white keys.** Confirmed cramped in the prototype. The rotate hint helps; consider whether this mode should nudge toward landscape by default. This mode leans on a real MIDI keyboard harder than any existing mode.
2. **Chromatic sessions are 25 keys long.** Confirm that is the intended length versus 12-up-only or 23.
3. **Voicings is free while Inversion Running is Pro**, and Voicings arguably teaches more. Mode-card copy should draw a clear line between them.
4. ~~**Cold start is real.**~~ _Answered in Phase 4:_ the empty state keeps a permanent **"Try a sample voicing first"** link into the demo drill, so a new user can feel the mode before building anything. Still worth watching in beta.

---

## Appendix — v2 preset library groundwork

Research and interval verification are already done; see the **voicings-library-preview** artifact for all 122 presets, playable.

**The key finding: it is all one generator.** Close / drop 2 / drop 3 spacing × which chord tone is in the bass produces most of the repertoire across genres. "Drop 2 of a triad with the root in the bass" *is* the pop open/spread triad, and classical four-part **open position is literally drop 2**. Genre is a tag on a preset, not a separate data structure.

Three families need hand-written offsets because they change the note set rather than the spacing: **shell voicings** (omit the 5th), **rootless A/B** (omit the root, add the 9th), **quartal** (non-tertian, 5 notes).

Two gotchas already identified:

- Label variants by **bass tone** (R / 3rd / 5th / 7th), never by "inversion index" — applying drop 2 to a close root-position chord puts the **5th** in the bass, so "root position, drop 2" would be actively misleading.
- **Symmetric chords** (diminished 7th, augmented triad) produce identical shapes at every bass position. Suppress the bass row for those.

Range check for a 3-octave keyboard, allowing 12 semitones of chromatic travel: close ✅, drop 2 ✅, drop 3 ❌ (needs 32), quartal ❌ (32), drop 2&4 ❌ (36). Cut drop 2&4; rely on the octave-fold rule for the rest.

The close/drop/bass taxonomy is also exactly what an automatic chord-namer would need, if that ever ships.
