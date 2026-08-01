# Invite-link hosting (scalerunner.c1gnus.com)

`https://scalerunner.c1gnus.com/invite/<code>` is the friend-invite link the
app generates. For it to work, that host must serve three things:

| Path | Purpose |
| --- | --- |
| `/.well-known/apple-app-site-association` | iOS Universal Links |
| `/.well-known/assetlinks.json` | Android App Links |
| `/invite/<code>` | Landing page for people without the app |

`c1gnus.com` uses Hostinger's nameservers (`atlas.dns-parking.com` /
`hyperion.dns-parking.com`), so the host is a Hostinger subdomain and the
files are plain static files. **`hostinger/` is what goes on the server.**

## Deploy

1. **hPanel → Domains → Subdomains** → create `scalerunner` under
   `c1gnus.com`. Note the document root it gives you (usually
   `public_html/scalerunner`).
2. **hPanel → SSL** → issue the free certificate for the new subdomain and
   wait until it shows Active. Apple and Google both refuse to fetch the
   association files over plain HTTP.
3. **hPanel → File Manager** → open the subdomain's document root, upload
   `scalerunner-invite-host.zip`, and extract it there. Turn on "show hidden
   files" and confirm both `.htaccess` and `.well-known/` landed — File
   Manager hides dot-entries by default and it is easy to think the extract
   dropped them.
4. Verify (all three must succeed, from anywhere):
   ```
   curl -sI https://scalerunner.c1gnus.com/.well-known/apple-app-site-association
   curl -s  https://scalerunner.c1gnus.com/.well-known/assetlinks.json
   curl -sI https://scalerunner.c1gnus.com/invite/TEST
   ```
   The first two must return `200` with **no redirect** — a `301` on these
   paths is the single most common reason app-link verification fails.

## What's in the association files

- **Apple Team ID `9LTD86C5X7`** (CYGNUS INNOVATIONS, LLC), bundle
  `com.scalerunner.app`. This must match `ios/Runner/Runner.entitlements`
  (`applinks:scalerunner.c1gnus.com`) and Xcode's `DEVELOPMENT_TEAM`.
- **Three** Android SHA-256 fingerprints, deliberately — App Links verify
  against whatever key actually signed the installed APK, so every channel
  the app reaches a device through needs an entry:
  - `6A:F2:…:E7` — Play App Signing key, for Play Store installs.
  - `F4:D1:…:72` — **upload key** (`android/key.properties`, alias
    `upload`, SHA-1 `41:C4:6E:…`). This is what signs the Firebase App
    Distribution beta APK, verified with `apksigner verify --print-certs`.
    Without it, App Links do not verify for current beta testers.
  - `E2:B9:…:F3` — local debug keystore, for `flutter run` installs.

  Note the beta APK is **not** debug-signed — `android/app/build.gradle.kts`
  falls back to debug signing only when `key.properties` is absent, and it is
  present. Re-check with `apksigner` after any signing change rather than
  assuming.

## Notes

- iOS caches the AASA at install time via Apple's CDN. After deploying,
  **reinstall** the app on the test device — updating in place won't re-fetch.
- Android re-verifies App Links on install/update. To check on a device:
  `adb shell pm get-app-links com.scalerunner.app`.
- `/invite/<code>` is one static page; `.htaccess` rewrites every code to it
  and the page reads the code out of `location.pathname`. Nothing is
  generated per invite.
- The app also registers `scalerunner://invite/<code>` as a fallback scheme,
  which the landing page triggers automatically.
- `worker.js` is the equivalent Cloudflare Worker, kept only as an
  alternative if `c1gnus.com` ever moves to Cloudflare DNS. It is **not**
  deployed and is not the source of truth — `hostinger/` is.

## Known gap: the "Get Scale Runner" button

Both store URLs (`apps.apple.com/app/id6795850810` and the Play listing)
currently return **404** — the app is in TestFlight and Play internal testing,
not publicly released. Anyone tapping an invite without the app installed hits
a dead page. Same URLs back `appShareUrl` in `lib/widgets/streak_sheets.dart`.
Either point them at the beta invites during the beta
(`https://testflight.apple.com/join/vMhnCACs`,
`https://appdistribution.firebase.google.com/i/a3847e100f0ac630`) or accept
the dead link until launch.
