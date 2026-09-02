import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

const List<String> _currencies = <String>['INR', 'USD', 'GBP', 'AED'];

/// Editable business/shop details — the core of the old app's Settings:
/// name, tagline, phone, receipt footer and currency. Used on receipts.
class SettingsBusinessScreen extends ConsumerStatefulWidget {
  const SettingsBusinessScreen({super.key});

  @override
  ConsumerState<SettingsBusinessScreen> createState() =>
      _SettingsBusinessScreenState();
}

class _SettingsBusinessScreenState
    extends ConsumerState<SettingsBusinessScreen> {
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _phone = TextEditingController();
  final _gstin = TextEditingController();
  final _upi = TextEditingController();
  final _footer = TextEditingController();
  String _currency = 'INR';
  bool _loaded = false;
  bool _saving = false;

  void _hydrate(ShopInfo shop) {
    if (_loaded) return;
    _name.text = shop.name;
    _tagline.text = shop.tagline;
    _phone.text = shop.phone;
    _gstin.text = shop.gstin;
    _upi.text = shop.upiVpa;
    _footer.text = shop.footer;
    _currency = _currencies.contains(shop.currency) ? shop.currency : 'INR';
    _loaded = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _phone.dispose();
    _gstin.dispose();
    _upi.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _save(ShopInfo shop) async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business name is required.')),
      );
      return;
    }
    final upi = _upi.text.trim();
    if (upi.isNotEmpty &&
        !RegExp(r'^[\w.\-]{1,256}@[a-zA-Z]{2,64}$').hasMatch(upi)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid UPI ID (e.g. name@bank).')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // Via the coordinator so these reach the server: the website and any
      // other device read the same shop details.
      await ref.read(mobileSyncCoordinatorProvider).saveBusinessDetails(
        <String, dynamic>{
          'name': _name.text.trim(),
          'tagline': _tagline.text.trim(),
          'footer': _footer.text.trim(),
          'currency': _currency,
          'business_phone': _phone.text.trim(),
          'gstin': _gstin.text.trim(),
          'upi_vpa': upi,
          // Preserve plan + features (saveShopDocument does a full overwrite).
          'plan_tier': shop.planTier,
          'enabled_features': shop.enabledFeatures,
        },
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Business details saved.')));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    _hydrate(shop);
    final colors = AppColors.of(context);

    return MobileStandaloneScaffold(
      title: 'Business details',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          AppPanel(
            title: 'Business',
            action: const MobileTag(
              label: 'ON RECEIPTS',
              icon: Icons.receipt_long_rounded,
            ),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 4),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Business name'),
                ),
                const SizedBox(height: 14),
                TextField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: _tagline,
                  decoration: const InputDecoration(
                    labelText: 'Tagline / subtitle',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _gstin,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN (optional)',
                    hintText: 'Shown on GST tax invoices',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Payments',
            action: const MobileTag(
              label: 'UPI QR',
              icon: Icons.qr_code_2_rounded,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 4),
                TextField(
                  controller: _upi,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'UPI ID (optional)',
                    hintText: 'e.g. yourname@okhdfcbank',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Used to auto-generate a UPI QR at checkout with the exact '
                  'bill amount, so customers pay straight into this account. '
                  'Applies to every cashier on this shop.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Receipt',
            action: const MobileTag(
              label: 'PRINTED',
              icon: Icons.print_rounded,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 4),
                TextField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: _footer,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Receipt footer',
                    hintText: 'Thank you for your business!',
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Currency',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _currencies
                      .map(
                        (c) => ChoiceChip(
                          label: Text(c),
                          selected: _currency == c,
                          onSelected: (_) => setState(() => _currency = c),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _saving ? null : () => _save(shop),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving...' : 'Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}
