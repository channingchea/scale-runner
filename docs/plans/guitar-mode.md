# Guitar Mode - Implementation Plan

**Status: PLANNED, nothing built.** Researched + prototyped 2026-09-02, reviewed
against the code at `fec6a93` the same day. Decisions in the next section were
confirmed with Channing during that review.

## Overview
A global **Instrument** setting (piano or guitar) that swaps the on-screen
piano for an interactive fretboard across every drill. The fretboard is an
*input/display surface* swap: it calls the same four callbacks the piano calls,
so validators, `BeatJudge`, metronome, scoring, stats, streaks and social do not
change. The goal is parity: a guitarist should be able to do everything a
pianist can, at the same speed, with the same feedback.

The contract every mode already exposes:

```dart
KeyFeedback feedbackFor(int midiNote)   // glow colour
bool        isTargetHint(int midiNote)  // hint dots
void        pressKey(int midiNote)      // input
void        releaseKey(int midiNote)    // input
```

A working proof exists as the desktop artifact **`guitar-mode-proof`** (piano +
fretboard on one mock controller). It shows a horizontal full neck; the layout
decision below supersedes that for portrait.

## Decisions (confirmed 2026-09-02)
- **Portrait layout is a vertical chord-diagram box**: nut at the top, strings
  vertical, five frets visible, the box slides with the drill. Landscape shows
  a horizontal neck. Reason: the keyboard area on a phone is ~377 x 240pt, so
  a horizontal 16-fret neck gives ~23pt per fret, while the vertical box gives
  ~55pt per string and ~44pt per fret.
- **Sound: extend the piano samples to MIDI 40-88.** Same tone as today. This
  also fixes silent notes above F5 in Inversion Running and Voicings on piano.
- **One global setting** in Settings, not per drill.
- **Free for everyone.** The three Pro drills stay Pro exactly as they are.
- **Saved voicings carry an instrument tag.** A guitar shape and a piano shape
  are different artifacts.
- **Left-handed flip ships in v1.**
- **The two piano-side fixes ship first as their own small release** (Phase 0)
  so Guitar Mode starts on a clean base.

## Verified against the code (do not re-derive)

**Six `PianoKeyboard(` call sites**, and what each one passes:

