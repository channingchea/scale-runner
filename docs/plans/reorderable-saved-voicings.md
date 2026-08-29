# Reorderable Saved Voicings — Implementation Plan

## Overview
The Voicings list currently shows saved shapes in creation order with no way to
change it. This adds manual drag-to-reorder via a grip handle on each card,
persisting the order to `SharedPreferences`. The stored list is already an
ordered `StringList`, so no new storage key or sort field is needed — the list
order *is* the order.

## Non-goals / Out of scope
- Sort presets (by name, by date). Manual order only.
- Changing where new voicings land — they still append to the bottom.
- Pro gating. Reordering is available to everyone.
- Reordering anything else (Jam sets, drill history, etc.).

## Phase 1: Persist an explicit order
- [x] Add `Future<void> reorderVoicings(List<VoicingSpec> ordered)` to
      `QuizSettings` — a thin wrapper over the existing private
      `_writeVoicings`, so callers can hand back a whole re-sequenced list.
- [x] Confirm `upsertVoicing` still preserves position on edit/rename (it does —
      index-replace, not remove-and-append). No change needed, but cover it in a
      test alongside reorder.
- [x] Add tests in `test/voicing_settings_test.dart`: reorder round-trips
      through prefs; a reorder followed by an edit keeps the new position; a
      reorder followed by a delete keeps the rest in order.

## Phase 2: Drag-to-reorder in the list UI
- [x] Replace `ListView.separated` in `_buildList()` with
      `ReorderableListView.builder`, keyed by `ValueKey(spec.id)`.
- [x] `ReorderableListView` has no `separatorBuilder` — move the 12px gap into
      the card itself (bottom margin on the card `Container`) so spacing
      survives the swap.
- [x] Set `buildDefaultDragHandles: false` and wrap the grip in
      `ReorderableDragStartListener(index: i)`, so only the handle initiates a
      drag and tap-anywhere-to-drill is untouched.
- [x] Add the grip to `_buildCard`: `Icons.drag_handle` in
      `AppColors.textMuted`, at the right edge after the `⋮` menu.
- [x] Implement `_onReorder(oldIndex, newIndex)`: apply the standard
      `if (newIndex > oldIndex) newIndex--` correction, reorder `_voicings` in
      `setState` optimistically, then `await _settings?.reorderVoicings(...)` —
      no `_load()` afterwards, which would cause a visible re-fetch flicker.
- [x] Add a `proxyDecorator` so the lifted card keeps the app's dark
      `AppColors.surface` styling — the default proxy wraps items in a themed
      `Material` and can flash light on drop.

## Phase 3: Polish and verify
- [x] Hide the grip when `_voicings.length < 2` (nothing to reorder with one
      card).
- [x] Add `HapticFeedback.selectionClick()` on drag start for parity with the
      rest of the app's touch feedback.
- [x] Verify the free-tier footer count, `⋮` actions, and paywall path all still
      work after a reorder.
- [x] Run `flutter analyze` and the voicings test files (clean; 101 tests pass).
- [ ] Check drag feel on hardware (a 3-item free list and a longer Pro list).

## Open questions / risks
- `reorderVoicings` writes the whole list; `upsertVoicing` does a
  read-modify-write. Sequential `await`s in the screen mean no realistic race,
  but avoid firing a reorder and a save concurrently.
- A drag that starts and is then dropped in place still triggers `onReorder` on
  some platforms — the write is harmless but can be skipped with an early return
  when the index is unchanged.

## Implementation notes (2026-08-29)
- Flutter now deprecates `ReorderableListView.onReorder` in favour of
  `onReorderItem`, which pre-adjusts `newIndex` — the manual
  `if (newIndex > oldIndex) newIndex--` correction is *not* needed and would
  introduce an off-by-one. Same-index drops still short-circuit.
- Haptic on drag start is `HapticFeedback.lightImpact()`, matching
  `metronome_bar.dart`.
