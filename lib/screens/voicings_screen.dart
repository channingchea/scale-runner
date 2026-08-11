import 'package:flutter/material.dart';

import '../midi/midi_service.dart';
import '../purchases/paywall_sheet.dart';
import '../purchases/purchase_service.dart';
import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';
import '../theory/voicings.dart';
import '../widgets/voicing_thumbnail.dart';
import 'voicing_capture_screen.dart';
import 'voicing_drill_screen.dart';

/// The Voicings mode's home: the collection of shapes the user has built.
///
/// Unlike every other mode, the card on the home screen lands here rather than
/// straight in a drill — there's nothing to practise until you've built
/// something, so the list *is* the mode.
class VoicingsScreen extends StatefulWidget {
  const VoicingsScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<VoicingsScreen> createState() => _VoicingsScreenState();
}

class _VoicingsScreenState extends State<VoicingsScreen> {
  final PurchaseService _purchases = PurchaseService.instance;
  QuizSettings? _settings;
  List<VoicingSpec> _voicings = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _purchases.addListener(_onPurchasesChanged);
    _load();
  }

  @override
  void dispose() {
    _purchases.removeListener(_onPurchasesChanged);
    super.dispose();
  }

  void _onPurchasesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final settings = _settings ?? await QuizSettings.load();
    final saved = await settings.savedVoicings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _voicings = saved;
      _loading = false;
    });
  }

  bool get _atFreeLimit =>
      !_purchases.isPro && _voicings.length >= QuizSettings.freeVoicingLimit;

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
    await _settings?.upsertVoicing(spec);
    await _load();
  }

  Future<void> _rename(VoicingSpec spec) async {
    final controller = TextEditingController(text: spec.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Rename voicing'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == spec.name) return;
    await _settings?.upsertVoicing(spec.copyWith(name: name));
    await _load();
  }

  Future<void> _duplicate(VoicingSpec spec) async {
    if (!await _clearedFreeLimit()) return;
    await _settings?.upsertVoicing(VoicingSpec.create(
      name: '${spec.name} copy',
      rootPc: spec.rootPc,
      offsets: spec.offsets,
    ));
    await _load();
  }

  Future<void> _delete(VoicingSpec spec) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete "${spec.name}"?'),
        content: const Text('This voicing will be removed for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.wrong),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _settings?.deleteVoicing(spec.id);
    await _load();
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voicings')),
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
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: _voicings.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _buildCard(_voicings[i]),
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildCard(VoicingSpec spec) {
    return InkWell(
      onTap: () => _openDrill(spec),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
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
                    '${spec.noteCount} notes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            _buildMenu(spec),
          ],
        ),
      ),
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
          case 'duplicate':
            _duplicate(spec);
          case 'delete':
            _delete(spec);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
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
