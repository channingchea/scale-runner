import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
      ),
    );
  }

  @override
  State<QuizSettingsSheet> createState() => _QuizSettingsSheetState();
}

class _QuizSettingsSheetState extends State<QuizSettingsSheet> {
  late List<String> _all;
  Set<String> _enabled = {};
  bool _formulaHint = true;
  bool _dotsHint = true;
  bool _statsBar = true;
  bool _beatIndicator = true;
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
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _formulaHint = formulaHint;
      _dotsHint = dotsHint;
      _statsBar = statsBar;
      _beatIndicator = beatIndicator;
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

  /// Scale names grouped and ordered by scale degree. Names must match those in
  /// `commonScales`; any not listed here are appended so nothing is dropped.
  static const List<String> _majorScaleModes = [
    'Major (Ionian)',
    'Dorian',
    'Phrygian',
    'Lydian',
    'Mixolydian',
    'Natural Minor (Aeolian)',
    'Locrian',
  ];
  static const List<String> _miscScales = [
    'Harmonic Minor',
    'Melodic Minor (asc)',
    'Major Pentatonic',
    'Minor Pentatonic',
    'Blues',
    'Chromatic',
  ];

  List<Widget> _groupedScaleTiles() {
    final known = {..._majorScaleModes, ..._miscScales};
    final leftover = _all.where((n) => !known.contains(n)).toList();
    return [
      _sectionHeader('Major Scale Modes'),
      ..._flatTiles(_majorScaleModes.where(_all.contains)),
      _sectionDivider(),
      _sectionHeader('Misc. Scales'),
      ..._flatTiles(_miscScales.where(_all.contains)),
      if (leftover.isNotEmpty) ..._flatTiles(leftover),
    ];
  }

  List<Widget> _flatTiles(Iterable<String> names) => [
        for (final name in names)
          SwitchListTile(
            value: _enabled.contains(name),
            onChanged: (v) => _toggle(name, v),
            title: Text(
              name,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            ),
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accent,
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.surfaceHigh,
          ),
      ];

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
      ],
    );
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
