import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/ui/responsive.dart';
import 'package:scale_runner/widgets/streak_sheets.dart';

/// Covers the layout rules that decide how the app renders in a freely
/// resizable desktop window, and the one share link that used to resolve
/// wrongly on macOS.
void main() {
  group('isCompactLayout', () {
    test('engages only below the 500px threshold', () {
      expect(isCompactLayout(499), isTrue);
      expect(isCompactLayout(500), isFalse);
      expect(isCompactLayout(900), isFalse);
    });

    test('is a function of height alone', () {
      // The old version ANDed this with a "phone or tablet" platform check,
      // so a short desktop window — the case the compact layout exists for —
      // could never trigger it.
      expect(isCompactLayout(320), isTrue);
    });
  });

  group('maxKeyboardWidth', () {
    test('caps a wide window to piano-ish proportions', () {
      // 15 white keys at 240px tall want ~655px, well under a 1440px window.
      final w = maxKeyboardWidth(
          available: 1440, height: 240, whiteKeyCount: 15);
      expect(w, lessThan(1440));
      expect(w / 15, closeTo(240 / kWhiteKeyAspect, 0.01));
    });

    test('never widens beyond what is available', () {
      expect(maxKeyboardWidth(available: 380, height: 240, whiteKeyCount: 15),
          380);
    });

    test('degrades safely on nonsense input', () {
      expect(
          maxKeyboardWidth(available: 500, height: 0, whiteKeyCount: 15), 500);
      expect(
          maxKeyboardWidth(available: 500, height: 240, whiteKeyCount: 0), 500);
    });
  });

  group('appShareUrl', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('macOS shares the App Store listing, not Google Play', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(appShareUrl, contains('apps.apple.com'));
    });

    test('iOS shares the App Store listing', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(appShareUrl, contains('apps.apple.com'));
    });

    test('Android shares the Play listing', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(appShareUrl, contains('play.google.com'));
    });
  });
}
