import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../social/social_backend.dart';
import '../social/social_models.dart';
import '../social/social_service.dart';
import '../streak/streak_service.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_picker_sheet.dart';
import '../widgets/social_widgets.dart';
import '../widgets/streak_sheets.dart' show appShareUrl;
import 'friend_profile_screen.dart';
import 'friends_screen.dart';

/// The social hub: sign-in when signed out; otherwise leaderboard,
/// activity feed, invites, and account management.
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  final SocialService _social = SocialService.instance;
  bool _authBusy = false;

  @override
  void initState() {
    super.initState();
    _social.addListener(_onChange);
    _refreshAndMarkSeen();
  }

  Future<void> _refreshAndMarkSeen() async {
    await _social.init();
    if (_social.isSignedIn) {
      await _social.refresh();
      await _social.markActivitySeen();
    }
  }

  @override
  void dispose() {
    _social.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: _social.isSignedIn ? _buildSignedIn() : _buildSignedOut(),
    );
  }

  // ---- Signed out ----

  Widget _buildSignedOut() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        SocialCard(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  gradient: AppColors.accentGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group,
                    size: 38, color: Color(0xFF06251F)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Practice with friends',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to back up your streak, invite friends, applaud '
                'their practice, and climb the streak leaderboard. '
                'Everything else works without an account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 20),
              if (_authBusy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                )
              else ...[
                if (appleSignInAvailable)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.apple, size: 20),
                      label: const Text('Sign in with Apple'),
                      onPressed: () => _signIn(_social.signInWithApple),
                    ),
                  ),
                if (appleSignInAvailable && googleSignInAvailable)
                  const SizedBox(height: 8),
                if (googleSignInAvailable)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.g_mobiledata, size: 24),
                      label: const Text('Sign in with Google'),
                      onPressed: () => _signIn(_social.signInWithGoogle),
                    ),
                  ),
                if (!appleSignInAvailable && !googleSignInAvailable)
                  const Text(
                    'Sign-in isn\'t configured in this build yet.',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                TextButton(
                  onPressed: _showEmailSignIn,
                  child: const Text('Sign in with email',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Only your display name, avatar, and streak are shared — and only '
          'with friends you invite.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _signIn(Future<String?> Function() method) async {
    setState(() => _authBusy = true);
    final error = await method();
    if (!mounted) return;
    setState(() => _authBusy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else if (_social.isSignedIn) {
      await _social.markActivitySeen();
    }
  }

  Future<void> _showEmailSignIn() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final creds = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in with email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
                context, (emailController.text, passwordController.text)),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (creds == null || !mounted) return;
    final (email, password) = creds;
    await _signIn(() => _social.signInWithEmail(email, password));
  }

  // ---- Signed in ----

  Widget _buildSignedIn() {
    final profile = _social.profile;
    final activity = _social.activity;
    final profileCard = profile == null ? null : _profileCard(profile);
    return RefreshIndicator(
      onRefresh: _refreshAndMarkSeen,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          ?profileCard,
          const SizedBox(height: 20),
          const SocialSectionHeader('Streak leaderboard'),
          SocialCard(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: _leaderboard(profile),
          ),
          const SizedBox(height: 20),
          const SocialSectionHeader('Activity'),
          SocialCard(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: activity.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'No activity yet. When friends join or applaud your '
                      'streak, it shows up here.',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          fontStyle: FontStyle.italic),
                    ),
                  )
                : Column(
                    children: [
                      for (final item in activity) _activityRow(item),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          const SocialSectionHeader('Account'),
          SocialCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.group_outlined,
                      color: AppColors.textSecondary),
                  title: const Text('Manage friends'),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textMuted),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const FriendsScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.logout,
                      color: AppColors.textSecondary),
                  title: const Text('Sign out'),
                  onTap: _confirmSignOut,
                ),
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: AppColors.wrong),
                  title: const Text('Delete account',
                      style: TextStyle(color: AppColors.wrong)),
                  onTap: _confirmDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard(SocialProfile profile) {
    return SocialCard(
      child: Row(
        children: [
          GestureDetector(
            onTap: _editAvatar,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SocialAvatar(seed: profile.avatarSeed, radius: 24),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: AppColors.surfaceHigh, shape: BoxShape.circle),
                    child: const Icon(Icons.edit,
                        size: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      color: AppColors.textMuted,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Edit name',
                      onPressed: _editName,
                    ),
                  ],
                ),
                Text(
                  '🔥 ${StreakService.instance.currentStreak}-day streak',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Invite'),
            onPressed: _invite,
          ),
        ],
      ),
    );
  }

  Widget _leaderboard(SocialProfile? profile) {
    final me = profile == null
        ? null
        : FriendEntry(
            profile: profile,
            currentStreak: StreakService.instance.currentStreak,
            bestStreak: StreakService.instance.bestStreak,
            friendsSince: DateTime.now(),
          );
    final rows = [
      ?me,
      ..._social.friends,
    ]..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));

    if (_social.loading && _social.friends.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (rows.length <= 1) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            const Text(
              'No friends yet — the leaderboard starts with your first '
              'invite.',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Invite a friend'),
                onPressed: _invite,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final (i, entry) in rows.indexed)
          _leaderboardRow(i + 1, entry, isMe: entry.profile.id == profile?.id),
      ],
    );
  }

  Widget _leaderboardRow(int rank, FriendEntry entry, {required bool isMe}) {
    final applauded = _social.applaudedToday(entry.profile.id);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank == 1 ? AppColors.accent2 : AppColors.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          SocialAvatar(seed: entry.profile.avatarSeed, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isMe ? '${entry.profile.displayName} (you)' : entry.profile.displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '🔥 ${entry.currentStreak}',
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontFeatures: tabularFigures),
          ),
          if (!isMe)
            IconButton(
              icon: Opacity(
                opacity: applauded ? 0.35 : 1,
                child: const Text('👏', style: TextStyle(fontSize: 18)),
              ),
              tooltip: applauded ? 'Applauded today' : 'Applaud',
              onPressed: applauded
                  ? null
                  : () async {
                      final ok = await _social.applaud(entry);
                      if (ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'You applauded ${entry.profile.displayName}! 👏')));
                      }
                    },
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
    if (isMe) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FriendProfileScreen(entry: entry))),
      child: row,
    );
  }

  Widget _activityRow(ActivityItem item) {
    final (icon, text) = switch (item) {
      ApplauseReceived(:final from, :final streakDays) => (
          '👏',
          '${from?.displayName ?? 'A friend'} applauded your '
              '$streakDays-day streak',
        ),
      FriendJoined(:final friend) => (
          '🤝',
          'You and ${friend.displayName} are now friends',
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13.5, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            relativeTime(item.createdAt),
            style:
                const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ---- Actions ----

  Future<void> _invite() async {
    final messenger = ScaffoldMessenger.of(context);
    final url = await _social.createInviteUrl();
    if (url == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Couldn\'t create an invite. Check your connection.')));
      return;
    }
    final streak = StreakService.instance.currentStreak;
    final streakLine = streak > 1
        ? 'I\'m on a $streak-day piano practice streak with Scale Runner. '
        : 'I\'m practicing piano with Scale Runner. ';
    await SharePlus.instance.share(ShareParams(
      text: '$streakLine'
          'Add me as a friend so we can keep each other going!\n'
          '$url\n\n'
          'Don\'t have the app? $appShareUrl',
    ));
  }

  Future<void> _editName() async {
    final controller =
        TextEditingController(text: _social.profile?.displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxDisplayNameLength,
          decoration: const InputDecoration(hintText: 'Shown to friends'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || !mounted) return;
    final error = await _social.renameProfile(newName);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _editAvatar() async {
    final current = _social.profile?.avatarSeed ?? '';
    final seed = await AvatarPickerSheet.show(context, current);
    if (seed == null || !mounted) return;
    final error = await _social.updateAvatar(seed);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await _confirm(
      title: 'Sign out?',
      body: 'Your local streak stays on this device. Friends and applause '
          'come back when you sign in again.',
      confirmLabel: 'Sign out',
    );
    if (ok) await _social.signOut();
  }

  Future<void> _confirmDelete() async {
    final ok = await _confirm(
      title: 'Delete your account?',
      body: 'This permanently removes your profile, friendships, and synced '
          'streak from our servers. Your local practice data stays on this '
          'device. This can\'t be undone.',
      confirmLabel: 'Delete forever',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final success = await _social.deleteAccount();
    messenger.showSnackBar(SnackBar(
        content: Text(success
            ? 'Your account has been deleted.'
            : 'Couldn\'t delete the account. Check your connection.')));
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppColors.wrong)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
