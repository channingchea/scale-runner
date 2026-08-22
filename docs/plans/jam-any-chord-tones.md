# Jam Mode "Any Chord Tones" Toggle — Implementation Plan

## Overview
A new toggle in the Chord families section of Jam Mode settings. When on, the
drill no longer demands a specific complete chord: any voicing built from the
prompted degree's stack tones (1, 2, 3, 4, 5, 7, 9 — i.e. triad + 7th + 9th +
sus tones) scores, as long as at least 3 keys are held (doubles count), the
lowest note is the chord root, and no out-of-stack note is sounding. The prompt
shows Roman numeral + root only (e.g. "ii — D"). Applies to both Prompted and
Freestyle. Inversions (wrong bass) judge as a miss; doubling any tone is always
fine. Note: the stack union covers 6 of the 7 in-key notes — the 9th shares the
2nd's pitch class — so the only invalid in-key note is the 6th above the root.

## Non-goals / Out of scope
- No changes to timing/BeatJudge, session length, or count-in.
- Per-quality weak-point stats are skipped for these bars (degree stats still
  count); no new "open" quality bucket.
- No changes to other modes (Scale Run, Voicings, Inversions, Quiz).

## Phase 1: Theory + settings plumbing
- [x] `jam_mode.dart`: `JamKey.stackPcs(degree)` — union of all family tones on
      a degree — plus `openChord(degree)` (name = root letter only, prompt
      "ii — D", formula "1-3-5-7-9 · sus"), `openPrompts()`, and
      `degreeOfRoot(pc)` for reading the bass in Freestyle.
- [x] `quiz_settings.dart`: `jam_any_tones` bool pref (default off) with
      getter/setter, next to `jamFamilies`.
- [x] Unit tests: stack union correct per degree (6 pcs, excludes the 6th),
      open-chord naming.

## Phase 2: Controller behavior
- [x] `JamModeController`: new `anyTones` flag.
- [x] Prompted pool = the 7 open chords (one per degree), same no-repeat picker.
- [x] Completeness: ≥3 held keys, all held pcs ⊆ stack pcs, lowest key's pitch
      class == prompted root. Wrong-note flash keys off the stack set.
- [x] Freestyle: recognize by bass — bass pc must be a diatonic root; all held
      pcs ⊆ that degree's stack; ≥3 keys; forbidden-degree repeat rule
      unchanged; live pill shows "ii — D".
- [x] Scoring: record degree tally only, skip quality tally.
- [x] Target dots: stack pcs of the current degree (Prompted); Freestyle keeps
      full-scale dots.
- [x] Unit tests: shell voicing hits, inversion = miss, doubles count toward
      the 3-note minimum, 2-note = not complete, out-of-stack note = wrong,
      freestyle recognition + repeat rule.

## Phase 3: Settings sheet UI + screen wiring
- [x] `jam_mode_settings_sheet.dart`: switch tile at the top of the Chord
      families section — "Any chord tones", subtitle explaining root-in-bass +
      3-note minimum. While on, the four family tiles render greyed out and
      non-tappable; the stored selection is untouched and comes back when
      toggled off.
- [x] `jam_mode_screen.dart`: read the pref, pass to the controller, rebuild on
      change (same path as the other settings).

## Phase 4: Verify
- [x] `flutter analyze` + `flutter test` via Desktop Commander.
- [ ] On-device sanity check (validation only — this change doesn't touch the
      beat clock).

## Open questions / risks
- Exact formula-line text when on ("1-3-5-7-9 · sus" vs something shorter) —
  cosmetic, easy to tweak.
