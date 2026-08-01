// Cloudflare Worker for scalerunner.c1gnus.com
//
// Serves three things:
//   1. /.well-known/apple-app-site-association  → iOS Universal Links
//   2. /.well-known/assetlinks.json             → Android App Links
//   3. /invite/<code>                           → invite landing page
//      (installed app intercepts the URL before the browser ever loads it;
//       this page is the fallback for people without the app)
//
// Deploy: see README.md in this folder.

const APPLE_TEAM_ID = '9LTD86C5X7'; // Xcode DEVELOPMENT_TEAM / App ID Prefix
// Play Console → Protected with Play → App signing → Digital Asset Links JSON.
// (Play App Signing key, not the upload key — re-copy it if you ever rotate.)
const ANDROID_SHA256_FINGERPRINT =
  '6A:F2:22:0C:A7:E5:42:E9:16:AB:16:A2:76:F1:8C:2D:A3:8B:2A:20:A1:DB:74:A0:E3:EC:8F:0D:A1:82:A4:E7';
const APP_STORE_URL = 'https://apps.apple.com/app/id6795850810';
const PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.scalerunner.app';

const BUNDLE_ID = 'com.scalerunner.app';

const AASA = {
  applinks: {
    apps: [],
    details: [
      {
        appIDs: [`${APPLE_TEAM_ID}.${BUNDLE_ID}`],
        components: [{ '/': '/invite/*' }],
      },
    ],
  },
};

const ASSETLINKS = [
  {
    relation: ['delegate_permission/common.handle_all_urls'],
    target: {
      namespace: 'android_app',
      package_name: BUNDLE_ID,
      sha256_cert_fingerprints: [ANDROID_SHA256_FINGERPRINT],
    },
  },
];

function invitePage(code) {
  const appUrl = `scalerunner://invite/${encodeURIComponent(code)}`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Scale Runner — Friend invite</title>
<style>
  body { margin:0; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
         background:#0F141B; color:#E8ECF1; display:flex; min-height:100vh;
         align-items:center; justify-content:center; text-align:center; }
  .card { max-width:340px; padding:40px 28px; }
  h1 { font-size:22px; margin:16px 0 8px;
       background:linear-gradient(135deg,#36D6C3,#1FA396);
       -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
  p { color:#94A1B2; font-size:14px; line-height:1.5; }
  .emoji { font-size:52px; }
  a.btn { display:block; margin-top:14px; padding:14px 20px; border-radius:10px;
          background:#36D6C3; color:#06251F; font-weight:700; text-decoration:none; }
  a.btn.alt { background:#1F2835; color:#E8ECF1; border:1px solid #2C3645; }
</style>
</head>
<body>
<div class="card">
  <div class="emoji">🎹</div>
  <h1>You've been invited!</h1>
  <p>A friend wants to be practice buddies on Scale Runner —
     the MIDI piano practice app.</p>
  <a class="btn" href="${appUrl}">Open in the app</a>
  <a class="btn alt" id="store" href="${APP_STORE_URL}">Get Scale Runner</a>
  <p style="font-size:12px;color:#5B6878">After installing, tap your invite
     link again to add your friend.</p>
</div>
<script>
  // Point the store button at the right store, and try the app once via the
  // custom scheme (a no-op when the app isn't installed).
  if (/android/i.test(navigator.userAgent)) {
    document.getElementById('store').href = '${PLAY_STORE_URL}';
  }
  setTimeout(function () { window.location.href = '${appUrl}'; }, 400);
</script>
</body>
</html>`;
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const json = (obj) =>
      new Response(JSON.stringify(obj), {
        headers: { 'Content-Type': 'application/json' },
      });

    if (url.pathname === '/.well-known/apple-app-site-association') {
      return json(AASA);
    }
    if (url.pathname === '/.well-known/assetlinks.json') {
      return json(ASSETLINKS);
    }
    const invite = url.pathname.match(/^\/invite\/([A-Za-z0-9]+)$/);
    if (invite) {
      return new Response(invitePage(invite[1]), {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }
    return Response.redirect('https://c1gnus.com', 302);
  },
};
