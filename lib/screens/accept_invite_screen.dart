import 'package:flutter/material.dart';

import '../social/social_backend.dart';
import '../social/social_models.dart';
import '../social/social_service.dart';
import '../theme/app_theme.dart';
import '../widgets/social_widgets.dart';

/// Opened from an invite deep link. Shows who's inviting, then one tap to
/// become friends (with inline sign-in if needed).
class AcceptInviteScreen extends StatefulWidget {
  const AcceptInviteScreen({super.key, required this.code});

  final String code;

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final SocialService _social = SocialService.instance;
  InvitePreview? _preview;
  bool _loading = true;
  bool _busy = false;
  bool _accepted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _social.addListener(_onChange);
    _load();
  }

  @override
  void dispose() {
    _social.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _social.init();
    final preview = await _social.previewInvite(widget.code);
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _loading = false;
      if (preview == null) {
        _error = 'This invite link isn\'t valid anymore. '
            'Ask your friend for a new one.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friend invite')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const CircularProgressIndicator()
              : _preview == null
                  ? _message(Icons.link_off, _error!)
                  : _accepted
                      ? _message(
                          Icons.celebration,
                          'You and ${_preview!.displayName} are now '
                          'friends! Find them on your leaderboard.',
                        )
                      : _inviteCard(_preview!),
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text) => Column(
        children: [
          Icon(icon, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_accepted ? 'Nice' : 'Close'),
          ),
        ],
      );

  Widget _inviteCard(InvitePreview preview) {
    return SocialCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          SocialAvatar(seed: preview.avatarSeed, radius: 36),
          const SizedBox(height: 14),
          Text(
            preview.displayName,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          if (preview.currentStreak > 0) ...[
            const SizedBox(height: 4),
            Text(
              '🔥 ${preview.currentStreak}-day practice streak',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'wants to be practice friends on Scale Runner. You\'ll see each '
            'other\'s streaks and can cheer each other on.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (_busy)
            const CircularProgressIndicator()
          else if (_social.isSignedIn)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add as friend'),
                onPressed: _accept,
              ),
            )
          else ...[
            const Text(
              'Sign in to accept:',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (appleSignInAvailable)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.apple, size: 20),
                  label: const Text('Sign in with Apple'),
                  onPressed: () => _signInThenStay(_social.signInWithApple),
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
                  onPressed: () => _signInThenStay(_social.signInWithGoogle),
                ),
              ),
            if (!appleSignInAvailable && !googleSignInAvailable)
              const Text(
                'Sign-in isn\'t configured in this build yet.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _signInThenStay(Future<String?> Function() method) async {
    setState(() => _busy = true);
    final error = await method();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final error = await _social.acceptInvite(widget.code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _accepted = true;
      }
    });
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}
