import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../midi/midi_service.dart';
import '../purchases/paywall_sheet.dart';
import '../purchases/purchase_service.dart';
import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';
import '../theory/voicings.dart';
import '../widgets/voicing_thumbnail.dart';
import 'voicing_capture_screen.dart';
import 'voicing_drill_screen.dart';

/// Section id for the Ungrouped bucket. Not a real folder — it owns no record,
/// it's just where voicings with no [VoicingSpec.folderId] collect.
const String _ungroupedId = '__ungrouped__';

/// The Voicings mode's home: the collection of shapes the user has built.
///
/// Unlike every other mode, the card on the home screen lands here rather than
/// straight in a drill — there's nothing to practise until you've built
/// something, so the list *is* the mode.
///
/// The list is organised three ways, all optional and all local: folders
/// (accordion sections, one folder per voicing at most), tags (one palette
/// colour plus any number of reusable text tags), and a search field that
/// matches names, tag labels and folder names.
class VoicingsScreen extends StatefulWidget {
  const VoicingsScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<VoicingsScreen> createState() => _VoicingsScreenState();
}

class _VoicingsScreenState extends State<VoicingsScreen> {
  final PurchaseService _purchases = PurchaseService.instance;
  final TextEditingController _search = TextEditingController();

  QuizSettings? _settings;

  /// Every voicing, in display order — folder by folder, Ungrouped last. The
  /// one source of order: sections are slices of this list, so a drag inside a
  /// section is a move inside this list and nothing else has to stay in sync.
  List<VoicingSpec> _voicings = const [];
  List<VoicingFolder> _folders = const [];
  List<VoicingTag> _tags = const [];

  /// Expanded section ids, or null for "never collapsed anything" — which
  /// reads as all expanded, including sections made after the fact.
  Set<String>? _expanded;

  String _query = '';
  final Set<int> _colorFilters = {};
  final Set<String> _tagFilters = {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _purchases.addListener(_onPurchasesChanged);
    _search.addListener(() {
      final q = _search.text.trim();
      if (q != _query) setState(() => _query = q);
    });
    _load();
  }

  @override
  void dispose() {
    _purchases.removeListener(_onPurchasesChanged);
    _search.dispose();
    super.dispose();
  }