| Screen | Line | `lowMidi` | Octaves | Range | Hint type | Judged by |
|---|---|---|---|---|---|---|
| `quiz_screen.dart` | 509 | 48 | 2 | 48-72 | exact MIDI (`targetNotes`, root in 48-59) | pitch class, scales in order |
| `scale_run_screen.dart` | 585 | 48 | 2 | 48-72 | pitch class (chord tones + the beat's run note) | pitch class per beat |
| `jam_mode_screen.dart` | 635 | 48 | 2.5 | 48-77 | pitch class (chord tones, or the whole scale in freestyle) | pitch class, root in bass for "any chord tones" |
| `inversion_run_screen.dart` | 540 | `60 + rootPc` (transposing) | 2 | 60-95 | exact MIDI (`currentStep.notes`) | pitch-class set + bass pitch class |
| `voicing_drill_screen.dart` | 470 | 48 | 3 | 48-84 | exact MIDI (`currentStep.notes`, octave-folded) | exact intervals, order-strict, bass pitch class |
| `voicing_capture_screen.dart` | 452 | 48 | 3 | 48-84 | none (`(_) => false`) | n/a, latching taps build a `VoicingSpec` |

So "pitch-class judged" is true for four drills; the Voicings drill is
**exact-interval and order-strict** (`VoicingSpec.matches`). That difference
drives Phase 5.

**Keyboard height budget** (`quiz_screen.dart:245-252`, same in every drill):
portrait `clamp(bodyHeight * 0.46, 140, 240)`, so 240pt on any phone;
landscape/compact `clamp(bodyHeight * 0.40, 120, 240)`, about 157pt on an
iPhone 15; desktop cap 320pt. Width is the screen minus 16pt padding. The piano
then caps its own width from its height (`maxKeyboardWidth`, aspect 5.5) so
keys stay key-shaped on a Mac; the fretboard needs its own cap.

**Piano touch targets today:** white keys are ~25pt wide on a phone (15 keys in
377pt), black keys ~15pt. The app already accepts sub-44pt widths; what it has
never had is a target that is small in *both* dimensions.

**Multi-touch is free on the piano** because every key is its own
`GestureDetector`. A `CustomPaint` fretboard gets none of that and has to track
pointers itself.

**Samples:** `assets/audio/note_48.wav` to `note_77.wav` only (22050 Hz, mono,
1.1 s). `NotePlayer.play` silently drops anything outside 48-77. The synthesis
script is not in the repo.

**Ambiguity numbers, neck pinned at 22 frets (standard tuning, low to high
`[40,45,50,55,59,64]`, range 40-86):**
- Positions per note over 48-72: 2-5, median 4. Over frets 0-15 only: 2-4,
  median 3 (the figures in the first draft assumed a 16-fret neck).
- Input is never ambiguous: one tap at (string, fret) is exactly one MIDI note.
  Display is one-to-many.
- Pitch-class hint for a 7-note scale: 84 dots on the whole 22-fret neck, 59
  on frets 0-15, **16-18 inside any 5-fret box** (piano shows 15-ish for two
  octaves). Exact-MIDI hint for one Quiz scale (8 notes): 26-29 dots on the
  neck, 8 in the box. The box is mandatory for every mode, not just the
  pitch-class ones.
- Inversion Running: every `commonChords` x 12 keys x every inversion step
  fits on adjacent strings with **triads in close position (span 2-3 frets)
  and 7ths in drop-2 (span 1-3)**. The reverse is unplayable (triads drop-2
  7-9 frets, 7ths close 5-6). Worked C Major: inv 0 strings 4-3-2 frets
  10-9-8; inv 1 strings 3-2-1 frets 9-8-8; inv 2 strings 4-3-2 frets
  17-17-17. About 8 of 84 triad voicings climb past fret 22 because the cycle
  climbs by octave, and the B-root cycles reach MIDI 90.

**Nothing on pub.dev helps.** `flutter_guitar_chord`, `libtab` (static
renderers), `guitar_chord_library` (v0.0.4, data only), `tonic` (unmaintained,
SDK risk), `music_notes` (no fretted-instrument support). Build it.

**User-facing strings that say piano or keys** (all need a guitar-aware
variant): `voicing_capture_screen.dart:212-214`, `settings_screen.dart:136-137`
(note sound subtitle), `welcome_sheet.dart:81-87`, `rotate_hint_banner.dart:60`
("Rotate for bigger keys"), `inversion_run_settings_sheet.dart:143`,
`social_screen.dart:534-535` (share text says "piano practice streak"),
`home_screen.dart:447-448`.

## Non-goals / Out of scope
- No MIDI-guitar or pickup input, no audio pitch detection. Tap only.
  (`ChordValidator` rejects any held note outside the chord, and a strummed
  source would need that loosened. Not now.)
- No alternate tunings, capo, 7-string, bass or ukulele. Standard tuning only.
- No guitar-specific sample set; taps play the piano tone.
- No tab notation staff. This is a fretboard surface, not a transcription.
- No changes to controllers' judging, `BeatJudge`, metronome, count-in,
  scoring, stats, streaks or social. Scores are comparable across
  instruments and stay in one pool.
- No store-listing or screenshot refresh in this feature; that is a follow-up
  once it is on hardware.

## Phase 0: Piano-side fixes, shipped first (own release)
**DONE 2026-09-02, commit `c046d73`.** Independent of Guitar Mode; both were
live bugs on piano.
- [x] `quiz_settings.dart`: `runShowDots()` / `setRunShowDots(bool)`
      (`run_show_dots`, default true), same pattern as `invShowDots()`.
- [x] `scale_run_settings_sheet.dart`: dots switch under a new Challenge
      header, same copy as the Inversion sheet. `scale_run_screen.dart` reads
      `_showDots` in `_rebuildController` and passes
      `isTargetHint: _showDots ? c.isTargetHint : (_) => false`.
- [x] Samples: `note_40.wav` to `note_47.wav` and `note_78.wav` to
      `note_95.wav` (26 new files), generated by the committed
      `tool/gen_note_samples.py`. `NotePlayer.lowMidi = 40`,
      `highMidi = 95`. Nothing changed in `pubspec.yaml`.
- [x] Tests: `test/scale_run_settings_test.dart` round-trips the new pref;
      `test/note_range_test.dart` walks every `InversionCycle` (all chords x
      12 keys) and `VoicingCycle` (three shapes x both increments x 12 start
      keys), asserts every note is inside `NotePlayer`'s range, that a file
      exists for each, and that each is 22050 Hz mono 16-bit 1.1 s.
- [x] `flutter analyze` clean, 486 tests pass.
- [ ] Bump build, ship to beta. **Not done — Channing's call.**

### What Phase 0 corrected in this plan
- **The top of the range is 95, not 88.** An `InversionCycle` on B Major 7th
  reaches MIDI 94 at its apex (`inversion(71, 4)` = `[83, 87, 90, 94]`), and a
  saved voicing spanning the full 48-84 capture keyboard transposes as high as
  95 in B, where `_fitRoot` has no octave left to fold into. Both are pinned
  by `note_range_test.dart`.
- **The sample recipe was recovered exactly, not approximated.** Additive sine
  partials at phase 0, each decaying `0.90` faster per partial than the one
  below, a linear attack, a linear release fade, peak-normalised to 0.82 full
  scale and truncated. Two voices, because the shipped files came from two
  batches:
  - **48-72:** 6 partials `[1, .55, .32, .20, .12, .07]`, attack 4 ms,
    release 40 ms, `k1 = 3.00 + 0.09 * (midi - 48)`.
  - **73-77:** 5 partials `[1, .501, .269, .156, .086]`, attack 5 ms,
    release 20 ms, `k1 = 5.55 + 0.125 * (midi - 73)`.
  The generator reproduces all 25 files from 48 to 72 **byte for byte**
  (`--verify`), which is what makes extending the range safe. New notes
  continue whichever voice they adjoin (40-47 the low voice, 78-95 the high
  one), so both seams are level and timbre matched; no existing file was
  touched. Assets grew from 1.5 MB to 2.7 MB.

## Phase 1: Device check (**still open — needs hardware**)
Phases 2 and 3 were built ahead of this against the numbers below, so the
check can now be run on the real `FretboardView` in a drill rather than on a
throwaway grid. Nothing after Phase 3 should be tuned until it is done.

Cell size cannot be judged in a simulator or in the HTML proof.
- [ ] Throw a static vertical 6-string x 5-fret grid into a drill's keyboard
      slot on a real phone in portrait. Expect ~55pt strings, ~44pt frets.
      Confirm adjacent-string mis-taps are rare with one finger, and that
      three fingers can hold a triad in the box without occluding it.
- [ ] Same grid horizontal in landscape (about 157pt tall on a phone, so ~26pt
      per string). Decide whether landscape phones keep the horizontal neck or
      also use the box. Desktop and iPad are not in question.
- [ ] Decide the hit model: each string's hit band runs to the midpoint of its
      neighbours (no dead zones), each fret's band likewise. Write the numbers
      into this doc.

## Phase 2: Theory core, `lib/theory/fretboard.dart`
**DONE 2026-09-02, commit `801db2b`.** Pure Dart, no UI, no MIDI, fully
unit-testable. All guitar-specific ambiguity lives here.
- [x] `Instrument { piano, guitar }` with `byName` for persistence.
- [x] `Tuning.standard`, `kMaxFret = 22`, `midiAt`, `positionsFor`,
      `lowest = 40`, `highest() = 86`.
- [x] `FretBox(start, width)` with `contains`, `distanceTo`, `clamped`.
- [x] `primaryFor(midi, box)`, `boxFor(targets)`, `fit(notes, {adjacentOnly})`
      returning a `FretShape`, `drop2`, `guitarVoicing`,
      `guitarVoicingCycle`.
- [x] `InversionCycle(chord, rootPc, {instrument})` and
      `InversionRunController(instrument:)`, both defaulting to piano.
- [x] `test/fretboard_test.dart`, 25 tests.

### What Phase 2 corrected in this plan
- **`fit` returns a `FretShape` (positions aligned to the notes), not
  `(startString, frets)`**, because `adjacentOnly: false` can skip a string
  and a start-plus-list cannot say which one.
- **Drop 2 changes the bass, and the bass is what the drill validates.**
  Dropping the second voice of the close voicing puts the 5th under a root
  position chord, which is a different inversion, so `currentVoicingHeld`
  would start demanding the wrong bass. `guitarVoicing` takes the drop 2
  whose bass is unchanged instead: the close voicing two rotations up, then
  dropped, which reduces to raising the second note from the bottom an octave
  (`[a,b,c,d]` -> `[a,c,d,b+12]`). C E G B becomes C G B E, the standard
  root-position drop 2. Pitch classes and bass pitch class are identical to
  the piano voicing in all 156 chord-and-key cycles, so judging, scoring and
  stats are untouched.
- **Per-step octave choice destroys the cycle.** The apex never fits under a
  hand where it is written, so it drops back onto exactly the notes of root
  position, in **156 of 156** cycles, not just "for high keys" as the open
  question below guessed. `guitarVoicingCycle` transposes the whole cycle by
  one shared offset, which keeps every interval between steps. All 156 now
  rise strictly in bass and top note from root position to the apex, sit on
  consecutive strings inside a five-fret box (max span 4), and reach no
  higher than fret 16.
- **Measured, so nothing here needs re-deriving:** a note over 48-72 has 2 to
  5 positions; a 7-note scale paints at most 18 dots in a five-fret box (the
  test asserts 20); `boxFor` returns width 5 for every quiz round the app can
  generate, scale or chord, in every root 48-59, so the six-fret allowance is
  never needed there.

## Phase 3: Widget, `lib/widgets/fretboard_view.dart`
**BUILT 2026-09-02. Not yet on hardware — Phase 1 is the check.**
- [x] Constructor mirrors `PianoKeyboard`: `feedbackFor`, `isTargetHint`,
      `onKeyDown`, `onKeyUp`, `showLabels`, plus `box`, `orientation`
      (`verticalBox` / `horizontalNeck`), `leftHanded`, `twinMode`
      (`primaryOnly` / `primaryAndGhost` / `all`), `tuning`.
- [x] `CustomPaint` for strings, frets, nut, inlays at 3/5/7/9/12/15/17/19/21,
      fret numbers, dots and glows. Horizontal neck uses the 17.817 spacing
      rule; the vertical box uses equal fret spacing (it is a diagram, not a
      neck).
- [x] **Input via `Listener`, keyed by pointer id.** `onPointerDown` hit-tests
      to (string, fret); `onPointerUp` and `onPointerCancel` release that
      pointer's note. A pointer that moves to another cell releases the old
      note and presses the new one (matches the piano's tap-cancel
      behaviour). Reject a second pointer landing on a string that already
      has one down.
- [x] **Ref-count per MIDI note.** Fret 5 on A and open D are both 50: call
      `onKeyDown` on the first pointer for that note and `onKeyUp` on the
      last, so lifting one finger never releases a note the other still
      holds.
- [x] **Glow only the tapped position.** `feedbackFor(midi)` returns
      `pressed` for every twin; the widget knows which cell the pointer is on
      and lights that one. A note held with no pointer (MIDI keyboard) lights
      its primary position.
- [x] Hint dots: `isTargetHint(midi)` is a predicate, so build the target set
      by querying 40-86 once per frame, then draw per `twinMode`: primary
      only, primary + ghost outline (**default**), or all positions. Dots
      hide under a glow, as on the piano.
- [x] Labels: note name per cell when `showLabels`, font size stepping down
      with cell width like `_WhiteKey` does.
- [x] `Semantics(label: noteName, button: true)` per cell, as the piano has.
- [x] Reuse `AppColors.correct` / `wrong` / `accent` / `target` and the same
      90 ms animation so feedback reads identically to the piano.
- [x] Width/height cap for desktop and iPad, the fretboard's equivalent of
      `maxKeyboardWidth` (string pitch 40-60pt, never wider).
- [x] Widget test (`test/fretboard_view_test.dart`, 11 tests): two simultaneous pointers on different strings produce two
      `onKeyDown`s; twin note ref-counting; pointer cancel releases; lefty
      flip mirrors string order but not fret order.

## Phase 4: Setting + surface swap
- [ ] `quiz_settings.dart`: `instrument()` / `setInstrument(Instrument)`
      (`instrument` key, default piano), `leftHanded()` / `setLeftHanded`,
      `guitarTwinMode()` / `setGuitarTwinMode`.
- [ ] `settings_screen.dart`: an **Instrument** section with a piano/guitar
      segmented control and, when guitar is selected, the left-handed switch
      and the twin-dots choice. Free, no Pro gate.
- [ ] `lib/widgets/instrument_surface.dart` (~40 lines): reads the setting
      and returns `PianoKeyboard` or `FretboardView`, forwarding the four
      callbacks and `showLabels`. Takes an `anchor` (the notes that define
      the box this round) so the fretboard can call `boxFor`.
- [ ] Swap the six call sites. Each screen already owns `_buildKeyboard(c,
      height)`; the surface keeps that height and picks orientation from
      `isCompactLayout(bodyHeight)` (compact = horizontal neck, otherwise the
      vertical box). Desktop always horizontal.
- [ ] Top bar icon: `Icons.piano` when MIDI is connected stays; the touch
      icon can stay `touch_app` for both instruments.
- [ ] Note sound: taps play the piano tone for both instruments (decided).

## Phase 5: Per-mode reconciliation
- [ ] **Quiz (Scales + Chords)**: anchor = `targetNotes`. Box from `boxFor`.
      Scales are sequential by pitch class, so any position of the next note
      counts. Verify all dots for a round land in-box.
- [ ] **Scale Running**: anchor = the step's chord pitch classes + run pitch
      classes, placed from the key root's position on the A string (frets
      3-14). Box slides when the key changes, never mid-run. Hints stay pitch
      class but are drawn only inside the box.
