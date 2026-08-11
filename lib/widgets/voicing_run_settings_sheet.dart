import 'package:flutter/material.dart';

import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';
import '../theory/music_theory.dart';
import '../theory/voicings.dart';

/// Settings for the Voicings drill. Two sections only: which **keys** the
/// shape walks through, and how much **help** you get while playing it.
///
/// Nothing here touches scoring, because the mode has none. Every change
/// persists immediately and calls [onChanged] so the screen can pick it up.
class VoicingRunSettingsSheet extends StatefulWidget {
  const VoicingRunSettingsSheet({
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
          VoicingRunSettingsSheet(settings: settings, onChanged: onChanged),
    );
  }

  @override
  State<VoicingRunSettingsSheet> createState() =>
      _VoicingRunSettingsSheetState();
}

class _VoicingRunSettingsSheetState extends State<VoicingRunSettingsSheet> {
  int _startKeyPc = 0;
  KeyIncrement _increment = KeyIncrement.chromatic;
  bool _showDots = true;
  bool _showFormula = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final startKeyPc = await widget.settings.voicingStartKeyPc();
    final increment = await widget.settings.voicingIncrement();
    final showDots = await widget.settings.voicingShowDots();
    final showFormula = await widget.settings.voicingShowFormula();
    if (!mounted) return;
    setState(() {
      _startKeyPc = startKeyPc;
      _increment = increment;
      _showDots = showDots;
      _showFormula = showFormula;
      _loading = false;
    });
  }

  /// How many keys the current choice adds up to — the honest answer to "how
  /// long is this going to take?", and the clearest way to show what the two
  /// options actually differ on.
  int get _keyCount => _increment == KeyIncrement.chromatic ? 25 : 12;

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
                child:
                    Center(heightFactor: 1, child: CircularProgressIndicator()),
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
                        _sectionHeader('Keys'),
                        _note(
                          'One shape, every key. Changing either of these '
                          'restarts the drill.',
                        ),
                        _subLabel('How the key moves'),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: SegmentedButton<KeyIncrement>(
                            segments: const [
                              ButtonSegment(
                                value: KeyIncrement.chromatic,
                                label: Text('Chromatic'),
                              ),
                              ButtonSegment(
                                value: KeyIncrement.fifths,
                                label: Text('By fifths'),
                              ),
                            ],
                            selected: {_increment},
                            onSelectionChanged: (sel) async {
                              setState(() => _increment = sel.first);
                              await widget.settings
                                  .setVoicingIncrement(sel.first);
                              widget.onChanged();
                            },
                          ),
                        ),
                        _note(
                          _increment == KeyIncrement.chromatic
                              ? 'Up a semitone at a time for an octave, then '
                                  'back down. $_keyCount keys.'
                              : 'Round the circle of fifths once. '
                                  '$_keyCount keys.',
                        ),
                        _subLabel('Starting key'),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var pc = 0; pc < 12; pc++) _keyChip(pc),
                            ],
                          ),
                        ),
                        _note('The key the drill begins in when you press '
                            'Start.'),
                        _sectionDivider(),
                        _sectionHeader('Challenge'),
                        _switchTile(
                          value: _showDots,
                          onChanged: (v) async {
                            setState(() => _showDots = v);
                            await widget.settings.setVoicingShowDots(v);
                            widget.onChanged();
                          },
                          title: 'Target dots',
                          subtitle:
                              'Mark the exact keys to play. Turn off once you '
                              'can find the shape yourself — that\'s the point '
                              'of the mode.',
                        ),
                        _switchTile(
                          value: _showFormula,
                          onChanged: (v) async {
                            setState(() => _showFormula = v);
                            await widget.settings.setVoicingShowFormula(v);
                            widget.onChanged();
                          },
                          title: 'Degree formula',
                          subtitle:
                              'Show the shape\'s spelling (e.g. 7-3-5-1) under '
                              'the key name.',
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
        await widget.settings.setVoicingStartKeyPc(pc);
        widget.onChanged();
      },
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF06251F) : AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surfaceHigh,
      side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
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
            'Voicings',
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

  Widget _subLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          text,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
