import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../shell/presentation/mobile_surface.dart';

const String _kOnboardingKey = 'onboarding_completed';

/// True until the owner finishes (or skips) first-run setup.
final needsOnboardingProvider = FutureProvider<bool>((ref) async {
  final done = await ref
      .watch(shopRepositoryProvider)
      .readSetting(_kOnboardingKey);
  return done != '1';
});

/// First-run setup.
///
/// A new shopkeeper otherwise lands in a completely empty app with no idea
/// what to do first. This asks only for the things that change what the app
/// can do — the shop's name (it prints on every bill), a UPI ID (turns on
/// collect-QRs), and a first product so the POS isn't a blank screen.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  final PageController _pages = PageController();
  final TextEditingController _shopName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _upi = TextEditingController();
  final TextEditingController _itemName = TextEditingController();
  final TextEditingController _itemPrice = TextEditingController();
  final TextEditingController _itemStock = TextEditingController();

  int _step = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final shop = ref.read(shopInfoProvider).asData?.value;
    _shopName.text = shop?.name ?? '';
    _phone.text = shop?.phone ?? '';
    _upi.text = shop?.upiVpa ?? '';
  }

  @override
  void dispose() {
    _pages.dispose();
    _shopName.dispose();
    _phone.dispose();
    _upi.dispose();
    _itemName.dispose();
    _itemPrice.dispose();
    _itemStock.dispose();
    super.dispose();
  }

  Future<void> _markDone() async {
    await ref.read(shopRepositoryProvider).writeSetting(_kOnboardingKey, '1');
    ref.invalidate(needsOnboardingProvider);
  }

  Future<void> _skip() async {
    await _markDone();
    if (mounted) context.go('/');
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
      _pages.animateToPage(
        _step,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final coordinator = ref.read(mobileSyncCoordinatorProvider);
    final shop =
        ref.read(shopInfoProvider).asData?.value ?? ShopInfo.fallback();

    try {
      // saveShopDocument does a full overwrite, so fall back to the current
      // value for anything left blank — skipping a step must never wipe a
      // detail the shop already had.
      await ref.read(shopRepositoryProvider).saveShopDocument(<String, dynamic>{
        'name': _shopName.text.trim().isEmpty
            ? shop.name
            : _shopName.text.trim(),
        'tagline': shop.tagline,
        'footer': shop.footer,
        'currency': shop.currency,
        'business_phone': _phone.text.trim().isEmpty
            ? shop.phone
            : _phone.text.trim(),
        'gstin': shop.gstin,
        'upi_vpa': _upi.text.trim().isEmpty ? shop.upiVpa : _upi.text.trim(),
        'plan_tier': shop.planTier,
        'enabled_features': shop.enabledFeatures,
      });

      final price = double.tryParse(_itemPrice.text.trim()) ?? 0;
      if (_itemName.text.trim().isNotEmpty && price > 0) {
        await coordinator.createInventoryItem(
          name: _itemName.text.trim(),
          sellPrice: price,
          openingStock: double.tryParse(_itemStock.text.trim()) ?? 0,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save everything: $error')),
        );
      }
    }

    await _markDone();
    if (mounted) {
      setState(() => _saving = false);
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MobileStandaloneScaffold(
      title: L.of(context).welcomeSetup,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Row(
              children: <Widget>[
                for (var i = 0; i < 3; i++) ...<Widget>[
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _step
                            ? AppPalette.primary
                            : colors.border.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                _Step(
                  icon: Icons.storefront_rounded,
                  title: 'Your shop',
                  body: 'This name prints on every bill you give a customer.',
                  children: <Widget>[
                    TextField(
                      controller: _shopName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Shop name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Shop mobile number',
                        helperText: 'Used for your daily summary on WhatsApp',
                      ),
                    ),
                  ],
                ),
                _Step(
                  icon: Icons.qr_code_2_rounded,
                  title: 'Take UPI payments',
                  body:
                      'Add your UPI ID and the app can show a scan-to-pay QR '
                      'for the exact bill amount.',
                  children: <Widget>[
                    TextField(
                      controller: _upi,
                      decoration: const InputDecoration(
                        labelText: 'UPI ID',
                        hintText: 'yourname@okhdfcbank',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can add this later from Business settings.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                _Step(
                  icon: Icons.inventory_2_rounded,
                  title: 'Add your first product',
                  body:
                      'One item is enough to start billing. You can import '
                      'the rest later from a spreadsheet.',
                  children: <Widget>[
                    TextField(
                      controller: _itemName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Product name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _itemPrice,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Selling price',
                              prefixText: '₹ ',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _itemStock,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'In stock',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            child: Column(
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _next,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(
                      _saving
                          ? 'Saving...'
                          : (_step == 2 ? 'Finish setup' : 'Continue'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _skip,
                  child: Text(L.of(context).welcomeSkip),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: AppPalette.primary, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}
