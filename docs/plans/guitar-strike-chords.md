# Guitar Strike Chords — Implementation Plan

## Overview
In Scale Running with Chords on, the chord is judged by sampling what's still held when beat 0 ends. On guitar that's unplayable: the fretboard's one-finger-per-string rule blocks run notes on occupied strings, and a guitarist can't hold a voicing and pick a line anyway. This makes guitar judge the chord by what *sounded* during the beat-0 window instead — strike the tones (one at a time is fine), they stay lit where tapped through beat 0, then the run proceeds. Piano is untouched.

## Non-goals / Out of scope
- Piano / MIDI keyboard hold rule — unchanged.
- Gating by the Arpeggiated Notes setting — the strike rule is simply how guitar works here.
- Partial shapes (root+one, root only) — every chord tone still required.
- Separate chord-accuracy line in the session summary.
- Count-in strikes beyond the existing early-hit tolerance.

## Phase 1: Controller strike rule (`lib/runner/scale_run_controller.dart`)
- [x] Add `enum ChordRule { hold, strike }`; a `chordRule` field on `ScaleRunController`, default `hold`, settable while idle (same pattern as `beatsPerBar`).
- [x] Add `_chordStruck` (pitch classes sounded in this bar's beat-0 window) and `_chordStruckNext` (early strikes for the next bar). Clear/promote wherever a bar's beat 0 begins: the downbeat branch of `onBeat` and the rollover in `_advance`. Clear both in `reset`/`stop` and `_enterKeyCountIn`.
- [x] In strike mode: a press whose pitch class is in `currentStep.chordPcs` adds to `_chordStruck` if `_beatIndex == 0` and not early; adds to `_chordStruckNext` if judged early for the next bar's beat 0 (beat 7 early, or the last count-in window). Factor a `_nextStep` helper out of `_expectedPcAt`.
- [x] `chordHeldCorrectly`: in strike mode return `chordPcs.every(_chordStruck.contains)`. Keep the name; update the doc.
- [x] Add `_latched` + `latchedNotes`, and `tapCell(int midiNote)`: normal press judgment; a chord tone inside the strike window stays in `_held` (lit), anything else is released immediately. Second tap on a latched note is a no-op. `releaseKey` skips latched notes. On every beat-0 → beat-1 transition drop the latched notes.
- [x] `isTargetHint`: in strike mode, chord tones hint only while counting in or on beat 0.
- [x] Controller tests: all tones struck one-by-one → correct; one missing → miss; release doesn't matter; early strike on beat 7 credits the next chord and the next key across a count-in; struck set clears at rollover; `tapCell` latches only chord tones in the window; latched notes drop on the beat-1 tick; hint dots hide chord tones from beat 1 on. Hold-mode tests stay green.

## Phase 2: Guitar wiring (`lib/screens/scale_run_screen.dart`)
- [x] When the instrument resolves, set `c.chordRule = guitar ? strike : hold`; re-apply if the instrument setting changes while idle.
- [x] `_struckCells` state; guitar passes `onCellDown` → `c.tapCell(cell.midi())` and syncs cells against `c.latchedNotes`; `latched: _struckCells`. Piano keeps `onKeyDown`/`onKeyUp`.
- [x] Drop stale cells in the controller listener so the neck unlights on the beat-1 tick.
- [x] `_buildChordIndicator` doc comment.
- [x] Copy: `mode_guides.dart` Scale Running line → instrument-neutral; `scale_run_screen.dart` header comment.
- [x] Widget test (guitar): wiring only — cell mode + `latched` set on guitar, press/hold on piano, strike vs hold copy (`test/scale_run_guitar_strike_test.dart`). Driving the drill in a widget test needs the metronome's audio players, so the lit-through-beat-0 / clear-on-beat-1 behaviour is covered at controller level (`tapCell` tests) plus hardware QA.

## Phase 3: Verify and log
- [x] `flutter test` full suite; `flutter analyze` clean. No `dart format` on existing files.
- [ ] Hardware QA on a phone: guitar + Chords + sevenths, odd meter, through a key change.
- [x] Commit as one change; log to project memory. (724 tests, analyze clean apart from a pre-existing warning in `Claude outputs/`.)

## Open questions / risks
- `_nextStep` refactor of `_expectedPcAt` is the one place existing early-hit behaviour could regress; existing tests cover it.
- MIDI guitar uses `pressKey`/`releaseKey`: strikes count, nothing latches — correct.
- `boxAtRoot(c.keyPc)` unchanged; shapes outside the box are a separate UX question.
