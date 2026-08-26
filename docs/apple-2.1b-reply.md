# Resolution Center reply — Guideline 2.1(b), submission 1b477a40-6311-4210-9cdb-68561e6ffbff

Send this **after** the new build (with the Settings → Unlock Pro entry point) is
uploaded and attached to version 1.0. Also re-add **Scale Runner Pro** to the
submission — it dropped back to *Ready to Submit* when the version was rejected,
so it will not go to review again unless it is explicitly added.

Before sending, confirm in **App Store Connect → Business** that the **Paid Apps
Agreement** is active — Apple's email raises it, and paid IAPs do not function
without it.

---

Hello,

Thank you for the review. You're right that the purchase was hard to reach in
build 8 — the paywall only appeared after a user had used up the free sessions
in a Pro mode, so a first-time reviewer would not have encountered it.

We've fixed that in this build. The in-app purchase is now reachable directly
from a fresh install, with no account, no MIDI keyboard and no prior use:

1. Launch the app to the home screen.
2. Tap the gear (Settings) icon in the icon row at the top of the home screen.
3. Scroll to the **PURCHASES** section and tap **Unlock Pro**.
4. The purchase sheet opens, showing the price and the **Unlock Pro** button.

Alternatively, on the home screen tap the gold **PRO** badge at the right of any
locked mode row (Scale Running, Inversion Running, or Jam Mode) — this opens the
same purchase sheet.

The product is "Scale Runner Pro" (com.scalerunner.app.pro), a one-time
non-consumable unlock. It is not restricted by storefront or device
configuration.

Please let us know if there's anything else you need.

Thank you,
Channing
