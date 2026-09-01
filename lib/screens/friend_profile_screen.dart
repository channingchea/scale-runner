import 'package:flutter/material.dart';

import '../social/social_models.dart';
import '../social/social_service.dart';
import '../theme/app_theme.dart';
import '../ui/responsive.dart';
import '../widgets/social_widgets.dart';

/// A friend's profile: streak stats plus weekly progress (days practiced,
/// sessions, accuracy) and a short trend. Opened by tapping a friend in the
/// leaderboard or the manage-friends list.
class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({super.key, required this.entry});

  final FriendEntry entry;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  final SocialService _social = SocialService.instance;
  FriendProfileDetail? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final detail = await _social.loadFriendProfile(widget.entry);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.profile.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.person_remove_outlined),
            tooltip: 'Remove friend',
            onPressed: () => _confirmRemove(entry),
          ),
        ],
      ),
      body: ContentColumn(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    _header(entry),
                    const SizedBox(height: 20),
                    const SocialSectionHeader('Streak'),
                    SocialCard(child: _streakRow(entry)),
                    const SizedBox(height: 20),
                    const SocialSectionHeader('Mode scores'),
                    SocialCard(child: _modeScores(_detail!.modeStats)),
                    const SizedBox(height: 20),
                    const SocialSectionHeader('This week'),
                    SocialCard(child: _thisWeek(_detail!.thisWeek)),
                    const SizedBox(height: 20),
                    const SocialSectionHeader('Days practiced per week'),
                    SocialCard(child: _trend(_detail!.trend)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(FriendEntry entry) {
    final applauded = _social.applaudedToday(entry.profile.id);
    return SocialCard(
      child: Row(
        children: [
          SocialAvatar(seed: entry.profile.avatarSeed, radius: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.profile.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Friends since ${relativeTime(entry.friendsSince)}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: applauded ? null : () => _applaud(entry),
            icon: Opacity(
              opacity: applauded ? 0.4 : 1,
              child: const Text('👏', style: TextStyle(fontSize: 16)),
            ),
            label: Text(applauded ? 'Applauded' : 'Applaud'),
          ),
        ],
      ),
    );
  }

  Widget _streakRow(FriendEntry e) => Row(
        children: [
          _stat('${e.currentStreak}', 'current'),
          _stat('${e.bestStreak}', 'best'),
          _stat('${e.totalDays}', 'total days'),
        ],
      );

  Widget _modeScores(ModeStats? m) => Row(
        children: [
          _stat(_scoreLabel(m?.scaleRunningScore), 'Scale Run'),
          _stat(_scoreLabel(m?.jamScore), 'Jam'),
          _stat(_scoreLabel(m?.inversionScore), 'Inversion'),
        ],
      );

  static String _scoreLabel(int? s) => s == null ? '—' : '$s';

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      );

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  Widget _thisWeek(WeeklyStat w) {
    final acc = w.accuracy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++) _dayDot(i, (w.daysMask & (1 << i)) != 0),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _stat('${w.daysPracticed}/7', 'days'),
            _stat('${w.sessions}', 'sessions'),
            _stat(acc == null ? '—' : '${(acc * 100).round()}%', 'accuracy'),
          ],
        ),
      ],
    );
  }

  Widget _dayDot(int i, bool on) => Column(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? AppColors.accent : AppColors.surfaceHigh,
            ),
            child: on
                ? const Icon(Icons.check, size: 15, color: Color(0xFF06251F))
                : null,
          ),
          const SizedBox(height: 4),
          Text(_dayLabels[i],
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      );

  Widget _trend(List<WeeklyStat> weeks) {
    if (weeks.isEmpty) {
      return const Text(
        'No history yet. A week of practice shows up here.',
        style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            fontStyle: FontStyle.italic),
      );
    }
    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final w in weeks)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${w.daysPracticed}',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10)),
                    const SizedBox(height: 3),
                    Container(
                      height: 8 + (w.daysPracticed / 7) * 56,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _applaud(FriendEntry entry) async {
    final ok = await _social.applaud(entry);
    if (!mounted) return;
    if (ok) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('You applauded ${entry.profile.displayName}! 👏')));
    }
  }

  Future<void> _confirmRemove(FriendEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${entry.profile.displayName}?'),
        content: const Text(
            'You\'ll stop seeing each other\'s streaks and activity. '
            'They aren\'t notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.wrong),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _social.removeFriend(entry.profile.id);
    if (mounted) Navigator.of(context).pop();
  }
}
