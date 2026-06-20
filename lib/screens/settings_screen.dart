import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// About screen — displays the app's privacy policy inline.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Privacy Policy',
                style: textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Last updated: June 14, 2026',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            _body(context,
                'Scale Runner does not collect, store, transmit, or share any '
                'personal data. The app has no user accounts, does not connect '
                'to the internet, and uses no analytics, advertising, or '
                'tracking services of any kind.'),
            _section(context, 'Data Stored on Your Device'),
            _body(context,
                'The app stores the following information locally on your '
                'device only, using standard app preferences storage:\n\n'
                '  • Practice statistics (score, best streak)\n'
                '  • App settings (sound preference, onboarding status)\n\n'
                'This information never leaves your device and is not '
                'accessible to the developer or any third party. It is deleted '
                'automatically when you uninstall the app.'),
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
