# Scale Runner — Pro Unlock Setup

A one-time non-consumable "Pro" purchase unlocks the **Scale Running** drill.
Code uses RevenueCat (`purchases_flutter`). The app runs free until you fill in
real API keys, so you can build and test the rest of the app first.

Product ID used everywhere below: **`scale_runner_pro`** (pick your own, but keep
it identical in all three places). RevenueCat entitlement ID: **`pro`** (must
match `PurchaseService.proEntitlementId`).

Do the stores first, then RevenueCat, then drop the keys into the app.

---

## 1. App Store Connect (Apple)

1. **Agreements** → sign the *Paid Applications* agreement and complete banking +
   tax. IAPs will not load until this is "Active."
2. **My Apps → Scale Runner → Monetization → In-App Purchases → +**
   - Type: **Non-Consumable**
   - Reference Name: `Scale Runner Pro`
   - Product ID: `scale_runner_pro`
3. Set a price (choose a tier), add a localized display name + description.
4. Add a review screenshot of the paywall (required) and Save. It should reach
   **Ready to Submit** — it gets reviewed alongside your first build.
5. **Users and Access → Sandbox → Testers**: add a sandbox Apple ID to test
   purchases without being charged. Sign into it on the device under
   *Settings → App Store → Sandbox Account*.

## 2. Google Play Console

1. Create the app, then upload at least one build to a testing track (Internal
   testing is fine) — in-app products can't be tested until a build exists.
2. **Monetize → Products → In-app products → Create product**
   - Product ID: `scale_runner_pro`
   - Name, description, set a price, then **Activate**.
3. **Setup → License testing**: add your tester Google account so purchases are
   free in testing.
4. Make sure your tester is on the testing track (opt-in link) so the product
   resolves on-device.

## 3. RevenueCat dashboard

1. Create a free account, then a **Project** ("Scale Runner").
2. **Project settings → Apps**: add an **App Store** app and a **Play Store**
   app.
   - Apple: enter the bundle ID `com.scalerunner.app` and upload your
     **In-App Purchase Key** (App Store Connect → Users and Access → Integrations
     → In-App Purchase) so RevenueCat can validate receipts.
   - Google: upload the **Service Account credentials** JSON and grant it
     permissions in Play Console (RevenueCat's setup guide walks through this).
3. **Entitlements → +new**: identifier `pro`.
4. **Products → import/add** both store products (`scale_runner_pro` for each
   platform) and **attach them to the `pro` entitlement**.
5. **Offerings**: keep the `default` offering, add a Package (e.g. "Lifetime"),
   and attach the products. The paywall reads `offerings.current` — so this must
   exist or the price button falls back to a generic label.
6. **API keys** (Project → API keys): copy the **public** Apple key (`appl_…`)
   and Google key (`goog_…`). These are app keys, safe to ship. *Not* the secret
   key.

## 4. Drop keys into the app

In `lib/purchases/purchase_service.dart`, replace:

```dart
static const String _appleApiKey = 'appl_REPLACE_ME';
static const String _googleApiKey = 'goog_REPLACE_ME';
```

with the real public keys. If your product ID isn't `scale_runner_pro`, that's
fine — the app never hardcodes the product ID; it reads whatever is in the
`default` offering. Just keep the entitlement ID `pro` (or change it in both the
dashboard and `proEntitlementId`).

Then:

```sh
flutter pub get
cd ios && pod install && cd ..   # iOS only
```

## 5. Test the flow

- Free state: Scale Running card shows a **PRO** badge; tapping opens the paywall.
- Buy with a sandbox/license-test account → sheet closes, badge disappears, the
  drill opens.
- Delete and reinstall → tap **Restore purchase** → Pro returns. (Apple requires
  a visible Restore option; the paywall has one.)
- Cross-device: sign in with the same store account → Pro is already active.

## Notes

- **Why a free fallback:** with `REPLACE_ME` keys, `configure()` is a no-op and
  `isPro` stays false but nothing crashes — Scales and Chords work normally and
  the paywall shows a generic "Unlock Pro" button.
- **Commission / compliance:** the purchase runs through Apple/Google's native
  payment sheet. RevenueCat only validates the receipt and tracks the
  entitlement — fully within App Store and Play IAP rules.
- **What's free vs Pro today:** Scales and Chords are free; Scale Running is Pro.
  To gate more later, check `PurchaseService.instance.isPro` at that branch and
  call `PaywallSheet.show(context)` when false (see `home_screen.dart`).
