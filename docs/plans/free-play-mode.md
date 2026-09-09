# Free Play Mode — Implementation Plan

## Overview
A seventh home-screen mode, always free, that puts the instrument on screen
with no prompt, no scoring and no session. On piano, whatever is sounding is
named live in the prompt area: single notes by name, two notes as an interval,
three or more as a chord (extended quality set, slash notation for
inversions). Guitar gets the same screen with the naming readout left blank
for day one. The metronome bar is present as a plain practice click.

## Non-goals / Out of scope
- No chord/interval naming on the fretboard (day two; the namer is
  instrument-agnostic so only the guitar surface wiring is missing).
- No scoring, streak credit, stats, session summary or Pro gating.
- No timing judgment against the click (no BPM flash, no BeatJudge).
- No rootless voicings (every name needs its root sounding) and no
  polychords/upper-structure names.

## Phase 1: Chord namer (pure Dart, fully unit-tested)
- [x] `lib/theory/chord_namer.dart`: `ChordQuality(name, symbol, intervals)`
      table ordered by priority. Triads: Major, Minor, Diminished, Augmented,
      Sus2, Sus4. Sevenths: Major 7th, Dominant 7th, Minor 7th, Minor 7th
      flat 5, Diminished 7th, Minor Major 7th, Augmented 7th (7#5), Augmented
      Major 7th, 7sus4, 7sus2, Dominant 7th flat 5. Sixths: Major 6th, Minor
      6th, 6/9, Minor 6/9. Adds: Add9, Minor Add9, Add11, Minor Add11.
      Extended: Major 9th, Dominant 9th, Minor 9th, Minor Major 9th, 7b9, 7#9,
      Dominant 11th, Minor 11th, Dominant 13th, Major 13th, Minor 13th. Shell
      voicings (5th omitted) for Major 7th, Dominant 7th, Minor 7th, Dominant
      9th, Major 9th, Minor 9th, listed after their full forms.
- [x] `nameChord(Set<int> midiNotes) -> ChordName?`: reduce to pitch classes,
      bass = lowest note. Try each pitch class as root, bass first, then the
      rest ascending from the bass; a candidate matches when its interval set
      relative to that root equals a table entry exactly. First match wins.
      Result carries `rootPc`, `quality`, `bassPc`, `isSlash`
      (bass != root), `label` ("C Major 7th", "C Major 7th / E") and
      `formula` via `formulaOf` ("1-3-5-7").
- [x] `nameInterval(int low, int high) -> IntervalName`: semitone distance up
      to 24 named simply (Unison, Minor 2nd ... Major 7th, Octave, Minor 9th
      ... Major 14th, Two Octaves), beyond that reduce mod 12 and append
      "+ octaves". Tritone reads "Tritone". Label plus both note names
      ("C4 – E4") for the formula line.
- [x] `describeHeld(Set<int> midiNotes) -> Readout?`: 0 notes → null, 1 → note
      name, 2 distinct pitch classes → interval (doubled octaves of one pitch
      class → "Octave"), 3+ → chord or null when nothing matches (readout
      shows the note names instead so the area is never blank mid-chord).
- [x] `test/chord_namer_test.dart`: every quality in root position across all
      12 roots (loop, not hand-written); each inversion of the triads and
      sevenths reads as a slash; C6 vs Am7 resolves by bass (C in bass → C
      Major 6th, A in bass → A Minor 7th, E in bass → A Minor 7th / E, G in
      bass → C Major 6th / G); dim7 always names from the bass; all 25
      interval names; shell voicings; unmatched set → null.

## Phase 2: Controller + screen + home card
- [x] `lib/runner/free_play_controller.dart`: `FreePlayController` holds the
      live `_held` set fed by `pressKey`/`releaseKey` (taps) and `bindMidi`
      (same shape as QuizController). `readout` getter calls `describeHeld`.
      `feedbackFor` returns `pressed` for held notes, `idle` otherwise;
      `isTargetHint` always false. `onAnyPress` hook for note sound.
- [x] Arpeggiated Notes support: when the global setting is on, tapped notes
      latch (release does not remove them), tapping a latched key releases it,
      and 2 s with no new tap clears the latch. MIDI notes never latch. Same
      2 s idle timer as the Chords quiz (see [[arpeggiated-notes]]).
- [x] `lib/screens/free_play_screen.dart`: copy the QuizScreen bootstrap
      (settings, instrument, left-handed, twin mode, fret labels, note sound,
      wakelock, MIDI bind, latency refresh for the metronome). Layout: top bar
      = back, "Free Play" title, `MetronomeBar` (BPM persisted globally, no
      `registerHit`); prompt area = readout label + formula line, "Play
      anything" placeholder when nothing is held; bottom = `InstrumentSurface`.
- [x] Piano range: `kVoicingKeyboardLow`..`kVoicingKeyboardHigh` (48–84, three
      octaves) like Voicing capture, since no prompt limits the span.
- [x] Guitar: `InstrumentSurface` with `box` = the same 5-fret window and fret
      stepper Voicing capture uses so the player can move up the neck; prompt
      area shows the "Play anything" placeholder only (no naming on day one).
- [x] `home_screen.dart`: `_ModeCard` "Free Play", subtitle "Play anything.
      Chords and intervals are named as you play them", first card above
      Scales, `onTap` pushes `FreePlayScreen(midi:)` with no gating. Icon:
      new `assets/icon/Icon_FreePlay.png` (needs artwork; reuse
      `Icon_Chords.png` until it exists).
- [x] `welcome_sheet.dart` / How-it-works copy: one line for Free Play.
- [x] `test/free_play_controller_test.dart`: readout follows held set; MIDI
      and taps merge; latch behavior with the setting on/off; release clears
      readout.

## Phase 3: Verify
- [x] `flutter analyze` + `flutter test` via Desktop Commander (558 → 595 tests, all green).
- [ ] On-device: iPhone (multi-touch chords, portrait + landscape), macOS
      (mouse + arpeggiated latch, MIDI keyboard live naming).
- [x] Log the milestone to project memory.

## Open questions / risks
- Free Play does not call `StreakService.recordPractice`, so noodling does not
  keep the daily streak alive. Flip this if you want it to count.
- Name style is the app's word style ("C Minor 7th flat 5") to match the
  Chords quiz prompts; a compact symbol style ("Cm7b5") could be a later
  setting.
- Free Play honoring Arpeggiated Notes is a design call made here so mouse
  users on macOS can build chords; say so if you would rather Free Play always
  read live held notes only.
- Naming beyond the table (9ths with omitted 3rds, altered 13ths) shows note
  names rather than a guess. Easy to extend the table later; every addition
  is one line plus the looped test.

## Built 2026-09-08 — what differs from the plan above
- Top bar has no "Free Play" title: none of the other five mode screens carry
  one, so it keeps their row (back, metronome, MIDI status).
- Slash-chord root choice: after the bass fails as root, other roots are tried
  by the interval from root up to the bass, 5th first, then 3rd, then 7th
  (`_bassIntervalPriority` in `chord_namer.dart`). That is what makes E-G-A-C
  read "A Minor 7th / E" and G-A-C-E read "C Major 6th / G". Enharmonic twins
  (Cm7/Eb = Eb Major 6th, Csus2/G = G Sus4, Cm6/A = A Minor 7th flat 5) name
  from the bass by design.
- `QuizSettings.arpeggiatedNotes()` exists now (key `arpeggiated_notes`,
  default on) so Free Play can honor it; the Settings switch and the other
  drills' latching land with the Arpeggiated Notes plan.
- Guitar taps stay live (no latch) since nothing is named there yet. Flip
  `_namesNotes` in `free_play_screen.dart` to light the readout on day two.
- The fret-window control moved into a shared `FretBoxStepper` widget
  (`lib/widgets/fret_box_stepper.dart`); Voicing capture uses it too.
- No input-latency refresh: the metronome is a plain click here, nothing
  judges presses against it.
- Still to do on hardware: iPhone multi-touch chords (portrait + landscape),
  macOS mouse latch + a MIDI keyboard. `Icon_FreePlay.png` artwork still
  needed (card reuses `Icon_Chords.png`).
