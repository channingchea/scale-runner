import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// In-app splash shown briefly on launch. On iOS/Android the native splash
/// (flutter_native_splash) covers cold start; this gives macOS — which has no
/// native splash support — a matching branded launch screen, and keeps the
/// look consistent across platforms. Background matches the app icon (#171E28).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.child});

  /// The screen to show once the splash completes.
  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _done
          ? widget.child
          : Container(
              key: const ValueKey('splash'),
              color: AppColors.surface, // #171E28 — same as app icon background
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 128,
                  height: 128,
                  fit: BoxFit.cover,
                ),
              ),
            ),
    );
  }
}
