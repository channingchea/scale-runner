import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theory/jam_mode.dart';
import '../theory/music_theory.dart';
import '../quiz/quiz_settings.dart';

/// Settings for the Jam Mode comping drill: the fixed key, which chord families
/// to prompt (never empty), the challenge hints, and note sound. Persists
/// immediately and calls [onChanged] so the screen rebuilds its controller.
class JamModeSettingsSheet extends StatefulWidget {
  const JamModeSettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final QuizSettings settings;
  final VoidCallback onChanged;

  static Future<void> show(
    BuildContext context, {
    required QuizSettings settings,
    required VoidCallback onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          JamModeSettingsSheet(settings: settings, onChanged: onChanged),
    );
  }

  @override
  State<JamModeSettingsSheet> createState() => _JamModeSettingsSheetState();
}

class _JamModeSettingsSheetState extends State<JamModeSettingsSheet> {
  int _keyPc = 0;
  Set<JamFamily> _families = JamFamily.values.toSet();
  int _sessionBars = 24;
  bool _freestyle = false;
  bool _countInNumbers = true;
  bool _showDots = true;
  bool _showFormula = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final keyPc = await widget.settings.jamKeyPc();
    final families = await widget.settings.jamFamilies();
    final sessionBars = await widget.settings.jamSessionBars();
    final freestyle = await widget.settings.jamFreestyle();
    final countInNumbers = await widget.settings.jamCountInNumbers();
    final showDots = await widget.settings.jamShowDots();
    final showFormula = await widget.settings.jamShowFormula();
    if (!mounted) return;
    setState(() {
      _keyPc = keyPc;
      _families = families;
      _sessionBars = sessionBars;
      _freestyle = freestyle;
      _countInNumbers = countInNumbers;
      _showDots = showDots;
      _showFormula = showFormula;
      _loading = false;
    });
  }

  Future<void> _pickFreestyle(bool on) async {
    setState(() => _freestyle = on);
    await widget.settings.setJamFreestyle(on);
    widget.onChanged();
  }

  Future<void> _pickSessionBars(int bars) async {
    setState(() => _sessionBars = bars);
    await widget.settings.setJamSessionBars(bars);
    widget.onChanged();
  }

  Future<void> _pickCountInNumbers(bool numbers) async {
    setState(() => _countInNumbers = numbers);
    await widget.settings.setJamCountInNumbers(numbers);
    widget.onChanged();
  }

  Future<void> _pickKey(int pc) async {
    setState(() => _keyPc = pc);
    await widget.settings.setJamKeyPc(pc);
    widget.onChanged();
  }

  /// Toggle a family, keeping at least one selected.
  Future<void> _toggleFamily(JamFamily family) async {
    final next = Set<JamFamily>.from(_families);
    if (next.contains(family)) {
      if (next.length == 1) return; // never empty
      next.remove(family);
    } else {
      next.add(family);
    }
    setState(() => _families = next);
    await widget.settings.setJamFamilies(next);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    heightFactor: 1, child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _grabber(),
                  _title(),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        _sectionHeader('Mode'),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'Prompted shows a specific chord each bar. '
                            'Freestyle lets you play any diatonic chord — '
                            'just don\'t play the same scale degree twice in '
                            'a row.',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                        _modeChips(),
                        _sectionDivider(),
                        _sectionHeader('Key'),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'The whole session plays in one key. Chords are '
                            'drawn at random from the families below.',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                        _keyChips(),
                        _sectionDivider(),
                        _sectionHeader('Chord families'),
                        for (final f in JamFamily.values) _familyTile(f),
                        _sectionDivider(),
                        _sectionHeader('Session length'),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'How many chords per session. The drill ends and '
                            'tallies automatically after the last one.',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                        _sessionChips(),
                        _sectionDivider(),
                        _sectionHeader('Count-in display'),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'How the count toward each chord\'s strike is shown.',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                        _countInChips(),
                        _sectionDivider(),
                        _sectionHeader('Challenge'),
                        _switchTile(
                          value: _showDots,
                          onChanged: (v) async {
                            setState(() => _showDots = v);
                            await widget.settings.setJamShowDots(v);
                            widget.onChanged();
                          },
                          title: 'Blue target dots',
                          subtitle:
                              'Highlight the chord tones on the keyboard. '
                              'Turn off for a harder challenge.',
                        ),
                        _switchTile(
                          value: _showFormula,
                          onChanged: (v) async {
                            setState(() => _showFormula = v);
                            await widget.settings.setJamShowFormula(v);
                            widget.onChanged();
                          },
                          title: 'Chord formulas',
                          subtitle:
                              'Show the chord\'s degree formula (e.g. 1-3-5) '
                              'under the prompt.',
                        ),
                        _sectionDivider(),
                        _sectionHeader('Lifetime stats'),
                        _resetTile(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _modeChips() {
    Widget chip(String label, bool freestyle) => ChoiceChip(
          label: Text(label),
          selected: _freestyle == freestyle,
          onSelected: (_) => _pickFreestyle(freestyle),
          showCheckmark: false,
          labelStyle: TextStyle(
            color: _freestyle == freestyle
                ? const Color(0xFF06251F)
                : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          backgroundColor: AppColors.surfaceHigh,
          selectedColor: AppColors.accent,
          side: BorderSide(
            color: _freestyle == freestyle ? AppColors.accent : AppColors.border,
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [chip('Prompted', false), chip('Freestyle', true)],
      ),
    );
  }

  Widget _keyChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var pc = 0; pc < 12; pc++)
            ChoiceChip(
              label: Text(pitchClassNames[pc]),
              selected: _keyPc == pc,
              onSelected: (_) => _pickKey(pc),
              showCheckmark: false,
              labelStyle: TextStyle(
                color: _keyPc == pc
                    ? const Color(0xFF06251F)
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              backgroundColor: AppColors.surfaceHigh,
              selectedColor: AppColors.accent,
              side: BorderSide(
                color: _keyPc == pc ? AppColors.accent : AppColors.border,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final bars in QuizSettings.jamSessionLengths)
            ChoiceChip(
              label: Text('$bars chords'),
              selected: _sessionBars == bars,
              onSelected: (_) => _pickSessionBars(bars),
              showCheckmark: false,
              labelStyle: TextStyle(
                color: _sessionBars == bars
                    ? const Color(0xFF06251F)
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              backgroundColor: AppColors.surfaceHigh,
              selectedColor: AppColors.accent,
              side: BorderSide(
                color: _sessionBars == bars ? AppColors.accent : AppColors.border,
              ),
            ),
        ],
      ),
    );
  }

  Widget _countInChips() {
    Widget chip(String label, bool numbers) => ChoiceChip(
          label: Text(label),
          selected: _countInNumbers == numbers,
          onSelected: (_) => _pickCountInNumbers(numbers),
          showCheckmark: false,
          labelStyle: TextStyle(
            color: _countInNumbers == numbers
                ? const Color(0xFF06251F)
                : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          backgroundColor: AppColors.surfaceHigh,
          selectedColor: AppColors.accent,
          side: BorderSide(
            color: _countInNumbers == numbers
                ? AppColors.accent
                : AppColors.border,
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip('Numbers (4 3 2 1)', true),
          chip('Beat dots', false),
        ],
      ),
    );
  }

  Widget _resetTile() {
    return ListTile(
      onTap: _confirmReset,
      leading: const Icon(Icons.restart_alt, color: AppColors.wrong, size: 22),
      title: const Text(
        'Reset weak-point stats',
        style: TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.w500),
      ),
      subtitle: const Text(
        'Clear the accuracy you\'ve accumulated by chord quality and degree.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reset stats?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This clears your accumulated per-quality and per-degree accuracy. '
          'It can\'t be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset',
                style: TextStyle(color: AppColors.wrong)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.settings.resetJamStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jam Mode stats reset')),
        );
      }
    }
  }

  Widget _familyTile(JamFamily family) {
    final selected = _families.contains(family);
    return ListTile(
      onTap: () => _toggleFamily(family),
      title: Text(
        family.label,
        style: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.w500),
      ),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? AppColors.accent : AppColors.textMuted,
        size: 20,
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

  Widget _title() => const Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Jam Mode',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ),
      );

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

  Widget _switchTile({
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