- [ ] **Jam Mode**: anchor = the jam key; box from the key root on the A
      string. Freestyle paints the whole scale, so the box is what keeps it
      readable. "Any chord tones" needs 3+ notes with the root lowest, which
      is a three-finger chord in the box; confirm on hardware.
- [ ] **Inversion Running**: `InversionCycle(..., instrument: guitar)` from
      Phase 2. The piano transposes its keyboard per round; on guitar the box
      slides to the step's fit. `currentVoicingHeld` (pitch classes + lowest
      held note's pitch class) is unchanged and still correct, because the
      lowest MIDI note means the same thing on both instruments. Step labels
      and formulas unchanged.
- [ ] **Voicings drill**: **no re-voicing.** `matches` is exact-interval, so
      the fretboard shows the shape exactly where `fit(currentStep.notes,
      adjacentOnly: false)` puts it (the whole shape may move by an octave;
      `matches` is octave-agnostic). If `fit` returns null the drill shows
      "This voicing does not fit under a hand on guitar" with a button to
      drill it on piano. Dots slide up the neck key by key, which is the
      most idiomatic thing in the whole feature.
- [ ] **Voicings capture on guitar**: latching taps, **one note per string**
      (a second tap on the same string moves the note; tapping the lit cell
      removes it). Box starts at frets 0-4 and the user can slide it (a
      small up/down control, since there is no drill to anchor it). Span is
      guaranteed playable because it was built on the board.
