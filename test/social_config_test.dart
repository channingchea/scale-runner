import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/social/social_config.dart';

/// Guards the release-blocker that shipped in beta build 2: mock social data
/// left enabled, which replaced the sign-in card with a fake signed-in
/// account and five invented friends.
void main() {
  test('mock social data is not requested', () {
    // If this fails you left the preview toggle on. Set
    // kMockSocialDataRequested back to false before building.
    expect(kMockSocialDataRequested, isFalse);
  });

  test('mock social data is structurally impossible in a release build', () {
    // kMockSocialData must stay gated on kDebugMode, so that even a stray
    // `kMockSocialDataRequested = true` cannot reach TestFlight or the stores.
    expect(kMockSocialData, kDebugMode && kMockSocialDataRequested);
    expect(kMockSocialData, isFalse);
  });

  test('invite links parse from both https and custom-scheme URIs', () {
    expect(inviteCodeFromUri(Uri.parse('$inviteBaseUrl/ABC123')), 'ABC123');
    expect(
        inviteCodeFromUri(Uri.parse('$inviteScheme://invite/ABC123')), 'ABC123');
    expect(inviteCodeFromUri(Uri.parse('https://example.com/invite/ABC123')),
        isNull);
  });
}
