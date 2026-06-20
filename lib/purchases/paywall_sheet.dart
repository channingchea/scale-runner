import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../theme/app_theme.dart';
import 'purchase_service.dart';

/// Bottom sheet that sells the one-time "Pro" unlock for Scale Running.
///
/// Returns `true` via [Navigator.pop] if the user ends up with Pro (bought or
/// restored), so callers can immediately proceed into the gated content.
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key});

  /// Show the paywall. Resolves to true if the user unlocked Pro.
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const PaywallSheet(),
    );
    return result ?? false;
  }

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  final _service = PurchaseService.instance;
  List<Package> _packages = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packages = await _service.proPackages();
    if (!mounted) return;
    setState(() {
      _packages = packages;
      _loading = false;
    });
  }

  /// The price string to show on the button. Falls back when offerings are
  /// unavailable (e.g. keys not set yet, or running on simulator).
  String get _priceLabel {
    if (_packages.isEmpty) return 'Unlock Pro';
    return 'Unlock Pro — ${_packages.first.storeProduct.priceString}';
  }

  Future<void> _buy() async {
    if (_packages.isEmpty) {
      _snack('Purchases aren\'t available right now. Try again later.');
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await _service.purchase(_packages.first);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _busy = false); // user cancelled
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Something went wrong with the purchase.');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final ok = await _service.restore();
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _busy = false);
        _snack('No previous purchase found to restore.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Couldn\'t restore purchases.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ShaderMask(
              shaderCallback: (b) => AppColors.accentGradient.createShader(b),
              child: const Text(
                'Scale Runner Pro',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'A one-time unlock — yours forever, on all your devices.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 22),
            const _Perk(
              icon: Icons.directions_run,
              title: 'Scale Running drill',
              subtitle:
                  'Run modes in time over chord progressions, key by key.',
            ),
            const _Perk(
              icon: Icons.all_inclusive,
              title: 'Every progression & key',
              subtitle: 'Full progression presets, sevenths, and key cycles.',
            ),
            const _Perk(
              icon: Icons.favorite_outline,
              title: 'Support development',
              subtitle: 'Help keep Scale Runner growing.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _buy,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF06251F)),
                    )
                  : Text(_loading ? 'Unlock Pro' : _priceLabel),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy ? null : _restore,
              child: const Text('Restore purchase',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
