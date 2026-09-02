import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

/// Lets a user who belongs to multiple shops switch the active workspace
/// without logging out. The current shop is marked; switching wipes the old
/// shop's local cache and loads the new one (full tenant isolation).
class ShopSwitcherScreen extends ConsumerStatefulWidget {
  const ShopSwitcherScreen({super.key});

  @override
  ConsumerState<ShopSwitcherScreen> createState() => _ShopSwitcherScreenState();
}

class _ShopSwitcherScreenState extends ConsumerState<ShopSwitcherScreen> {
  List<ShopMembershipAccessRecord> _shops = const [];
  bool _loading = true;
  bool _switching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    try {
      final shops = await ref
          .read(backendApiClientProvider)
          .getShopMemberships(user: session.user);
      setState(() {
        _shops = shops.where((s) => s.status == 'active').toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load your shops. $e';
      });
    }
  }

  Future<void> _switch(ShopMembershipAccessRecord shop) async {
    setState(() => _switching = true);
    final error = await ref
        .read(mobileSessionProvider.notifier)
        .switchShop(shop.shopId);
    if (!mounted) return;
    setState(() => _switching = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Switched to ${shop.shopName}.')));
      // Re-enter the app so every screen rebuilds against the new shop.
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final currentShopId = session?.shopId ?? '';

    return MobileStandaloneScaffold(
      title: 'Switch shop',
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          : _error != null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                if (_shops.length <= 1)
                  const AppPanel(
                    title: 'One workspace',
                    child: AppEmptyState(
                      icon: Icons.storefront_rounded,
                      title: 'You belong to one shop',
                      body:
                          'When you are invited to another shop, it will appear here so you can switch between them.',
                    ),
                  ),
                for (final shop in _shops)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ShopCard(
                      shop: shop,
                      isCurrent: shop.shopId == currentShopId,
                      disabled: _switching,
                      onTap: shop.shopId == currentShopId || _switching
                          ? null
                          : () => _switch(shop),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.shop,
    required this.isCurrent,
    required this.disabled,
    required this.onTap,
  });

  final ShopMembershipAccessRecord shop;
  final bool isCurrent;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent ? AppPalette.primary : colors.border,
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppPalette.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.shopName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${shop.roleLabel} · ${shop.shopPlanTier}',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                const MobileTag(
                  label: 'CURRENT',
                  icon: Icons.check_circle_rounded,
                  accent: AppPalette.success,
                )
              else
                Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
