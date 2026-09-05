import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart' show Size;
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

  group('pianoWidthFor', () {
    // A landscape phone: the keyboard gets ~150pt of height, and under the
    // strict ratio that drew 15 keys ~26pt wide across half an 812pt screen.
    const phoneLandscape = Size(812, 375);
    // A landscape tablet is not compact, so it keeps a cap -- just a looser
    // one. 15 keys at 233pt tall want 15 * (233 / 3.2) ~= 1092pt.
    const tabletLandscape = Size(1180, 820);
    const phonePortrait = Size(375, 812);

    double width(Size viewport, double available, double height,
            {bool desktop = false}) =>
        pianoWidthFor(
          available: available,
          height: height,
          whiteKeyCount: 15,
          viewport: viewport,
          desktop: desktop,
        );

    test('a landscape phone fills the slot, cap and all', () {
      expect(width(phoneLandscape, 812, 143), 812);
    });

    test('a landscape tablet relaxes the ratio but still caps', () {
      final w = width(tabletLandscape, 1180, 233);
      expect(w, lessThan(1180));
      expect(w / 15, closeTo(233 / kWhiteKeyAspectLandscape, 0.01));
      // The point of the change: wider than the strict ratio would allow.
      expect(w, greaterThan(15 * (233 / kWhiteKeyAspect)));
    });

    test('portrait is untouched', () {
      // A portrait phone is narrower than even the strict cap, so it fills --
      // exactly as it did before this rule existed.
      expect(width(phonePortrait, 375, 240),
          maxKeyboardWidth(available: 375, height: 240, whiteKeyCount: 15));
      // A portrait tablet is wide enough for the cap to bite, and it still
      // bites at the strict ratio.
      final w = width(const Size(820, 1180), 820, 240);
      expect(w / 15, closeTo(240 / kWhiteKeyAspect, 0.01));
    });

    test('a landscape desktop window keeps the strict ratio', () {
      final w = width(const Size(1440, 900), 1440, 320, desktop: true);
      expect(w / 15, closeTo(320 / kWhiteKeyAspect, 0.01));
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
