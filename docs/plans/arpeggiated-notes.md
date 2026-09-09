# Arpeggiated Notes — Implementation Plan

## Overview
A global "Arpeggiated Notes" switch (default on) that lets on-screen players
build a chord one note at a time. Tapped notes latch instead of releasing, so
the Chords quiz, Inversion Running and the Voicings drill can be completed
without a MIDI instrument or a five-finger touch. MIDI input is untouched: a
real instrument still has to hold the notes. Applies to piano and guitar.

## Non-goals / Out of scope
- Scale Running and Jam Mode keep their live held-set judgment (their chord
  must be sounding on a downbeat; latching would blur the timing they score).
- No change to MIDI behavior, even when the switch is on.
- No per-mode override; one global switch.

## Phase 1: Setting + shared latch helper
- [ ] `quiz_settings.dart`: `arpeggiatedNotes()` / `setArpeggiatedNotes(bool)`
      on key `arpeggiated_notes`, default true.
- [ ] `settings_screen.dart`: switch tile in the Instrument section (shown for
      both instruments): title "Arpeggiated Notes", subtitle "Build chords one
      note at a time on the on-screen keys. Notes stay lit until the chord
      completes, a wrong note is played, or 2 seconds pass. MIDI instruments
      still hold every note."
- [ ] `lib/runner/note_latch.dart`: `NoteLatch` — a small helper the three
      controllers share. Holds the latched note set, the 2 s idle `Timer`
      (restarted on every latched press), `add(note)`, `toggle(note)` (a
      second tap on a latched key releases it), `clear()`, and an `onExpire`
      callback. `@visibleForTesting` clock injection via `package:clock` like
      MetronomeController so tests can fake the idle timeout.
- [ ] Guitar semantics: a string sounds one note, so a latched tap on an
      occupied string replaces that string's note (same rule as Voicing
      capture's `_tapCell`). Implement in the screens by switching the
      fretboard to its `onCellDown` capture path when the setting is on, and
      translating the resulting cell set into `pressKey`/`releaseKey` calls on
      the controller. Extract that cell-to-notes diff from
      `voicing_capture_screen.dart` into a reusable `GuitarLatch` so the three
      screens and Voicing capture share it.
- [ ] `test/note_latch_test.dart`: add/toggle/clear, idle expiry fires
      `onExpire` once, a new press restarts the timer; `GuitarLatch` string
      replacement and remove-on-second-tap.

## Phase 2: Chords quiz
- [ ] `QuizController.pressKey(note, {bool latch = false})`: when `latch` is
      true (screen passes `latch: arpeggiated` from `onKeyDown`; `bindMidi`
      never sets it) the note goes into the `NoteLatch` as well as `_held`;
      `releaseKey` skips notes the latch owns. Latch expiry clears its notes
      from `_held`, re-evaluates, and notifies.
- [ ] Wrong note: `_handleChordNotes` already flashes the offending keys and
      breaks the streak; add `latch.clear()` + `_held` purge after the
      450 ms flash so the player starts the chord over.
- [ ] Completion: `_win()` already holds on the green check; `_nextRound`
      clears `_held`, add `latch.clear()` there too.
- [ ] Scale quiz is sequential already and ignores the latch (the flag is only
      read in chord mode).
- [ ] `quiz_screen.dart`: read the setting in `_bootstrap`, pass `latch:` on
      `onKeyDown`, use `GuitarLatch` when the instrument is guitar, and
      re-read on settings changes like the other prefs.
- [ ] `home_screen.dart`: Chords subtitle becomes "Build the named chord,
      note by note or all at once".
- [ ] `test/quiz_controller_test.dart`: C then E then G completes C Major
      with the latch; C, E, F# flashes F# and resets; idle expiry resets an
      incomplete chord but never a completed round; MIDI notes still release
      normally with the setting on.

## Phase 3: Inversion Running + Voicings drill
- [ ] `InversionRunController.pressKey(note, {bool latch = false})` with the
      same `NoteLatch` wiring. `currentVoicingHeld` already reads `_held` and
      checks the lowest note as bass, so a latched C-E-G-C… sequence judges
      correctly. A press outside the chord is already flagged wrong
      (`_judgePress`); add the latch clear there. Line ~477 already clears
      `_held` when a round advances; clear the latch alongside it. Tempo mode:
      the completing press is what `_judgePress` times, unchanged.
- [ ] `VoicingRunController.pressKey(note, {bool latch = false})`: same
      wiring. `spec.matches` needs the exact note set with exact spacing, so
      the latch completes when the set matches; when the latched count reaches
      the shape's size without matching, flash the whole set wrong and clear.
      Out-of-key presses already flash and are ignored; clear the latch there.
- [ ] `inversion_run_screen.dart` / `voicing_drill_screen.dart`: same screen
      wiring as the quiz (setting read, `latch:` on taps, `GuitarLatch` on
      guitar).
- [ ] Tests in `inversion_run_controller_test.dart` and
      `voicing_run_controller_test.dart`: latched completion advances; wrong
      note clears; idle expiry clears; bass detection with latched notes; MIDI
      path unaffected.

## Phase 4: Verify
- [ ] `flutter analyze` + `flutter test` via Desktop Commander.
- [ ] On-device: iPhone piano and guitar with no MIDI (all three modes);
      macOS with mouse; then a MIDI keyboard connected to confirm nothing
      latches over MIDI.
- [ ] Log the milestone to project memory.

## Open questions / risks
- Latched keys show as `pressed` (the existing held color); a distinct latch
  color would make the state clearer but adds a `KeyFeedback` value that
  every surface must paint. Deferred unless testing shows confusion.
- The 2 s idle window is fixed. If testers find it too short on guitar, make
  it a constant first, a setting only if asked for.
- Voicing capture already latches on its own; it does not read this setting
  and does not need to.
