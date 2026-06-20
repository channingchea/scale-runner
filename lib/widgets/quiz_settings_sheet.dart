import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theory/music_theory.dart';
import '../quiz/quiz_controller.dart';
import '../quiz/quiz_settings.dart';

/// A bottom sheet that lets the user toggle which scale/chord types appear in
/// the quiz. Persists changes immediately and calls [onChanged] so the quiz
/// can rebuild with the new selection. At least one item must stay enabled.
class QuizSettingsSheet extends StatefulWidget {
  const QuizSettingsSheet({
    super.key,
    required this.mode,
    required this.settings,
    required this.onChanged,
    required this.onFormulaHintChanged,
    required this.onDotsHintChanged,
    required this.onStatsBarChanged,
    required this.onBeatIndicatorChanged,
    required this.onNoteSoundChanged,
    required this.onResetStats,
  });

  final QuizMode mode;
  final QuizSettings settings;

  /// Called whenever the enabled set changes (with the new set of names).
  final ValueChanged<Set<String>> onChanged;

  /// Called whenever the formula-hint toggle changes.
  final ValueChanged<bool> onFormulaHintChanged;

  /// Called whenever the keyboard-dots toggle changes.
  final ValueChanged<bool> onDotsHintChanged;

  /// Called whenever the stats-bar toggle changes.
  final ValueChanged<bool> onStatsBarChanged;

  /// Called whenever the metronome beat-indicator toggle changes.
  final ValueChanged<bool> onBeatIndicatorChanged;

  /// Called whenever the note-sound toggle changes.
  final ValueChanged<bool> onNoteSoundChanged;

  /// Called when the user confirms a stats reset.
  final VoidCallback onResetStats;

  /// Convenience opener.
  static Future<void> show(
    BuildContext context, {
    required QuizMode mode,
    required QuizSettings settings,
    required ValueChanged<Set<String>> onChanged,
    required ValueChanged<bool> onFormulaHintChanged,
    required ValueChanged<bool> onDotsHintChanged,
    required ValueChanged<bool> onStatsBarChanged,
    required ValueChanged<bool> onBeatIndicatorChanged,
    required ValueChanged<bool> onNoteSoundChanged,
    required VoidCallback onResetStats,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => QuizSettingsSheet(
        mode: mode,
        settings: settings,
        onChanged: onChanged,
        onFormulaHintChanged: onFormulaHintChanged,
        onDotsHintChanged: onDotsHintChanged,
        onStatsBarChanged: onStatsBarChanged,
        onBeatIndicatorChanged: onBeatIndicatorChanged,
        onNoteSoundChanged: onNoteSoundChanged,
        onResetStats: onResetStats,
      ),
    );
  }

  @override
  State<QuizSettingsSheet> createState() => _QuizSettingsSheetState();
}

class _QuizSettingsSheetState extends State<QuizSettingsSheet> {
  late List<String> _all;
  Set<String> _enabled = {};

  /// Scale rows whose formula panel is currently slid open (by scale name).
  final Set<String> _formulaOpen = {};

  bool _formulaHint = true;
  bool _dotsHint = true;
  bool _statsBar = true;
  bool _beatIndicator = true;
  bool _noteSound = true;
  bool _loading = true;

  bool get _isScale => widget.mode == QuizMode.scale;

  @override
  void initState() {
    super.initState();
    _all = QuizSettings.allNames(widget.mode);
    _init();
  }

