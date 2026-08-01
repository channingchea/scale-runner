import 'package:flutter/foundation.dart' show kDebugMode;

/// Supabase + deep-link configuration for the social features.
///
/// The publishable key is safe to ship in the client — all data access is
/// enforced by Postgres row-level security.
const String supabaseUrl = 'https://mbikuewjbvxndzhdorav.supabase.co';
const String supabasePublishableKey =
    'sb_publishable_G4vXv2geTZT7OR6NCLN1NQ_pIOOYVWr';

/// UI-preview-only switch: set true to make SocialService skip Supabase and
/// load MockSocialBackend's seeded friends/activity instead.
///
/// Only honoured in debug builds. A release build ignores this entirely (see
/// [kMockSocialData]), because shipping it true replaces the sign-in card
/// with a fake signed-in account and five invented friends — which is exactly
/// what happened in beta build 2.
const bool kMockSocialDataRequested = false;

/// Whether mock social data is actually in use. Structurally false in any
/// release build, so mock friends can never reach the stores or TestFlight
/// no matter what [kMockSocialDataRequested] is left set to.
const bool kMockSocialData = kDebugMode && kMockSocialDataRequested;

/// The **web** OAuth client ID from the Google Cloud console (project
/// `scale-runner`). google_sign_in uses it as the serverClientId so the ID
/// tokens it mints are accepted by Supabase. Google sign-in is hidden while
/// this is empty. Must match a Supabase → Auth → Google "Client IDs" entry.
const String googleServerClientId =
    '1055426007613-o9apbh9ss4jk3h365evihij5ciodb9j3.apps.googleusercontent.com';

/// Invite links: https://scalerunner.c1gnus.com/invite/<code>, served by
/// web_hosting/worker.js (Cloudflare Worker) which also hosts the
/// apple-app-site-association / assetlinks.json files for app links.
const String inviteHost = 'scalerunner.c1gnus.com';
const String inviteBaseUrl = 'https://$inviteHost/invite';

/// Custom-scheme fallback the redirect page uses: scalerunner://invite/<code>
const String inviteScheme = 'scalerunner';

/// Extracts an invite code from a deep link, or null if [uri] isn't one.
/// Accepts both https://scalerunner.c1gnus.com/invite/<code> and
/// scalerunner://invite/<code>.
String? inviteCodeFromUri(Uri uri) {
  final isHttps = uri.scheme == 'https' &&
      uri.host == inviteHost &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments[0] == 'invite';
  final isCustom = uri.scheme == inviteScheme &&
      uri.host == 'invite' &&
      uri.pathSegments.isNotEmpty;
  if (isHttps) return uri.pathSegments[1];
  if (isCustom) return uri.pathSegments[0];
  return null;
}
