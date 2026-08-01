import 'package:flutter/material.dart';

import '../social/social_models.dart';
import '../theme/app_theme.dart';
import 'social_widgets.dart';

/// Lets a signed-in user pick their avatar — the emoji + color indices that
/// make up a seed "emoji:color". Returns the chosen seed, or null if dismissed.
class AvatarPickerSheet extends StatefulWidget {
  const AvatarPickerSheet({super.key, required this.initialSeed});

  final String initialSeed;

  static Future<String?> show(BuildContext context, String initialSeed) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => AvatarPickerSheet(initialSeed: initialSeed),
      );

  @override
  State<AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<AvatarPickerSheet> {
  late int _emoji;
  late int _color;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialSeed.split(':');
    _emoji = _parse(parts, 0, avatarEmojis.length);
    _color = _parse(parts, 1, avatarColors.length);
  }

  static int _parse(List<String> parts, int i, int mod) {
    if (i >= parts.length) return 0;
    return (int.tryParse(parts[i]) ?? 0) % mod;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(child: SocialAvatar(seed: '$_emoji:$_color', radius: 32)),
          const SizedBox(height: 22),
          const SocialSectionHeader('Icon'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < avatarEmojis.length; i++) _emojiChip(i),
            ],
          ),
          const SizedBox(height: 20),
          const SocialSectionHeader('Color'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < avatarColors.length; i++) _colorDot(i),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, '$_emoji:$_color'),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiChip(int i) {
    final selected = i == _emoji;
    return GestureDetector(
      onTap: () => setState(() => _emoji = i),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(avatarEmojis[i],
            style: const TextStyle(fontSize: 22, height: 1.0)),
      ),
    );
  }

  Widget _colorDot(int i) {
    final selected = i == _color;
    final c = avatarColors[i];
    return GestureDetector(
      onTap: () => setState(() => _color = i),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? c : AppColors.border,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected ? Icon(Icons.check, size: 18, color: c) : null,
      ),
    );
  }
}
