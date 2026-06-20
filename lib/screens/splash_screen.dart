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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _done = false;
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  @override
  void initState() {
    super.initState();

    // Logo entrance: fade + scale up over 600ms
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );
    _logoController.forward();

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: _done
          ? widget.child
          : Container(
              key: const ValueKey('splash'),
              color: AppColors.surface,
              alignment: Alignment.center,
              child: FadeTransition(
                opacity: _logoOpacity,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: Image.asset(
                    'assets/icon/icon_splash.png',
                    width: 200,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
    );
  }
}
