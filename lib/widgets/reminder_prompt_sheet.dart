import 'package:flutter/material.dart';

import '../notifications/notification_service.dart';
import '../quiz/quiz_settings.dart';
import '../streak/streak_service.dart';
import '../theme/app_theme.dart';

/// One-time opt-in prompt, shown right after the user's first-ever completed
/// practice: pick a reminder time, then the OS permission dialog. Asking at
/// this moment (they just started a streak) beats asking at first launch.
class ReminderPromptSheet extends StatefulWidget {
  const ReminderPromptSheet({super.key});

  /// Shows the prompt once ever, and only once a practice day exists.
  static Future<void> maybeShow(BuildContext context) async {
    final settings = await QuizSettings.load();
    if (await settings.reminderPromptSeen()) return;
    if (StreakService.instance.totalPracticeDays < 1) return;
    await settings.setReminderPromptSeen();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ReminderPromptSheet(),
    );
  }

  @override
  State<ReminderPromptSheet> createState() => _ReminderPromptSheetState();
}

class _ReminderPromptSheetState extends State<ReminderPromptSheet> {
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _enable() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final granted = await NotificationService.instance.requestPermission();
    final settings = await QuizSettings.load();
    if (granted) {
      await settings.setReminderTime(_time.hour, _time.minute);
      await settings.setRemindersEnabled(true);
      await NotificationService.instance.resync();
    } else {
      messenger.showSnackBar(const SnackBar(
        content: Text('Notifications are off — you can enable reminders '
            'anytime in Settings.'),
      ));
    }
    if (navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 22),
            const Icon(Icons.local_fire_department,
                size: 44, color: Color(0xFFFF9F43)),
            const SizedBox(height: 12),
            ShaderMask(
              shaderCallback: (b) => AppColors.accentGradient.createShader(b),
              child: const Text(
                'You started a streak!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Daily practice is how it sticks. Want a reminder at a time '
              'that suits you?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule,
                        size: 20, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Text(
                      _time.format(context),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('tap to change',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _enable,
                child: const Text('Remind me daily'),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
