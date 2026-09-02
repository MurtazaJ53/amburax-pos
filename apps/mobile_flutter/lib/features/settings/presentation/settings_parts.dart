import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/ui.dart';

/// Who you are and which shop you are in.
///
/// Sits at the top of Settings because "am I in the right shop?" is the
/// question that brings people here — a shopkeeper with two branches has
/// rung support over a figure that was simply the other shop's.
class SettingsShopCard extends StatelessWidget {
  const SettingsShopCard({super.key, required this.shop, this.session});

  final ShopInfo shop;
  final MobileSession? session;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final signedIn = session != null && session!.email.isNotEmpty
        ? session!.email
        : 'Local operator';

    return AppPanel(
      title: l.settingsShop,
      action: AppTag(
        label: '${shop.planLabel} plan',
        icon: Icons.workspace_premium_rounded,
        tone: AppTone.primary,
      ),
      child: Column(
        children: <Widget>[
          _InfoRow(
            icon: Icons.storefront_rounded,
            label: 'Shop',
            value: shop.name,
          ),
          _InfoRow(
            icon: Icons.person_rounded,
            label: 'Signed in',
            value: signedIn,
          ),
          _InfoRow(
            icon: Icons.badge_rounded,
            label: 'Role',
            value: session?.displayRoleLabel ?? 'GUEST',
            last: true,
          ),
        ],
      ),
    );
  }
}

/// Surfaces only when receipts are actually waiting.
///
/// An always-visible sync panel taught people to ignore it; this one appearing
/// means something needs doing.
class SettingsSyncPanel extends ConsumerWidget {
  const SettingsSyncPanel({super.key, required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final coordinator = ref.watch(mobileSyncCoordinatorProvider);

    return AppPanel(
      title: l.settingsSync,
      action: AppCountTag(
        count: pending,
        noun: 'queued',
        icon: Icons.cloud_upload_rounded,
        tone: AppTone.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$pending receipt${pending == 1 ? '' : 's'} waiting to sync.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Gap.sm),
          FilledButton.tonalIcon(
            onPressed: () async {
              final result = await coordinator.flushCommerceOutbox();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message ?? 'Retrying queued receipts.'),
                ),
              );
            },
            icon: const Icon(Icons.cloud_upload_rounded),
            label: const Text('Retry sync'),
          ),
        ],
      ),
    );
  }
}

/// One label/value line inside [SettingsShopCard].
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : Gap.sm),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colors.textTertiary),
          const SizedBox(width: Gap.sm),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textTertiary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
