# Social features — remaining manual setup

The code, database, and tests are done. These steps need accounts/consoles
only you can access, then a two-device test.

## 1. Sign in with Apple (needed before any sign-in works)

1. Apple Developer portal → Certificates, IDs & Profiles → Identifiers →
   `com.scalerunner.app` → enable **Sign in with Apple**.
2. Xcode picks up `ios/Runner/Runner.entitlements` automatically (already
   wired into the project). Build once on a device to confirm signing.
3. Supabase dashboard → Authentication → Sign In / Providers → Apple →
   enable. For native iOS sign-in, add `com.scalerunner.app` to
   **Authorized Client IDs**. (No secret key needed for native-only flow.)

## 2. Google sign-in (optional; Android's only option, so needed for Android)

1. Google Cloud console → create OAuth client IDs: one **Web** (this is the
   "server client ID"), one **Android** (package `com.scalerunner.app` +
   debug/release SHA-1), one **iOS** (bundle `com.scalerunner.app`).
2. Supabase → Authentication → Providers → Google → enable, paste the Web
   client ID into **Authorized Client IDs**.
3. Paste the Web client ID into `googleServerClientId` in
   `lib/social/social_config.dart` (Google button is hidden until set).
4. iOS also needs the reversed iOS client ID added as a URL scheme in
   `ios/Runner/Info.plist` (google_sign_in README shows the exact block).

## 3. Invite-link hosting

Follow `web_hosting/README.md` — paste `worker.js` into a Cloudflare Worker
and attach the custom domain `scalerunner.c1gnus.com`. Fill in the Android
keystore SHA-256 (and real store URLs at launch).

## 4. On-device verification (the plan's end-to-end check)

Two devices / two accounts:
1. Sign in on both (Stats → sign-in card, or the Friends icon on Home).
2. Practice on device A → streak row appears in Supabase `streaks`.
3. A: Friends → Invite → share link; B: tap link → accept → both see each
   other on the leaderboard.
4. B: applaud A's streak → A sees activity + badge; second tap same day is
   blocked.
5. A: remove friend, sign out, sign back in; try Delete account with a
   throwaway account.

## Known placeholders

- `appShareUrl` App Store ID (`id0000000000`) — replace at launch (also in
  `web_hosting/worker.js`).
- Android release keystore SHA-256 in `worker.js` + Google console.
- Display names ship with a length/character filter only; consider a report
  mechanism if App Store review asks.
