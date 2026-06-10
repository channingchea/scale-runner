import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart';
import 'quiz_screen.dart';
import 'midi_monitor_screen.dart';

/// Landing screen: pick a practice mode, see MIDI status, open the monitor.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<String>? _setupSub;

  @override
  void initState() {
    super.initState();
    widget.midi.start();
    // Rebuild the status banner when devices connect/disconnect.
    _setupSub = widget.midi.onSetupChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _setupSub?.cancel();
    super.dispose();
  }

  void _openQuiz(QuizMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(mode: mode, midi: widget.midi),
      ),
    );
  }

  void _openMonitor() {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => MidiMonitorScreen(midi: widget.midi),
        ))
        .then((_) => setState(() {}));
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
                icon: Icons.timeline,
                gradient: const [AppColors.accent, Color(0xFF1FA396)],
                onTap: () => _openQuiz(QuizMode.scale),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                title: 'Chords',
                subtitle: 'Build the named chord — hold all the notes at once',
                icon: Icons.grid_view_rounded,
                gradient: const [AppColors.accent2, Color(0xFFD98E0B)],
                onTap: () => _openQuiz(QuizMode.chord),
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
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.music_note, color: Color(0xFF06251F), size: 30),
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
                        : 'Tap to connect — or just use the on-screen keys',
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
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: const Color(0xFF0F141B), size: 30),
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
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