  Future<void> _init() async {
    final enabled = await widget.settings.enabledNames(widget.mode);
    final formulaHint = await widget.settings.formulaHintEnabled(widget.mode);
    final dotsHint = await widget.settings.dotsHintEnabled(widget.mode);
    final statsBar = await widget.settings.statsBarEnabled(widget.mode);
    final beatIndicator =
        await widget.settings.beatIndicatorEnabled(widget.mode);
    final noteSound = await widget.settings.noteSoundEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _formulaHint = formulaHint;
      _dotsHint = dotsHint;
      _statsBar = statsBar;
      _beatIndicator = beatIndicator;
      _noteSound = noteSound;
      _loading = false;
    });
  }

  Future<void> _toggleFormulaHint(bool on) async {
    setState(() => _formulaHint = on);
    await widget.settings.setFormulaHintEnabled(widget.mode, on);
    widget.onFormulaHintChanged(on);
  }

  Future<void> _toggleDotsHint(bool on) async {
    setState(() => _dotsHint = on);
    await widget.settings.setDotsHintEnabled(widget.mode, on);
    widget.onDotsHintChanged(on);
  }

  Future<void> _toggleStatsBar(bool on) async {
    setState(() => _statsBar = on);
    await widget.settings.setStatsBarEnabled(widget.mode, on);
    widget.onStatsBarChanged(on);
  }

  Future<void> _toggleBeatIndicator(bool on) async {
    setState(() => _beatIndicator = on);
    await widget.settings.setBeatIndicatorEnabled(widget.mode, on);
    widget.onBeatIndicatorChanged(on);
  }

  Future<void> _toggleNoteSound(bool on) async {
    setState(() => _noteSound = on);
    await widget.settings.setNoteSoundEnabled(on);
    widget.onNoteSoundChanged(on);
  }

  OverlayEntry? _toast;
  Timer? _toastTimer;

  /// Shows a brief toast in the root overlay, which paints above every route —
  /// including this modal sheet. (A SnackBar lives in the root Scaffold, so it
  /// would render *behind* the sheet.)
  void _showToast(String message) {
    _toast?.remove();
    _toastTimer?.cancel();
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 12),
                ],
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    _toast = entry;
    _toastTimer = Timer(const Duration(seconds: 2), () {
      entry.remove();
      if (_toast == entry) _toast = null;
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _toast?.remove();
    super.dispose();
  }

  Future<void> _toggle(String name, bool on) async {
    // Never allow the last enabled item to be turned off.
    if (!on && _enabled.length == 1 && _enabled.contains(name)) {
      _showToast('Keep at least one selected');
      return;
    }
    setState(() {
      if (on) {
        _enabled.add(name);
      } else {
        _enabled.remove(name);
      }
    });
    await widget.settings.setEnabledNames(widget.mode, _enabled);
    widget.onChanged(_enabled);
  }

  Future<void> _setAll(bool on) async {
    setState(() => _enabled = on ? _all.toSet() : {_all.first});
    await widget.settings.setEnabledNames(widget.mode, _enabled);
    widget.onChanged(_enabled);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    heightFactor: 1, child: CircularProgressIndicator()),
              )
            : DefaultTabController(
                length: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _grabber(),
                    _title(),
                    const TabBar(
                      labelColor: AppColors.textPrimary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.accent,
                      tabs: [
                        Tab(text: 'Practice'),
                        Tab(text: 'Challenge'),
                      ],
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Flexible(
                      child: TabBarView(
                        children: [
                          _practiceTab(),
                          _challengeTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _grabber() => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _title() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _isScale ? 'Scale practice' : 'Chord practice',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ),
      );

  Widget _practiceTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_enabled.length} of ${_all.length} selected',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              TextButton(onPressed: () => _setAll(true), child: const Text('All')),
              TextButton(
                  onPressed: () => _setAll(false), child: const Text('None')),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: _isScale ? _groupedScaleTiles() : _flatTiles(_all),
          ),
        ),
      ],
    );
  }

  /// Scale names grouped by parent scale and ordered by mode (scale degree).
  /// Names must match those in `commonScales`; any not listed here fall into the
  /// trailing "Other Scales" group so nothing is dropped.
  static const List<String> _majorScaleModes = [
    'Major (Ionian)',
    'Dorian',
    'Phrygian',
    'Lydian',
    'Mixolydian',
    'Aeolian (Natural Minor)',
    'Locrian',
  ];
  static const List<String> _harmonicMinorModes = [
    'Harmonic Minor',
    'Locrian ♮6',
    'Ionian #5 (Augmented Major)',
    'Dorian #4 (Ukrainian Dorian)',
    'Phrygian Dominant',
    'Lydian #2',
    'Ultralocrian (Altered Diminished)',
  ];
  static const List<String> _melodicMinorModes = [
    'Melodic Minor (asc)',
    'Dorian b2 (Phrygian ♮6)',
    'Lydian Augmented',
    'Lydian Dominant',
    'Mixolydian b6',
    'Locrian ♮2 (Half-Diminished)',
    'Altered (Super Locrian)',
  ];

  List<Widget> _groupedScaleTiles() {
    final known = {
      ..._majorScaleModes,
      ..._harmonicMinorModes,
      ..._melodicMinorModes,
    };
    final other = _all.where((n) => !known.contains(n)).toList();
    return [
      _scaleGroup('Major Scale', _majorScaleModes),
      _scaleGroup('Harmonic Minor Scale', _harmonicMinorModes),
      _scaleGroup('Melodic Minor Scale', _melodicMinorModes),
      if (other.isNotEmpty) _scaleGroup('Other Scales', other),
    ];
  }

  /// One collapsible accordion group: a parent scale with its modes as toggles.
  /// The header shows how many of the group's scales are enabled. Collapsed by
  /// default to keep the list compact and easy to scan.
  Widget _scaleGroup(String title, List<String> names) {
    final present = names.where(_all.contains).toList();
    final on = present.where(_enabled.contains).length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        iconColor: AppColors.textSecondary,
        collapsedIconColor: AppColors.textSecondary,
        title: Text(
          title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '$on of ${present.length} on',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        children: _flatTiles(present),
      ),
    );
  }

  List<Widget> _flatTiles(Iterable<String> names) => [
        for (final name in names) _scaleTile(name),
      ];

  /// A scale row: name + a "?" info button + the on/off switch. Tapping "?"
  /// slides a formula panel open beneath the row (same motion as the
  /// metronome's expand). Only scales have a known formula; chords show none.
  Widget _scaleTile(String name) {
    final formula = _formulaFor(name);
    final open = _formulaOpen.contains(name);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(
            name,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (formula != null)
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 20),
                  color: open ? AppColors.accent : AppColors.textSecondary,
                  tooltip: 'Show formula',
                  onPressed: () => setState(() =>
                      open ? _formulaOpen.remove(name) : _formulaOpen.add(name)),
                ),
              Switch(
                value: _enabled.contains(name),
                onChanged: (v) => _toggle(name, v),
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.accent,
                inactiveThumbColor: AppColors.textMuted,
                inactiveTrackColor: AppColors.surfaceHigh,
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: (open && formula != null)
              ? _formulaPanel(formula)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _formulaPanel(String formula) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Text('Formula',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                formula,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabularFigures),
              ),
            ),
          ],
        ),
      );

  /// Degree formula for a scale name, or null if it isn't a known scale.
  String? _formulaFor(String name) {
    for (final s in commonScales) {
      if (s.name == name) return s.formula;
    }
    return null;
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _sectionDivider() => const Divider(
        height: 16,
        thickness: 1,
        indent: 20,
        endIndent: 20,
        color: AppColors.border,
      );

  Widget _challengeTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _sectionHeader('Hints'),
        _hintSwitch(
          value: _formulaHint,
          onChanged: _toggleFormulaHint,
          title: 'Show formula',
          subtitle: 'The degree formula under the scale/chord name',
        ),
        _hintSwitch(
          value: _dotsHint,
          onChanged: _toggleDotsHint,
          title: 'Show key dots',
          subtitle: 'The blue dots marking which keys to play',
        ),
        _sectionDivider(),
        _sectionHeader('Performance'),
        _hintSwitch(
          value: _statsBar,
          onChanged: _toggleStatsBar,
          title: 'Show stats bar',
          subtitle: 'The score, streak, and best row at the top',
        ),
        _hintSwitch(
          value: _beatIndicator,
          onChanged: _toggleBeatIndicator,
          title: 'Beat indicator',
          subtitle:
              'Flash the metronome BPM green/amber/red with your key timing',
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt, color: AppColors.textSecondary),
          title: const Text(
            'Reset stats',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          ),
          subtitle: const Text(
            'Set score and best streak back to zero',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          onTap: _confirmResetStats,
        ),
        _sectionDivider(),
        _sectionHeader('Sound'),
        _hintSwitch(
          value: _noteSound,
          onChanged: _toggleNoteSound,
          title: 'Note sound',
          subtitle: 'Play a piano tone when you press a key '
              '(turn off if your keyboard has its own sound)',
        ),
      ],
    );
  }

  Future<void> _confirmResetStats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('Reset stats?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Your ${_isScale ? "scale" : "chord"} score and best streak will '
          'go back to zero. This can\'t be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onResetStats();
    _showToast('Stats reset');
  }

  Widget _hintSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required String subtitle,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.accent,
      inactiveThumbColor: AppColors.textMuted,
      inactiveTrackColor: AppColors.surfaceHigh,
    );
  }
}
