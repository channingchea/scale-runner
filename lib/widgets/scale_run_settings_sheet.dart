import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../quiz/quiz_settings.dart';
import '../theory/music_theory.dart';
import '../theory/scale_running.dart';

/// Settings for the Scale Running drill: chords on/off, progression preset,
/// key increment, and triads vs 7ths. Persists immediately and calls
/// [onChanged] so the screen can rebuild its controller.
class ScaleRunSettingsSheet extends StatefulWidget {
  const ScaleRunSettingsSheet({
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
          ScaleRunSettingsSheet(settings: settings, onChanged: onChanged),
    );
  }

  @override
  State<ScaleRunSettingsSheet> createState() => _ScaleRunSettingsSheetState();
}

class _ScaleRunSettingsSheetState extends State<ScaleRunSettingsSheet> {
  bool _chords = true;
  bool _sevenths = false;
  bool _noteSound = true;
  String _progressionName = commonProgressions.first.name;
  KeyIncrement _increment = KeyIncrement.fifths;
  int _startKeyPc = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final chords = await widget.settings.runChordsEnabled();
    final sevenths = await widget.settings.runSevenths();
    final progression = await widget.settings.runProgression();
    final increment = await widget.settings.runKeyIncrement();
    final startKeyPc = await widget.settings.runStartKeyPc();
    final noteSound = await widget.settings.noteSoundEnabled();
    if (!mounted) return;
    setState(() {
      _chords = chords;
      _sevenths = sevenths;
      _noteSound = noteSound;
      _progressionName = progression.name;
      _increment = increment;
      _startKeyPc = startKeyPc;
      _loading = false;
    });
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
                        _switchTile(
                          value: _chords,
                          onChanged: (v) async {
                            setState(() => _chords = v);
                            await widget.settings.setRunChordsEnabled(v);
                            widget.onChanged();
                          },
                          title: 'Follow a chord progression',
                          subtitle:
                              'Hold each diatonic chord while running its mode. '
                              'Off = plain scale runs.',
                        ),
                        _switchTile(
                          value: _sevenths,
                          enabled: _chords,
                          onChanged: (v) async {
                            setState(() => _sevenths = v);
                            await widget.settings.setRunSevenths(v);
                            widget.onChanged();
                          },
                          title: 'Use 7th chords',
                          subtitle: 'Four-note diatonic 7ths instead of triads',
                        ),
                        _sectionDivider(),
                        _sectionHeader('Progression'),
                        for (final p in commonProgressions)
                          ListTile(
                            enabled: _chords,
                            onTap: () async {
                              setState(() => _progressionName = p.name);
                              await widget.settings
                                  .setRunProgressionName(p.name);
                              widget.onChanged();
                            },
                            title: Text(
                              p.name,
                              style: TextStyle(
                                color: _chords
                                    ? AppColors.textPrimary
                                    : AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: p.name == _progressionName
                                ? const Icon(Icons.check_circle,
                                    color: AppColors.accent, size: 20)
                                : const Icon(Icons.circle_outlined,
                                    color: AppColors.textMuted, size: 20),
                          ),
                        _sectionDivider(),
                        _sectionHeader('Starting key'),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var pc = 0; pc < 12; pc++)
                                _keyChip(pc),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'The key the drill begins in when you press Start',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                        _sectionDivider(),
                        _sectionHeader('Key change'),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: SegmentedButton<KeyIncrement>(
                            segments: const [
                              ButtonSegment(
                                value: KeyIncrement.fifths,
                                label: Text('By fifths'),
                              ),
                              ButtonSegment(
                                value: KeyIncrement.chromatic,
                                label: Text('Chromatic'),
                              ),
                            ],
                            selected: {_increment},
                            onSelectionChanged: (sel) async {
                              setState(() => _increment = sel.first);
                              await widget.settings
                                  .setRunKeyIncrement(sel.first);
                              widget.onChanged();
                            },
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'How the key advances after each full pass of the '
                            'progression',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
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

  Widget _keyChip(int pc) {
    final selected = pc == _startKeyPc;
    return ChoiceChip(
      label: Text(pitchClassNames[pc]),
      selected: selected,
      onSelected: (_) async {
        setState(() => _startKeyPc = pc);
        await widget.settings.setRunStartKeyPc(pc);
        widget.onChanged();
      },
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF06251F) : AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surfaceHigh,
      side: BorderSide(
          color: selected ? AppColors.accent : AppColors.border),
      showCheckmark: false,
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
            'Scale Running',
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
    bool enabled = true,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(
        title,
        style: TextStyle(
            color: enabled ? AppColors.textPrimary : AppColors.textMuted,
            fontWeight: FontWeight.w500),
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