- [ ] **Range**: taps at MIDI 40-47 (low E frets 0-7) are below every
      drill's range; they judge by pitch class like any other note and now
      make sound (Phase 0). Nothing needs clamping.

## Phase 6: Voicings instrument tag
- [ ] `VoicingSpec.instrument` (`Instrument`, default piano when decoding
      entries without the field, so the existing library is untouched).
      Encode/decode round-trip test.
- [ ] Capture stamps the current global instrument on a new voicing. Edit and
      drill open on **the voicing's own instrument**, whatever the global
      setting; the global setting only chooses the surface for the other
      four drills and for new captures. (A shape is bound to the instrument
      it was built on.)
- [ ] `VoicingThumbnail`: a mini fretboard for guitar-tagged specs (same
      96x44 footprint, chord tones teal, root amber, exactly like the mini
      keyboard). Small instrument glyph on the card.
- [ ] `sameShapeAs` also requires the same instrument, so a piano shape and
      its guitar twin do not trigger the duplicate warning.
- [ ] Preset library (v2) is unaffected; presets would need a tag per entry
      later.

## Phase 7: Copy and share text
- [ ] Rewrite the seven strings listed above so each reads correctly for the
      active instrument ("Tap the frets below", "Rotate for a wider neck",
      "Highlight the frets to press", "practicing guitar with Scale Runner").
      House rule: no em dashes.
