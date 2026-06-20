import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

/// Wraps RevenueCat for Scale Runner's single "Pro" one-time unlock.
///
/// RevenueCat sits on top of StoreKit (iOS/macOS) and Google Play Billing
/// (Android): the purchase still goes through the native store, RevenueCat
/// just validates the receipt server-side and tracks the [proEntitlementId]
/// entitlement. The app reads [isPro] to gate premium content.
///
/// Until real API keys are set below, [configure] is a safe no-op and [isPro]
/// stays false, so the app still runs in development and on unsupported
/// platforms (the keys are platform-specific).
class PurchaseService extends ChangeNotifier {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  /// DEV ONLY: when true, the paywall is bypassed and all Pro content is
  /// unlocked regardless of purchase state. Set back to false to re-enable the
  /// paywall before shipping. See PAYWALL_SETUP.md / scale-runner-paywall.
  static const bool _devUnlockAll = true;

  /// Entitlement identifier configured in the RevenueCat dashboard.
  /// Anything attached to this entitlement unlocks Pro content.
  static const String proEntitlementId = 'pro';

  /// Public SDK keys from RevenueCat → Project → API keys. These are *public*
  /// app keys (safe to ship), not the secret key. Fill both in before launch.
  static const String _appleApiKey = 'appl_REPLACE_ME';
  static const String _googleApiKey = 'goog_REPLACE_ME';

  bool _configured = false;
  bool _isPro = false;

  /// Whether the user owns the Pro unlock. False until proven true.
  /// Always true while [_devUnlockAll] is set (paywall bypassed for testing).
  bool get isPro => _devUnlockAll || _isPro;

  /// Whether RevenueCat initialised with a real key (false in dev/no-key mode).
  bool get isConfigured => _configured;

  /// Initialise the SDK. Call once at startup, after `WidgetsFlutterBinding`.
  /// Never throws — failures leave the app in free (non-Pro) mode.
  Future<void> configure() async {
    final apiKey = defaultTargetPlatform == TargetPlatform.android
        ? _googleApiKey
        : _appleApiKey;
    if (apiKey.contains('REPLACE_ME')) {
      // No key yet — run free so development isn't blocked.
      return;
    }
    try {
      await Purchases.configure(PurchasesConfiguration(apiKey));
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _onCustomerInfo(await Purchases.getCustomerInfo());
      _configured = true;
    } catch (e) {
      debugPrint('PurchaseService.configure failed: $e');
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(proEntitlementId);
    if (active != _isPro) {
      _isPro = active;
      notifyListeners();
    }
  }

  /// The current "default" offering's packages to display on the paywall.
  /// Returns an empty list if offerings can't be fetched.
  Future<List<Package>> proPackages() async {
    if (!_configured) return const [];
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? const [];
    } catch (e) {
      debugPrint('PurchaseService.proPackages failed: $e');
      return const [];
    }
  }

  /// Buy [package]. Returns true if the user now has Pro.
  /// Returns false on user cancellation; rethrows nothing — UI shows a snackbar.
  Future<bool> purchase(Package package) async {
    if (!_configured) return false;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return result.customerInfo.entitlements.active
          .containsKey(proEntitlementId);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    }
  }

  /// Restore prior purchases (Apple requires a visible Restore option).
  /// Returns true if Pro was restored.
  Future<bool> restore() async {
    if (!_configured) return false;
    final info = await Purchases.restorePurchases();
    return info.entitlements.active.containsKey(proEntitlementId);
  }
}
