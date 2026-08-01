import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../midi/midi_service.dart';
import '../purchases/purchase_service.dart';
import '../purchases/paywall_sheet.dart';
import '../notifications/notification_service.dart';
import '../quiz/quiz_controller.dart';
import '../quiz/quiz_settings.dart';
import '../social/social_service.dart';
import '../streak/streak_service.dart';
import '../widgets/streak_sheets.dart';
import '../widgets/welcome_sheet.dart';
import 'quiz_screen.dart';
import 'social_screen.dart';
import 'scale_run_screen.dart';
import 'inversion_run_screen.dart';
import 'jam_mode_screen.dart';
import 'midi_monitor_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

/// Landing screen: pick a practice mode, see MIDI status, open the monitor.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription<String>? _setupSub;
  final PurchaseService _purchases = PurchaseService.instance;
  final StreakService _streak = StreakService.instance;
  final SocialService _social = SocialService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupSub = widget.midi.onSetupChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _purchases.addListener(_onPurchasesChanged);
    _streak.addListener(_onPurchasesChanged);
    _social.addListener(_onPurchasesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeShowIntro();
      await _maybeShowStreakEvent();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A long-suspended app crosses midnights too: re-evaluate the streak on
    // resume so freezes/breaks surface without a full relaunch.
    if (state == AppLifecycleState.resumed) {
      _streak.init().then((_) async {
        await _maybeShowStreakEvent();
        await NotificationService.instance.resync();
      });
      // Pull fresh friend streaks/applause when coming back to the app.
      if (_social.isSignedIn) _social.refresh();
    }
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

  /// Surfaces the pending app-open streak event (Pro freeze applied, or
  /// streak lost → paywall recovery moment) at most once per event.
  Future<void> _maybeShowStreakEvent() async {
    if (!mounted) return;
    switch (_streak.consumeOpenEvent()) {
      case StreakFrozen(:final streak):
        await StreakFrozenSheet.show(context, streak);
      case StreakLost(:final lostStreak):
        await StreakLostSheet.show(context, lostStreak);
      case null:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setupSub?.cancel();
    _purchases.removeListener(_onPurchasesChanged);
    _streak.removeListener(_onPurchasesChanged);
    _social.removeListener(_onPurchasesChanged);
    super.dispose();
  }

  void _openSocial() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SocialScreen()),
    );
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
    final settings = await QuizSettings.load();
    if (!await settings.trialUsed(QuizSettings.modeScaleRun)) {
      _showTrialToast('Scale Running');
      if (mounted) _openScaleRun();
      return;
    }
    if (!mounted) return;
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
    final settings = await QuizSettings.load();
    if (!await settings.trialUsed(QuizSettings.modeInversionRun)) {
      _showTrialToast('Inversion Running');
      if (mounted) _openInversionRun();
      return;
    }
    if (!mounted) return;
    final unlocked = await PaywallSheet.show(context);
    if (unlocked && mounted) _openInversionRun();
  }

  void _openJamMode() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JamModeScreen(midi: widget.midi),
      ),
    );
  }

  Future<void> _openJamModeGated() async {
    if (_purchases.isPro) {
      _openJamMode();
      return;
    }
    final settings = await QuizSettings.load();
    if (!await settings.trialUsed(QuizSettings.modeJam)) {
      _showTrialToast('Jam Mode');
      if (mounted) _openJamMode();
      return;
    }
    if (!mounted) return;
    final unlocked = await PaywallSheet.show(context);
    if (unlocked && mounted) _openJamMode();
  }

  /// Announces a mode's one free trial session. Shown once, right before the
  /// mode opens unpaywalled for the first time.
  void _showTrialToast(String modeLabel) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Your first $modeLabel session is free — enjoy!')),
    );
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

  void _openStats() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const StatsScreen(),
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
                imagePath: 'assets/icon/Icon_Scales.png',
                onTap: () => _openQuiz(QuizMode.scale),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'Chords',
                subtitle: 'Build the named chord, holding all the notes at once',
                imagePath: 'assets/icon/Icon_Chords.png',
                onTap: () => _openQuiz(QuizMode.chord),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'Scale Running',
                subtitle:
                    'Hold chords and run their modes in time, key by key',
                imagePath: 'assets/icon/Icon_Running.png',
                locked: !_purchases.isPro,
                onTap: _openScaleRunGated,
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'Inversion Running',
                subtitle:
                    'Walk a chord up its inversions an octave and back down',
                imagePath: 'assets/icon/invert-run.png',
                locked: !_purchases.isPro,
                onTap: _openInversionRunGated,
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'Jam Mode',
                subtitle:
                    'Comp diatonic chords in time, one per bar, in a single key',
                imagePath: 'assets/icon/Jam.png',
                locked: !_purchases.isPro,
                onTap: _openJamModeGated,
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ShaderMask(
                  shaderCallback: (b) =>
                      AppColors.accentGradient.createShader(b),
                  child: const Text(
                    'Scale Runner',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const Text('Make music theory practical',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        if (_streak.currentStreak > 0) ...[
          _StreakBadge(
            streak: _streak.currentStreak,
            activeToday: _streak.practicedToday,
            onTap: _openStats,
          ),
          const SizedBox(width: 4),
        ],
        IconButton(
          icon: Badge(
            isLabelVisible: _social.unreadCount > 0,
            label: Text('${_social.unreadCount}'),
            child: const Icon(Icons.group_outlined),
          ),
          color: AppColors.textSecondary,
          tooltip: 'Friends',
          onPressed: _openSocial,
        ),
        IconButton(
          icon: const Icon(Icons.bar_chart_outlined),
          color: AppColors.textSecondary,
          tooltip: 'Stats',
          onPressed: _openStats,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
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

/// The daily practice streak pill: flame + day count. Bright when today's
/// practice is done, dimmed while the day's session is still owed.
class _StreakBadge extends StatelessWidget {
  const _StreakBadge({
    required this.streak,
    required this.activeToday,
    required this.onTap,
  });

  final int streak;
  final bool activeToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = activeToday ? const Color(0xFFFF9F43) : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 16, color: color),
            const SizedBox(width: 3),
            Text(
              '$streak',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
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