  void _onPurchasesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final settings = _settings ?? await QuizSettings.load();
    final saved = await settings.savedVoicings();
    final folders = await settings.voicingFolders();
    final tags = await settings.voicingTags();
    final expanded = _expanded ?? await settings.expandedVoicingFolders();
    // Storage keeps whatever order the user last dragged; grouping re-slots a
    // voicing that changed folders. Written back only when it actually moved,
    // so a plain reload never touches prefs.
    final ordered = groupVoicings(saved, folders);
    if (!_sameOrder(saved, ordered)) await settings.reorderVoicings(ordered);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _voicings = ordered;
      _folders = folders;
      _tags = tags;
      _expanded = expanded;
      _loading = false;
    });
  }

  static bool _sameOrder(List<VoicingSpec> a, List<VoicingSpec> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  bool get _atFreeLimit =>
      !_purchases.isPro && _voicings.length >= QuizSettings.freeVoicingLimit;

  bool get _isFiltering =>
      _query.isNotEmpty || _colorFilters.isNotEmpty || _tagFilters.isNotEmpty;

  bool _isExpanded(String id) => _expanded?.contains(id) ?? true;

  String? _folderName(String? id) {
    if (id == null) return null;
    for (final f in _folders) {
      if (f.id == id) return f.name;
    }
    return null;
  }

  String? _tagLabel(String id) {
    for (final t in _tags) {
      if (t.id == id) return t.name;
    }
    return null;
  }

  /// Labels of [spec]'s tags, skipping ids whose tag has since been deleted.
  List<String> _labelsOf(VoicingSpec spec) =>
      [for (final id in spec.tagIds) ?_tagLabel(id)];

  // ---- Search and filters ------------------------------------------------

  /// Whether [spec] survives the search box and the filter chips. Search is a
  /// substring match on name, tag labels or folder name; the chips are OR
  /// within a kind (any of the picked colours) and AND across kinds.
  bool _matches(VoicingSpec spec) {
    if (_colorFilters.isNotEmpty && !_colorFilters.contains(spec.colorTag)) {
      return false;
    }
    if (_tagFilters.isNotEmpty &&
        !spec.tagIds.any((id) => _tagFilters.contains(id))) {
      return false;
    }
    return voicingMatchesQuery(
      spec,
      _query,
      tagLabels: _labelsOf(spec),
      folderName: _folderName(spec.folderId),
    );
  }

  List<VoicingSpec> get _results =>
      [for (final v in _voicings) if (_matches(v)) v];

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _colorFilters.clear();
      _tagFilters.clear();
    });
  }

  // ---- Actions -----------------------------------------------------------

  void _openDrill(VoicingSpec? spec) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoicingDrillScreen(midi: widget.midi, spec: spec),
      ),
    );
  }

  /// The free cap, enforced at the two places that would *add* a voicing.
  /// Going over the limit never deletes anything — a lapsed Pro user keeps
  /// every shape they built, they just can't make another until they're back.
  Future<bool> _clearedFreeLimit() async {
    if (!_atFreeLimit) return true;
    return PaywallSheet.show(context);
  }

  /// Open the builder and save whatever comes back. The capture screen owns
  /// the shape, this screen owns storage — so an abandoned capture (a pop with
  /// no spec) writes nothing.
  ///
  /// Editing is never gated: the cap is on *creating* voicings, and locking a
  /// user out of a shape they already own would be a different thing entirely.
  Future<void> _openCapture({VoicingSpec? existing}) async {
    if (existing == null && !await _clearedFreeLimit()) return;
    if (!mounted) return;
    final spec = await Navigator.of(context).push<VoicingSpec>(
      MaterialPageRoute(
        builder: (_) => VoicingCaptureScreen(
          midi: widget.midi,
          existing: existing,
          others: _voicings,
        ),
      ),
    );
    if (spec == null) return;
    // Capture only knows about the shape, so a save from the edit screen would
    // otherwise wipe the organisation fields off an existing voicing.
    final merged = existing == null
        ? spec
        : spec.copyWith(
            folderId: existing.folderId,
            colorTag: existing.colorTag,
            tagIds: existing.tagIds,
          );
    await _settings?.upsertVoicing(merged);
    await _load();
  }

  Future<void> _rename(VoicingSpec spec) async {
    final name = await _promptName(
      title: 'Rename voicing',
      initial: spec.name,
      action: 'Save',
    );
    if (name == null || name == spec.name) return;
    await _settings?.upsertVoicing(spec.copyWith(name: name));
    await _load();
  }

  Future<void> _duplicate(VoicingSpec spec) async {
    if (!await _clearedFreeLimit()) return;
    await _settings?.upsertVoicing(VoicingSpec.create(
      name: '${spec.name} copy',
      rootPc: spec.rootPc,
      offsets: spec.offsets,
      folderId: spec.folderId,
      colorTag: spec.colorTag,
      tagIds: spec.tagIds,
    ));
    await _load();
  }

  Future<void> _delete(VoicingSpec spec) async {
    final confirmed = await _confirm(
      title: 'Delete "${spec.name}"?',
      body: 'This voicing will be removed for good.',
      action: 'Delete',
    );
    if (confirmed != true) return;
    await _settings?.deleteVoicing(spec.id);
    await _load();
  }

  /// Persist a drag inside one section. The list is written optimistically so
  /// the card stays where the finger dropped it — reloading from prefs here
  /// would flash the old order for a frame.
  ///
  /// [start] is where the section begins in the flat list, so a section-local
  /// index needs only that offset. Uses `onReorderItem`, which already accounts
  /// for the dragged card being lifted out, so [newIndex] needs no off-by-one.
  Future<void> _reorder(int start, int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    setState(() {
      final all = [..._voicings];
      all.insert(start + newIndex, all.removeAt(start + oldIndex));
      _voicings = all;
    });
    await _settings?.reorderVoicings(_voicings);
  }

  // ---- Folders -----------------------------------------------------------

  Future<void> _toggleFolder(String id) async {
    final next = {..._expanded ?? _allSectionIds()};
    next.contains(id) ? next.remove(id) : next.add(id);
    setState(() => _expanded = next);
    await _settings?.setExpandedVoicingFolders(next);
  }

  Set<String> _allSectionIds() =>
      {for (final f in _folders) f.id, _ungroupedId};

  /// Create a folder and return it, or null if the user backed out. Shared by
  /// the app-bar button and the "New folder…" row in the move sheet.
  Future<VoicingFolder?> _newFolder() async {
    final name = await _promptName(
      title: 'New folder',
      hint: 'Folder name',
      action: 'Create',
    );
    if (name == null) return null;
    final folder = VoicingFolder.create(name);
    await _settings?.upsertVoicingFolder(folder);
    // A brand-new folder is expanded, even once the set has been materialised.
    if (_expanded != null) {
      final next = {..._expanded!, folder.id};
      _expanded = next;
      await _settings?.setExpandedVoicingFolders(next);
    }
    await _load();
    return folder;
  }

  Future<void> _renameFolder(VoicingFolder folder) async {
    final name = await _promptName(
      title: 'Rename folder',
      initial: folder.name,
      action: 'Save',
    );
    if (name == null || name == folder.name) return;
    await _settings?.upsertVoicingFolder(folder.renamed(name));
    await _load();
  }

  Future<void> _deleteFolder(VoicingFolder folder) async {
    final count = _voicings.where((v) => v.folderId == folder.id).length;
    final confirmed = await _confirm(
      title: 'Delete "${folder.name}"?',
      body: count == 0
          ? 'The folder will be removed.'
          : 'The folder will be removed. '
              '${count == 1 ? 'Its voicing moves' : 'Its $count voicings move'} '
              'to Ungrouped — nothing is deleted.',
      action: 'Delete folder',
    );
    if (confirmed != true) return;
    await _settings?.deleteVoicingFolder(folder.id);
    await _load();
  }

  Future<void> _moveToFolder(VoicingSpec spec) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetTitle('Move to folder'),
            ListTile(
              leading: const Icon(Icons.inbox_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Ungrouped'),
              trailing: spec.folderId == null
                  ? const Icon(Icons.check, color: AppColors.accent)
                  : null,
              onTap: () => Navigator.of(context).pop(_ungroupedId),
            ),
            for (final f in _folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined,
                    color: AppColors.textSecondary),
                title: Text(f.name),
                trailing: spec.folderId == f.id
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.of(context).pop(f.id),
              ),
            const Divider(height: 1, color: AppColors.border),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined,
                  color: AppColors.accent),
              title: const Text('New folder…'),
              onTap: () => Navigator.of(context).pop('new'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    var target = choice;
    if (choice == 'new') {
      final folder = await _newFolder();
      if (folder == null) return;
      target = folder.id;
    }
    if (target == _ungroupedId) {
      if (spec.folderId == null) return;
      await _settings?.upsertVoicing(spec.copyWith(clearFolder: true));
    } else {
      if (spec.folderId == target) return;
      await _settings?.upsertVoicing(spec.copyWith(folderId: target));
    }
    await _load();
  }

  /// Folder order gets its own sheet rather than a drag handle in the list:
  /// dragging a header inside a scroll view that already drags cards is a
  /// nest of reorderables, and this is one tap away.
  Future<void> _reorderFoldersSheet() async {
    final working = [..._folders];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetTitle('Reorder folders'),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: working.length,
                  onReorderItem: (o, n) =>
                      setSheet(() => working.insert(n, working.removeAt(o))),
                  itemBuilder: (context, i) => ListTile(
                    key: ValueKey(working[i].id),
                    leading: const Icon(Icons.folder_outlined,
                        color: AppColors.textSecondary),
                    title: Text(working[i].name),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle,
                          color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _settings?.reorderVoicingFolders(working);
    await _load();
  }

  // ---- Tags --------------------------------------------------------------

  Future<void> _openTagSheet(VoicingSpec spec) async {
    var colorTag = spec.colorTag;
    var tagIds = [...spec.tagIds];
    final field = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheet) {
              final query = field.text.trim();
              final suggestions = [
                for (final t in _tags)
                  if (query.isEmpty ||
                      t.name.toLowerCase().contains(query.toLowerCase()))
                    t,
              ];
              final exact = _tags.any(
                  (t) => t.name.toLowerCase() == query.toLowerCase());

              Future<void> createTag() async {
                if (query.isEmpty || exact) return;
                final tag = VoicingTag.create(query, prefix: 't');
                await _settings?.upsertVoicingTag(tag);
                final tags = await _settings?.voicingTags() ?? const [];
                field.clear();
                tagIds = [...tagIds, tag.id];
                if (!mounted) return;
                setState(() => _tags = tags);
                setSheet(() {});
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SheetTitle('Tag "${spec.name}"'),
                    const _SheetLabel('Colour'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var i = 0; i < kVoicingTagColors.length; i++)
                            _Swatch(
                              color: kVoicingTagColors[i],
                              label: kVoicingTagColorNames[i],
                              selected: colorTag == i,
                              // Tapping the live swatch clears it, so there's
                              // no separate "none" chip to hunt for.
                              onTap: () => setSheet(
                                  () => colorTag = colorTag == i ? null : i),
                            ),
                        ],
                      ),
                    ),
                    const _SheetLabel('Tags'),
                    if (_tags.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(
                          'No tags yet — type one below.',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in suggestions)
                            _TagChip(
                              label: t.name,
                              selected: tagIds.contains(t.id),
                              onTap: () => setSheet(() => tagIds.contains(t.id)
                                  ? tagIds.remove(t.id)
                                  : tagIds.add(t.id)),
                              // Long-press edits the library entry itself, so
                              // a typo is fixed everywhere at once.
                              onLongPress: () async {
                                await _editTag(t);
                                if (!mounted) return;
                                tagIds = [
                                  for (final id in tagIds)
                                    if (_tagLabel(id) != null) id,
                                ];
                                setSheet(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: field,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'New tag',
                                isDense: true,
                              ),
                              onChanged: (_) => setSheet(() {}),
                              onSubmitted: (_) => createTag(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed:
                                query.isEmpty || exact ? null : createTag,
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    field.dispose();
    if (colorTag != spec.colorTag ||
        !_sameIds(tagIds, spec.tagIds)) {
      await _settings?.upsertVoicing(spec.copyWith(
        colorTag: colorTag,
        clearColor: colorTag == null,
        tagIds: tagIds,
      ));
    }
    await _load();
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Rename or delete a library tag. A rename lands on every card carrying it;
  /// a delete strips it from every card, which is why it confirms first.
  Future<void> _editTag(VoicingTag tag) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetTitle('Tag "${tag.name}"'),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Rename tag'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.wrong),
              title: const Text('Delete tag',
                  style: TextStyle(color: AppColors.wrong)),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'rename') {
      final name = await _promptName(
        title: 'Rename tag',
        initial: tag.name,
        action: 'Save',
      );
      if (name == null || name == tag.name) return;
      await _settings?.upsertVoicingTag(tag.renamed(name));
    } else {
      final count = _voicings.where((v) => v.tagIds.contains(tag.id)).length;
      final confirmed = await _confirm(
        title: 'Delete "${tag.name}"?',
        body: count == 0
            ? 'The tag will be removed.'
            : 'The tag will be removed from '
                '${count == 1 ? '1 voicing' : '$count voicings'}. '
                'No voicing is deleted.',
        action: 'Delete tag',
      );
      if (confirmed != true) return;
      await _settings?.deleteVoicingTag(tag.id);
      _tagFilters.remove(tag.id);
    }
    await _load();
  }

  // ---- Shared dialogs ----------------------------------------------------

  Future<String?> _promptName({
    required String title,
    required String action,
    String? initial,
    String hint = 'Name',
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.wrong),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      );

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voicings'),
        actions: [
          if (!_loading && _voicings.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'New folder',
              onPressed: _newFolder,
            ),
            if (_folders.length > 1)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                color: AppColors.surfaceHigh,
                tooltip: 'List options',
                onSelected: (_) => _reorderFoldersSheet(),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      value: 'folders', child: Text('Reorder folders')),
                ],
              ),
          ],
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _voicings.isEmpty
                ? _buildEmpty()
                : _buildList(),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.piano_outlined,
                  size: 40, color: AppColors.accent),
            ),
            const SizedBox(height: 24),
            Text(
              'Build a voicing.\nDrill it in all 12 keys.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Play a chord shape, say which note is its root, and give it a '
              'name. Voicings then walks that exact shape through every key, '
              'at your own pace.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openCapture(),
                icon: const Icon(Icons.add),
                label: const Text('Create your first voicing'),
              ),
            ),
            const SizedBox(height: 8),
            // The cold-start answer: a custom-only mode opens empty, so let a
            // new user feel the drill before deciding what to build.
            TextButton(
              onPressed: () => _openDrill(null),
              child: const Text('Try a sample voicing first'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return Column(
      children: [
        _buildSearchBar(),
        _buildFilterBar(),
        Expanded(
          child: CustomScrollView(
            slivers: _isFiltering ? _resultSlivers() : _sectionSlivers(),
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search voicings, tags, folders',
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textMuted, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textMuted, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () => _search.clear(),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  /// One chip per colour and tag actually in use, so the row can't fill up
  /// with filters that would match nothing.
  Widget _buildFilterBar() {
    final colorsInUse = <int>{for (final v in _voicings) ?v.colorTag}.toList()
      ..sort();
    final tagsInUse = [
      for (final t in _tags)
        if (_voicings.any((v) => v.tagIds.contains(t.id))) t,
    ];
    if (colorsInUse.isEmpty && tagsInUse.isEmpty) return const SizedBox.shrink();
    final anyActive = _colorFilters.isNotEmpty || _tagFilters.isNotEmpty;

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        children: [
          if (anyActive)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.close, size: 16),
                label: const Text('Clear'),
                backgroundColor: AppColors.surfaceHigh,
                side: const BorderSide(color: AppColors.border),
                onPressed: () => setState(() {
                  _colorFilters.clear();
                  _tagFilters.clear();
                }),
              ),
            ),
          for (final i in colorsInUse)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: _colorFilters.contains(i),
                showCheckmark: false,
                avatar: CircleAvatar(
                    radius: 7, backgroundColor: kVoicingTagColors[i]),
                label: Text(kVoicingTagColorNames[i]),
                backgroundColor: AppColors.surface,
                selectedColor: AppColors.surfaceHigh,
                side: BorderSide(
                  color: _colorFilters.contains(i)
                      ? kVoicingTagColors[i]
                      : AppColors.border,
                ),
                onSelected: (on) => setState(
                    () => on ? _colorFilters.add(i) : _colorFilters.remove(i)),
              ),
            ),
          for (final t in tagsInUse)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: _tagFilters.contains(t.id),
                showCheckmark: false,
                label: Text(t.name),
                backgroundColor: AppColors.surface,
                selectedColor: AppColors.surfaceHigh,
                side: BorderSide(
                  color: _tagFilters.contains(t.id)
                      ? AppColors.accent
                      : AppColors.border,
                ),
                onSelected: (on) => setState(() =>
                    on ? _tagFilters.add(t.id) : _tagFilters.remove(t.id)),
              ),
            ),
        ],
      ),
    );
  }

  /// Searching flattens the accordion: one plain list, each card wearing its
  /// folder name, so a match is never hidden inside a collapsed section.
  List<Widget> _resultSlivers() {
    final results = _results;
    if (results.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off,
                    size: 36, color: AppColors.textMuted),
                const SizedBox(height: 12),
                const Text('No voicings match',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear search and filters'),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        sliver: SliverList.builder(
          itemCount: results.length,
          itemBuilder: (context, i) =>
              _buildCard(results[i], i, draggable: false, showFolder: true),
        ),
      ),
    ];
  }

  List<Widget> _sectionSlivers() {
    final slivers = <Widget>[];
    var start = 0;
    for (final f in _folders) {
      final items = _voicings.where((v) => v.folderId == f.id).toList();
      slivers.add(SliverToBoxAdapter(
        child: _buildFolderHeader(f, items.length),
      ));
      if (_isExpanded(f.id)) slivers.add(_sectionList(items, start));
      start += items.length;
    }

    final loose = _voicings.sublist(start);
    if (_folders.isEmpty) {
      // No folders: the list looks exactly as it did before this feature.
      slivers.add(_sectionList(loose, start));
    } else {
      slivers.add(SliverToBoxAdapter(
        child: _buildFolderHeader(null, loose.length),
      ));
      if (_isExpanded(_ungroupedId)) slivers.add(_sectionList(loose, start));
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    return slivers;
  }

  Widget _sectionList(List<VoicingSpec> items, int start) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverReorderableList(
        itemCount: items.length,
        onReorderItem: (o, n) => _reorder(start, o, n),
        onReorderStart: (_) => HapticFeedback.lightImpact(),
        proxyDecorator: _liftedCard,
        itemBuilder: (context, i) =>
            _buildCard(items[i], i, draggable: items.length > 1),
      ),
    );
  }

  /// [folder] null means the Ungrouped section.
  Widget _buildFolderHeader(VoicingFolder? folder, int count) {
    final id = folder?.id ?? _ungroupedId;
    final expanded = _isExpanded(id);
    return InkWell(
      onTap: () => _toggleFolder(id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 22),
            ),
            const SizedBox(width: 4),
            Icon(
              folder == null ? Icons.inbox_outlined : Icons.folder_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                folder?.name ?? 'Ungrouped',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
            if (folder != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz,
                    color: AppColors.textSecondary, size: 20),
                color: AppColors.surfaceHigh,
                tooltip: 'Folder options',
                onSelected: (action) => action == 'rename'
                    ? _renameFolder(folder)
                    : _deleteFolder(folder),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename folder')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete folder',
                        style: TextStyle(color: AppColors.wrong)),
                  ),
                ],
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    VoicingSpec spec,
    int index, {
    bool draggable = true,
    bool showFolder = false,
  }) {
    final color = spec.colorTag;
    final labels = _labelsOf(spec);
    final folder = showFolder ? _folderName(spec.folderId) : null;

    return InkWell(
      key: ValueKey(spec.id),
      onTap: () => _openDrill(spec),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        // The gap lives on the card: the reorderable list has no separator.
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        // The stripe is positioned rather than a Row child: the card's height
        // comes from its content, and a stretched Row child in a list has no
        // height to stretch to.
        child: Stack(
          children: [
            Padding(
                padding: EdgeInsets.fromLTRB(color == null ? 14 : 18, 14, 14, 14),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: VoicingThumbnail(spec: spec),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            spec.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${spec.rootName} · ${spec.formula} · '
                            '${spec.noteCount} notes'
                            '${folder == null ? '' : ' · $folder'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          if (labels.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _TagRow(labels: labels),
                          ],
                        ],
                      ),
                    ),
                    _buildMenu(spec),
                    if (draggable)
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.drag_handle,
                              color: AppColors.textMuted),
                        ),
                      ),
                  ],
                ),
            ),
            if (color != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: kVoicingTagColors[color]),
              ),
          ],
        ),
      ),
    );
  }

  /// Keeps the dragged card on the app's dark surface — the default proxy
  /// wraps the item in a themed [Material] that flashes light on lift.
  Widget _liftedCard(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Material(
        color: Colors.transparent,
        elevation: Curves.easeInOut.transform(animation.value) * 8,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      child: child,
    );
  }

  Widget _buildMenu(VoicingSpec spec) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      color: AppColors.surfaceHigh,
      tooltip: 'Voicing options',
      onSelected: (action) {
        switch (action) {
          case 'edit':
            _openCapture(existing: spec);
          case 'rename':
            _rename(spec);
          case 'tag':
            _openTagSheet(spec);
          case 'move':
            _moveToFolder(spec);
          case 'duplicate':
            _duplicate(spec);
          case 'delete':
            _delete(spec);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'tag', child: Text('Tag…')),
        const PopupMenuItem(value: 'move', child: Text('Move to folder…')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppColors.wrong)),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final count = _voicings.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openCapture(),
                icon: const Icon(Icons.add),
                label: const Text('New voicing'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _purchases.isPro
                  ? 'Pro · unlimited'
                  : '$count of ${QuizSettings.freeVoicingLimit} free',
              style: TextStyle(
                color: _atFreeLimit ? AppColors.accent2 : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// The card's tag chips: three at most, then a "+N" so a heavily tagged
/// voicing can't grow its card taller than its neighbours.
class _TagRow extends StatelessWidget {
  const _TagRow({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    const max = 3;
    final shown = labels.take(max).toList();
    final extra = labels.length - shown.length;
    return Row(
      children: [
        for (final l in shown)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _MiniChip(l),
            ),
          ),
        if (extra > 0) _MiniChip('+$extra'),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: FilterChip(
        selected: selected,
        showCheckmark: false,
        label: Text(label),
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.surfaceHigh,
        side: BorderSide(
            color: selected ? AppColors.accent : AppColors.border),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.textPrimary : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 18, color: AppColors.bg)
              : null,
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
