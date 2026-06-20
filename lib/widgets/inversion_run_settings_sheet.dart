import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../quiz/quiz_settings.dart';

/// Settings for the Inversion Running drill: which of the four v1 chords to
/// drill, and (placeholder) note sound. Persists immediately and calls
/// [onChanged] so the screen can rebuild its controller.
class InversionRunSettingsSheet extends StatefulWidget {
  const InversionRunSettingsSheet({
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
          InversionRunSettingsSheet(settings: settings, onChanged: onChanged),
    );
  }

  @override
  State<InversionRunSettingsSheet> createState() =>
      _InversionRunSettingsSheetState();
}

class _InversionRunSettingsSheetState extends State<InversionRunSettingsSheet> {
  Set<String> _chords = QuizSettings.invChordNames.toSet();
  bool _noteSound = true;
  bool _tempoMode = false;
  bool _showDots = true;
  bool _showFormula = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final chords = await widget.settings.invEnabledChordNames();
    final noteSound = await widget.settings.noteSoundEnabled();
    final tempoMode = await widget.settings.invTempoMode();
    final showDots = await widget.settings.invShowDots();
    final showFormula = await widget.settings.invShowFormula();
    if (!mounted) return;
    setState(() {
      _chords = chords;
      _noteSound = noteSound;
      _tempoMode = tempoMode;
      _showDots = showDots;
      _showFormula = showFormula;
      _loading = false;
    });
  }

  /// Toggle a chord, keeping at least one selected.
  Future<void> _toggleChord(String name) async {
    final next = Set<String>.from(_chords);
    if (next.contains(name)) {
      if (next.length == 1) return; // never empty
      next.remove(name);
    } else {
      next.add(name);
    }
    setState(() => _chords = next);
    await widget.settings.setInvEnabledChordNames(next);
    widget.onChanged();
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
                        _sectionHeader('Chords'),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'Each round picks a random chord and key, then '
                            'walks its inversions up an octave and back down.',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                        for (final name in QuizSettings.invChordNames)
                          _chordTile(name),
                        _sectionDivider(),
                        _sectionHeader('Pacing'),
                        _switchTile(
                          value: _tempoMode,
                          onChanged: (v) async {
                            setState(() => _tempoMode = v);
                            await widget.settings.setInvTempoMode(v);
                            widget.onChanged();
                          },
                          title: 'Tempo mode',
                          subtitle:
                              'Advance on the metronome beat (count-in first). '
                              'Off = self-paced: play each voicing to advance.',
                        ),
                        _sectionDivider(),
                        _sectionHeader('Challenge'),
                        _switchTile(
                          value: _showDots,
                          onChanged: (v) async {
                            setState(() => _showDots = v);
                            await widget.settings.setInvShowDots(v);
                            widget.onChanged();
                          },
                          title: 'Blue target dots',
                          subtitle:
                              'Highlight the keys to press on the keyboard. '
                              'Turn off for a harder challenge.',
                        ),
                        _switchTile(
                          value: _showFormula,
                          onChanged: (v) async {
                            setState(() => _showFormula = v);
                            await widget.settings.setInvShowFormula(v);
                            widget.onChanged();
                          },
                          title: 'Chord formulas',
                          subtitle:
                              'Show the chord\'s degree formula (e.g. 1-3-5) '
                              'under the prompt.',
                        ),
                        _sectionDivider(),
                        _sectionHeader('Sound'),
                        _switchTile(
                          value: _noteSound,
                          onChanged: (v) async {
                            setState(() => _noteSound = v);
                            await widget.settings.setNoteSoundEnabled(v);
                            widget.onChanged();
                          },
                          title: 'Note sound',
                          subtitle: 'Play a piano tone when you press a key '
                              '(turn off if your keyboard has its own sound)',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _chordTile(String name) {
    final selected = _chords.contains(name);
    return ListTile(
      onTap: () => _toggleChord(name),
      title: Text(
        name,
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
            'Inversion Running',
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
