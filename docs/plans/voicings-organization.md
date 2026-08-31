# Voicings Organization — Implementation Plan

## Overview
Voicings mode's list currently supports drag-to-reorder only. This adds three organizing
layers on top: **folders** (accordion sections, one folder max per voicing plus an Ungrouped
section), **tags** (one palette color + multiple reusable text tags, applied from the card's
dot menu), and a **search field** at the top of the page that matches voicing names, tag
labels and folder names. All free — no Pro gating.

## Non-goals / Out of scope
- Nested folders (folders inside folders)
- Multiple folders per voicing
- Multiple colors per voicing
- Custom color picker (fixed 8-swatch palette only)
- Drag-and-drop between folders (moving is menu-driven)
- Syncing folders/tags across devices (SharedPreferences stays local, same as today)

## Phase 1: Data model & storage
- [x] Add `folderId` (`String?`), `colorTag` (`int?`, index into a fixed palette), and
      `tagIds` (`List<String>`) to `VoicingSpec` in `lib/theory/voicings.dart`; extend
      `encode()`/`decode()` to read/write `'folder'`, `'color'`, `'tags'`, tolerating their
      absence so existing saved voicings decode unchanged
- [x] Extend `copyWith` to cover the three new fields, with explicit-null handling so
      "remove from folder" / "clear color" can be expressed
- [x] Add `const List<Color> kVoicingTagColors` — 8 swatches tuned for the dark theme — to
      `lib/theme/app_theme.dart`
- [x] Add `VoicingFolder { String id, String name }` with `encode()`/`decode()` in
      `voicings.dart`; list order = display order
- [x] Add `VoicingTag { String id, String label }` with `encode()`/`decode()` — IDs on the
      spec, labels in one library, so renaming a tag updates every card at once
- [x] In `lib/quiz/quiz_settings.dart`, add keys `voicing_folders`, `voicing_tags`,
      `voicing_expanded_folders`, plus: `voicingFolders()`, `upsertVoicingFolder()`,
      `deleteVoicingFolder(id)` (reassigns member voicings to `folderId = null`),
      `reorderVoicingFolders()`, `voicingTags()`, `upsertVoicingTag()`,
      `deleteVoicingTag(id)` (strips the id from every spec), `expandedVoicingFolders()` /
      `setExpandedVoicingFolders()`
- [x] Keep the single flat ordered voicing list as the source of order; sections derive from
      it by grouping on `folderId` while preserving relative order — no per-folder order key
- [x] Unit tests in `test/voicings_test.dart`: round-trip encode/decode with and without the
      new fields, legacy line decodes with null folder/color/empty tags
- [x] Unit tests in `test/voicing_settings_test.dart`: folder delete orphans to Ungrouped,
      tag delete strips ids

## Phase 2: Folders UI
- [x] Replace the single `ReorderableListView` in `lib/screens/voicings_screen.dart` with a
      `CustomScrollView`: one header sliver + one `SliverReorderableList` per folder, then
      the Ungrouped section last
- [x] Folder header: chevron, name, count badge, tap to expand/collapse; expansion state
      persisted via `setExpandedVoicingFolders`
- [x] Header dot menu: Rename folder, Delete folder (confirm — "Voicings inside move to
      Ungrouped")
- [x] "New folder" action in the app bar (`Icons.create_new_folder_outlined`) → name dialog
- [x] Add `Move to folder…` to the card's `PopupMenuButton`; bottom sheet listing folders +
      "Ungrouped" + "New folder…", with a check on the current one
- [x] Reorder handler maps a section-local `(oldIndex, newIndex)` back to an index in the
      flat list before calling `reorderVoicings`
- [x] ~~Folder reordering via an app-bar sheet~~ — **superseded 2026-08-30**: folder headers
      now carry their own grip and drag in place, like the cards. Folders are one outer
      `SliverReorderableList` whose items are `header + that folder's card list`; each
      section's cards live in an inner shrink-wrapped `ReorderableListView`. A card's grip is
      inside the inner list and a header's is not, so each binds to the right list. Dragging a
      folder regroups the flat voicing list behind it, so a section's cards move with it.
      Ungrouped sits outside the outer list and stays last. The sheet is gone.
- [x] Ungrouped section renders headerless when no folders exist, so a user who never makes
      one sees today's list exactly

## Phase 3: Tags
- [x] Add `Tag…` to the card's dot menu → tag sheet with an 8-swatch color row (tap the
      active swatch to clear) and a text-tag section listing library tags as toggleable chips
      plus a "New tag" field with autocomplete against the library
- [x] Tag sheet supports editing: rename a library tag (updates everywhere) or delete it
      (strips it from every voicing, with confirm)
- [x] Card rendering in `_buildCard`: 4px color stripe on the leading edge when
      `colorTag != null`; text tags as compact chips in a wrapping row under the formula
      line, capped at ~3 visible with a "+N" overflow chip
- [x] Card height stays stable when a voicing has no tags — the chip row only occupies space
      when non-empty

## Phase 4: Search & tag filter
- [x] Persistent search `TextField` pinned above the list (magnifier prefix, clear "×"
      suffix), hidden in the empty state
- [x] Filter row under it: horizontally scrolling chips for each color and text tag in use;
      tap toggles, tap again untoggles, leading "Clear" chip resets every active filter
- [x] Search matches, case-insensitively: voicing name, its tag labels, and its folder name
      (a folder-name match surfaces its contents)
- [x] While search or a filter is active, the accordion flattens to one plain list, each card
      showing a small folder name under the formula line
- [x] Empty result state: "No voicings match" with a button that clears search + filters
- [x] Clearing the search restores the previous accordion expansion state

## Phase 5: Verification
- [x] `flutter analyze` and `flutter test` (via Desktop Commander)
- [ ] Manual pass on hardware: create/rename/delete a folder, move voicings in and out,
      confirm delete-folder orphans rather than destroys, reorder within a folder and across
      folder order, tag with color + text, rename a tag and confirm every card updates,
      search by all three fields, toggle and clear filters
- [ ] Confirm a pre-upgrade install with saved voicings loads them intact (legacy JSON lines
      with no folder/color/tags)

## Open questions / risks
- ~~**Nested reorderables**~~ — resolved 2026-08-30. The nesting works and is covered by
  widget tests that perform real drags at both levels. One thing to watch on hardware: a
  dragged folder's proxy includes its cards, so dragging an expanded folder holding many
  voicings lifts a tall block. Collapse it first if that feels unwieldy.
- **Free limit + folders**: the "3 of 3 free" footer stays a global count, not per folder.
- **Tag library growth**: no auto-pruning of tags no voicing uses — they stay until deleted
  manually.
