import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'midi/midi_service.dart';
import 'purchases/purchase_service.dart';
import 'notifications/notification_service.dart';
import 'screens/accept_invite_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'social/social_config.dart';
import 'social/social_service.dart';
import 'streak/streak_service.dart';

/// Lets deep links push screens from outside the widget tree.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  PurchaseService.instance.configure();
  SocialService.instance.init();
  // Practicing reshuffles the reminder schedule (cancel today's, push the
  // win-back out) and pushes the streak to friends. Fire-and-forget:
  // neither ever blocks the UI.
  StreakService.instance.onPracticeRecorded = (_) {
    NotificationService.instance.resync();
    SocialService.instance.syncStreak();
  };
  StreakService.instance.init().then(
      (_) => NotificationService.instance.resync());
  runApp(const ScaleRunnerApp());
}

class ScaleRunnerApp extends StatefulWidget {
  const ScaleRunnerApp({super.key});

  @override
  State<ScaleRunnerApp> createState() => _ScaleRunnerAppState();
}

class _ScaleRunnerAppState extends State<ScaleRunnerApp> {
  final MidiService _midi = MidiService();
  StreamSubscription<Uri>? _linkSub;
  String? _lastInviteCode; // dedupes initial-link double delivery

  @override
  void initState() {
    super.initState();
    _midi.start();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Guarded: the plugin is absent in widget tests, and a broken link
    // listener must never take the app down.
    try {
      final appLinks = AppLinks();
      final initial = await appLinks.getInitialLink();
      if (initial != null) _handleLink(initial);
      _linkSub = appLinks.uriLinkStream.listen(_handleLink);
    } catch (e) {
      debugPrint('Deep links unavailable: $e');
    }
  }

  void _handleLink(Uri uri) {
    final code = inviteCodeFromUri(uri);
    if (code == null || code == _lastInviteCode) return;
    _lastInviteCode = code;
    navigatorKey.currentState
        ?.push(MaterialPageRoute(
            builder: (_) => AcceptInviteScreen(code: code)))
        // Clear the dedupe once the screen closes so tapping the same link
        // again (as the invite page tells fresh installs to do) works.
        .whenComplete(() => _lastInviteCode = null);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _midi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scale Runner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: navigatorKey,
      home: SplashScreen(child: HomeScreen(midi: _midi)),
    );
  }
}
