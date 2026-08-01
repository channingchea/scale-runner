import 'package:flutter/material.dart';

import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';

/// A small dismissible banner shown in portrait on the practice screens,
/// suggesting landscape for bigger keys. Dismissal is persisted via
/// [settings] (same pattern as the welcome sheet's `introSeen` flag) so once
/// closed it never shows again.
class RotateHintBanner extends StatefulWidget {
  const RotateHintBanner({super.key, required this.settings});

  final QuizSettings settings;

  @override
  State<RotateHintBanner> createState() => _RotateHintBannerState();
}

class _RotateHintBannerState extends State<RotateHintBanner> {
  bool _dismissed = true; // default hidden until we know the stored value

  @override
  void initState() {
    super.initState();
    widget.settings.rotateHintDismissed().then((dismissed) {
      if (mounted && !dismissed) setState(() => _dismissed = false);
    });
  }

  void _dismiss() {
    setState(() => _dismissed = true);
    widget.settings.setRotateHintDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    if (_dismissed || !portrait) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.screen_rotation, color: AppColors.accent2, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Rotate for bigger keys',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            InkWell(
              onTap: _dismiss,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, color: AppColors.textMuted, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
