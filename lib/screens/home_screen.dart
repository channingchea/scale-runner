import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../midi/midi_service.dart';
import '../purchases/purchase_service.dart';
import '../purchases/paywall_sheet.dart';
import '../quiz/quiz_controller.dart';
import '../quiz/quiz_settings.dart';
import '../widgets/welcome_sheet.dart';
import 'quiz_screen.dart';
import 'scale_run_screen.dart';
import 'inversion_run_screen.dart';
import 'midi_monitor_screen.dart';
import 'settings_screen.dart';

/// Landing screen: pick a practice mode, see MIDI status, open the monitor.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<String>? _setupSub;
  final PurchaseService _purchases = PurchaseService.instance;

  @override
  void initState() {
    super.initState();
    _setupSub = widget.midi.onSetupChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _purchases.addListener(_onPurchasesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowIntro());
  }

  void _onPurchasesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _maybeShowIntro() async {
    final settings = await QuizSettings.load();
    if (await settings.introSeen()) return;
    await settings.setIntroSeen();
    if (!mounted) return;
    WelcomeSheet.show(context);
  }

  @override
  void dispose() {
    _setupSub?.cancel();
    _purchases.removeListener(_onPurchasesChanged);
    super.dispose();
  }

  void _openQuiz(QuizMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(mode: mode, midi: widget.midi),
      ),
    );
  }

  void _openScaleRun() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScaleRunScreen(midi: widget.midi),
      ),
    );
  }

  Future<void> _openScaleRunGated() async {
    if (_purchases.isPro) {
      _openScaleRun();
      return;
    }
    final unlocked = await PaywallSheet.show(context);
    if (unlocked && mounted) _openScaleRun();
  }

  void _openInversionRun() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InversionRunScreen(midi: widget.midi),
      ),
    );
  }

  Future<void> _openInversionRunGated() async {
    if (_purchases.isPro) {
      _openInversionRun();
      return;
    }
    final unlocked = await PaywallSheet.show(context);
    if (unlocked && mounted) _openInversionRun();
  }

  void _openMonitor() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => MidiMonitorScreen(midi: widget.midi),
        ))
        .then((_) => setState(() {}));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildMidiBanner(),
              const SizedBox(height: 24),
              Text('Practice',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _ModeCard(
                title: 'Scales',
                subtitle: 'Play scales from a random key, note by note',
                imagePath: 'assets/icon/Icon_Scales.jpg',
                onTap: () => _openQuiz(QuizMode.scale),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'Chords',
                subtitle: 'Build the named chord, holding all the notes at once',
                imagePath: 'assets/icon/Icon_Chords.jpg',
                onTap: () => _openQuiz(QuizMode.chord),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'Scale Running',
                subtitle:
                    'Hold chords and run their modes in time, key by key',
                imagePath: 'assets/icon/Icon_Running.jpg',
                locked: !_purchases.isPro,
                onTap: _openScaleRunGated,
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'Inversion Running',
                subtitle:
                    'Walk a chord up its inversions an octave and back down',
                imagePath: 'assets/icon/invert-run.jpg',
                locked: !_purchases.isPro,
                onTap: _openInversionRunGated,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/icon/app_icon.png',
            width: 52,
            height: 52,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (b) => AppColors.accentGradient.createShader(b),
              child: const Text(
                'Scale Runner',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const Text('Train your scales & chords',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.info_outline),
          color: AppColors.textSecondary,
          tooltip: 'Settings',
          onPressed: _openSettings,
        ),
        IconButton(
          icon: const Icon(Icons.help_outline),
          color: AppColors.textSecondary,
          tooltip: 'How it works',
          onPressed: () => WelcomeSheet.show(context),
        ),
      ],
    );
  }

  Widget _buildMidiBanner() {
    final connected = widget.midi.isConnected;
    final name = widget.midi.connectedDevice?.name;
    return InkWell(
      onTap: _openMonitor,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: connected ? AppColors.correct : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              connected ? Icons.piano : Icons.bluetooth_searching,
              color: connected ? AppColors.correct : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? 'MIDI connected' : 'No MIDI device',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: connected
                          ? AppColors.correct
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    connected
                        ? (name ?? 'Keyboard')
                        : 'Tap to connect or just use the on-screen keys',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.onTap,
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final String imagePath;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                imagePath,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            if (locked)
              const _ProBadge()
            else
              const Icon(Icons.arrow_forward_ios,
                  size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 12, color: Color(0xFF06251F)),
          SizedBox(width: 4),
          Text('PRO',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF06251F))),
        ],
      ),
    );
  }
}
