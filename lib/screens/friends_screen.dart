import 'package:flutter/material.dart';

import '../social/social_models.dart';
import '../social/social_service.dart';
import '../theme/app_theme.dart';
import '../ui/responsive.dart';
import '../widgets/social_widgets.dart';
import 'friend_profile_screen.dart';

/// Full friends list with remove-friend.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final SocialService _social = SocialService.instance;

  @override
  void initState() {
    super.initState();
    _social.addListener(_onChange);
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
    final friends = _social.friends;
    return Scaffold(
      appBar: AppBar(title: const Text('Manage friends')),
      body: ContentColumn(
        child: friends.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No friends yet. Share an invite link from the Friends '
                    'screen to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: friends.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, i) {
                  final f = friends[i];
                  return ListTile(
                    leading: SocialAvatar(seed: f.profile.avatarSeed),
                    title: Text(f.profile.displayName),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => FriendProfileScreen(entry: f))),
                    subtitle: Text(
                      '🔥 ${f.currentStreak}-day streak · friends since '
                      '${relativeTime(f.friendsSince)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.person_remove_outlined),
                      color: AppColors.textMuted,
                      tooltip: 'Remove friend',
                      onPressed: () => _confirmRemove(f),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _confirmRemove(FriendEntry friend) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${friend.profile.displayName}?'),
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
    if (ok == true) await _social.removeFriend(friend.profile.id);
  }
}