- [ ] Welcome sheet: "No piano needed" stays, add one line that guitar is a
      setting away.
- [ ] Settings note-sound subtitle no longer says "piano tone" specifically.

## Phase 8: Verify
- [ ] `flutter analyze` + `flutter test` via Desktop Commander.
- [ ] On hardware, per the standing rule: adjacent-string accuracy in the
      box; three-finger chords in Inversion Running and Jam; a full Voicings
      cycle on a guitar-captured shape; landscape phone; iPad; Mac window
      resized narrow and wide; left-handed flip; twin-dot modes; no silent
      notes anywhere on the neck.
- [ ] Piano regression pass: every drill, both orientations, since the
      surface wrapper now sits in front of `PianoKeyboard`.
- [ ] Beta build, then a note in project memory with what was confirmed.

## Open questions / risks
- **Landscape phones** (~26pt strings) are the remaining touch risk; Phase 1
  decides whether they get the box too.
- ~~**Inversion apex**~~: **settled in Phase 2.** It was not "for high keys",
  it was every key, so `guitarVoicingCycle` picks one octave for the whole
  cycle. The apex now always differs from root position.
- **Three-state dots on guitar** (off / primary / all) instead of the current
  on/off: the twin-mode setting in Phase 4 covers it globally; a per-drill
  three-state is v2 if anyone asks.
- **Stats and leaderboards** stay one pool across instruments. If guitar
  sessions turn out consistently slower, an instrument column on
  `mode_stats` is the fix, not now.
- **QA surface doubles permanently.** Six surfaces x two instruments, and
  every future drill inherits it. Known and accepted.
- **Store listing** still says "MIDI meets muscle memory" and the screenshots
  are all piano; refresh once guitar mode is confirmed on hardware.
