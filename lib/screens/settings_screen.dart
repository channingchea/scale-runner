import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../notifications/notification_service.dart';
import '../purchases/paywall_sheet.dart';
import '../purchases/purchase_service.dart';
import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';
import '../ui/responsive.dart';
import '../widgets/timing_difficulty_selector.dart';

/// The app's real settings screen: global sound + timing controls, Restore
/// Purchases, and a Privacy Policy sub-page.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  QuizSettings? _settings;
  bool _noteSound = true;
  bool _tickHaptic = true;
  TimingDifficulty _difficulty = TimingDifficulty.normal;
  String _version = '';
  bool _restoring = false;
  bool _reminders = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    _init();
  }
  Future<void> _init() async {
    final settings = await QuizSettings.load();
    final noteSound = await settings.noteSoundEnabled();
    final tickHaptic = await settings.tickHapticEnabled();
    final difficulty = await settings.timingDifficulty();
    final reminders = await settings.remindersEnabled();
    final (hour, minute) = await settings.reminderTime();
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _noteSound = noteSound;
      _tickHaptic = tickHaptic;
      _difficulty = difficulty;
      _reminders = reminders;
      _reminderTime = TimeOfDay(hour: hour, minute: minute);
      _version = '${info.version} (${info.buildNumber})';
    });
  }

  Future<void> _toggleReminders(bool on) async {
    if (on) {
      // Turning on needs OS permission; if denied, stay off with a hint.
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        _snack('Notifications are blocked. Allow them for Scale Runner in '
            'your device settings first.');
        return;
      }
    }
    setState(() => _reminders = on);
    await _settings?.setRemindersEnabled(on);
    // resync() schedules everything when on and cancels all when off.
    await NotificationService.instance.resync();
  }

  Future<void> _pickReminderTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _reminderTime);
    if (picked == null) return;
    setState(() => _reminderTime = picked);
    await _settings?.setReminderTime(picked.hour, picked.minute);
    await NotificationService.instance.resync();
  }

  Future<void> _toggleNoteSound(bool on) async {
    setState(() => _noteSound = on);
    await _settings?.setNoteSoundEnabled(on);
  }

  Future<void> _toggleTickHaptic(bool on) async {
    setState(() => _tickHaptic = on);
    await _settings?.setTickHapticEnabled(on);
  }

  Future<void> _unlockPro() async {
    final unlocked = await PaywallSheet.show(context);
    if (unlocked && mounted) setState(() {});
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final ok = await PurchaseService.instance.restore();
      if (!mounted) return;
      _snack(ok ? 'Pro restored!' : 'No previous purchase found to restore.');
    } catch (_) {
      if (!mounted) return;
      _snack('Couldn\'t restore purchases.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openPrivacyPolicy() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _PrivacyPolicyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ContentColumn(
        child: settings == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _sectionHeader('Sound'),
                  _switchTile(
                    value: _noteSound,
                    onChanged: _toggleNoteSound,
                    title: 'Note sound',
                    subtitle: 'Play a piano tone when you press a key '
                        '(turn off if your keyboard has its own sound)',
                  ),
                  // Desktop has no haptics — HapticFeedback is a silent no-op
                  // there, so don't offer a switch that does nothing.
                  if (hasHaptics)
                    _switchTile(
                      value: _tickHaptic,
                      onChanged: _toggleTickHaptic,
                      title: 'Haptic tick',
                      subtitle: 'Buzz the device on every metronome beat',
                    ),
                  _sectionDivider(),
                  _sectionHeader('Reminders'),
                  _switchTile(
                    value: _reminders,
                    onChanged: _toggleReminders,
                    title: 'Practice reminders',
                    subtitle: 'A daily nudge at your chosen time, plus a '
                        'heads-up when your streak is about to break',
                  ),
                  if (_reminders) _reminderTimeTile(),
                  _sectionDivider(),
                  _sectionHeader('Timing'),
                  TimingDifficultySelector(
                    value: _difficulty,
                    settings: settings,
                    onChanged: (d) => setState(() => _difficulty = d),
                  ),
                  _sectionDivider(),
                  _sectionHeader('Purchases'),
                  _unlockProTile(),
                  _restoreTile(),
                  _sectionDivider(),
                  _sectionHeader('About'),
                  _privacyTile(),
                  _versionTile(),
                ],
              ),
      ),
    );
  }

  Widget _reminderTimeTile() {
    return ListTile(
      leading: const Icon(Icons.schedule, color: AppColors.textSecondary),
      title: const Text('Reminder time',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      trailing: Text(_reminderTime.format(context),
          style: const TextStyle(
              color: AppColors.accent,
              fontSize: 15,
              fontWeight: FontWeight.w700)),
      onTap: _pickReminderTime,
    );
  }

  /// Always-visible purchase entry point. Without it the only way to reach
  /// the paywall is to spend every free session of a gated mode, which App
  /// Review flagged under Guideline 2.1(b) as "cannot locate the IAP".
  Widget _unlockProTile() {
    if (PurchaseService.instance.isPro) {
      return const ListTile(
        leading: Icon(Icons.workspace_premium, color: AppColors.accent),
        title: Text('Scale Runner Pro',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
        subtitle: Text('Unlocked. Thanks for the support!',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
    }
    return ListTile(
      leading: const Icon(Icons.workspace_premium, color: AppColors.accent),
      title: const Text('Unlock Pro',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: const Text(
          'One-time purchase: Scale Running, Inversion Running, Jam Mode '
          'and unlimited saved voicings',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right,
          size: 16, color: AppColors.textMuted),
      onTap: _unlockPro,
    );
  }

  Widget _restoreTile() {
    return ListTile(
      leading: const Icon(Icons.restore, color: AppColors.textSecondary),
      title: const Text('Restore purchases',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: const Text('Recover a previous Pro unlock on this device',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: _restoring
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      onTap: _restoring ? null : _restore,
    );
  }

  Widget _privacyTile() {
    return ListTile(
      leading: const Icon(Icons.privacy_tip_outlined,
          color: AppColors.textSecondary),
      title: const Text('Privacy Policy',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: _openPrivacyPolicy,
    );
  }

  Widget _versionTile() {
    return ListTile(
      title: const Text('Version',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      trailing:
          Text(_version, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
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
      title: Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.accent,
      inactiveThumbColor: AppColors.textMuted,
      inactiveTrackColor: AppColors.surfaceHigh,
    );
  }
}

/// Displays the app's privacy policy inline (no external link — see
/// scale-runner-settings-info-screen memory for why).
class _PrivacyPolicyScreen extends StatelessWidget {
  const _PrivacyPolicyScreen();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ContentColumn(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy Policy',
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Last updated: July 14, 2026',
                  style: textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              _body(context,
                  'Scale Runner works fully offline and collects no personal '
                  'data unless you choose to sign in for the optional social '
                  'features. The app uses no analytics, advertising, or '
                  'tracking services of any kind.'),
              _section(context, 'Data Stored on Your Device'),
              _body(context,
                  'The app stores the following information locally on your '
                  'device only, using standard app preferences storage:\n\n'
                  '  • Practice statistics (score, best streak)\n'
                  '  • App settings (sound preference, onboarding status)\n\n'
                  'This information is deleted automatically when you uninstall '
                  'the app.'),
              _section(context, 'Optional Account & Social Features'),
              _body(context,
                  'If you sign in (with Apple or Google) to use the friends '
                  'features, the following is stored on our servers (Supabase):\n\n'
                  '  • Your display name and a generated avatar\n'
                  '  • Your practice streak (current, best, total days)\n'
                  '  • Your friend connections, invites, and applause\n\n'
                  'This data is visible only to friends you connect with. '
                  'There is no public profile or global leaderboard. You can '
                  'delete your account at any time from the Friends screen, '
                  'which permanently removes all of it from our servers. '
                  'Without an account, nothing ever leaves your device.'),
              _section(context, 'MIDI and Bluetooth'),
              _body(context,
                  'If you connect a MIDI keyboard via USB or Bluetooth, the app '
                  'communicates directly with that device to receive note input. '
                  'No information about your device, your playing, or your MIDI '
                  'hardware is transmitted anywhere.'),
              _section(context, 'Children\'s Privacy'),
              _body(context,
                  'Scale Runner does not knowingly collect any information from '
                  'anyone, including children under 13, because it does not '
                  'collect information at all.'),
              _section(context, 'Changes to This Policy'),
              _body(context,
                  'If this policy changes, the updated version will be posted '
                  'here with a revised "Last updated" date.'),
              _section(context, 'Contact'),
              _body(context,
                  'Questions about this privacy policy? Contact us at:\n'
                  'channing@c1gnus.com'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  Widget _body(BuildContext context, String text) {
    return Text(text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textSecondary, height: 1.6));
  }
}
