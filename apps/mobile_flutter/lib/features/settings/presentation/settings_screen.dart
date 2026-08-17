import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/app_runtime_info.dart';
import '../../../core/runtime/mobile_runtime_config.dart';
import 'shop_switcher_screen.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_theme.dart';
import '../../shell/presentation/mobile_surface.dart';

/// Clean, shop-owner-first settings.
///
/// Day-to-day controls only. Internal/ops tooling (pulse, device sessions,
/// advanced ops) lives behind the single "Admin tools" entry.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    final pending = ref.watch(pendingOutboxCountProvider).asData?.value ?? 0;
    final version = ref.watch(appRuntimeInfoProvider).asData?.value.versionLabel;
    final syncCoordinator = ref.watch(mobileSyncCoordinatorProvider);

    final l = L.of(context);
    final owner = session?.isOwnerLike ?? false;
    // Manager and above. Several screens here are computed on the device from
    // its own database, so the server's role check never runs — the gate has
    // to be repeated here or the two platforms disagree about who may look.
    final managerUp = owner || (session?.isManager ?? false);

    return MobileStandaloneScaffold(
      title: l.settingsTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          // Shop identity
          MobilePanel(
            title: l.settingsShop,
            action: MobileTag(
              label: '${shop.planLabel} plan',
              icon: Icons.workspace_premium_rounded,
              accent: AppPalette.primary,
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
                  value: session != null && session.email.isNotEmpty
                      ? session.email
                      : 'Local operator',
                ),
                _InfoRow(
                  icon: Icons.badge_rounded,
                  label: 'Role',
                  value: session?.displayRoleLabel ?? 'GUEST',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Manage
          const _SectionLabel('Manage'),
          if (owner)
            MobileListTile(
              title: l.settingsBusiness,
              subtitle: l.settingsBusinessSub,
              leadingIcon: Icons.storefront_rounded,
              onTap: () => context.push('/settings/business'),
            ),
          if (owner)
            MobileListTile(
              title: l.settingsStaff,
              subtitle: l.settingsStaffSub,
              leadingIcon: Icons.badge_rounded,
              onTap: () => context.push('/settings/staff'),
            ),
          if (owner)
            MobileListTile(
              title: l.settingsTeam,
              subtitle: l.settingsTeamSub,
              leadingIcon: Icons.groups_rounded,
              onTap: () => context.push('/settings/team'),
            ),
          if (MobileRuntimeConfig.backendAuthMode == 'jwt')
            MobileListTile(
              title: l.settingsSwitchShop,
              subtitle: l.settingsSwitchShopSub,
              leadingIcon: Icons.swap_horiz_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ShopSwitcherScreen(),
                ),
              ),
            ),
          if (shop.supportsAttendance)
            MobileListTile(
              title: l.settingsAttendance,
              subtitle: l.settingsAttendanceSub,
              leadingIcon: Icons.fact_check_rounded,
              onTap: () => context.push('/settings/attendance'),
            ),
          if (shop.supportsExpenses)
            MobileListTile(
              title: l.settingsExpenses,
              subtitle: l.settingsExpensesSub,
              leadingIcon: Icons.payments_rounded,
              onTap: () => context.push('/settings/expenses'),
            ),
          MobileListTile(
            title: l.settingsLanguage,
            subtitle: l.settingsLanguageSubtitle,
            leadingIcon: Icons.translate_rounded,
            onTap: () => context.push('/settings/language'),
          ),
          MobileListTile(
            title: l.settingsPurchases,
            subtitle: l.settingsPurchasesSub,
            leadingIcon: Icons.local_shipping_rounded,
            onTap: () => context.push('/settings/purchases'),
          ),
          // The 09:00 low-stock alert and the 21:00 takings summary were being
          // sent to owners who had nowhere in the app to read them.
          MobileListTile(
            title: 'Alerts',
            subtitle: 'Low stock in the morning, takings at night',
            leadingIcon: Icons.notifications_active_rounded,
            onTap: () => context.push('/settings/alerts'),
          ),
          MobileListTile(
            title: 'Day book (Roj Mel)',
            subtitle: 'What came in today, and what went out on credit',
            leadingIcon: Icons.menu_book_rounded,
            onTap: () => context.push('/settings/day-book'),
          ),
          // Both of these are for the person at the back door with cartons in
          // their hands, which is why they belong on the phone at all.
          MobileListTile(
            title: 'Purchase orders',
            subtitle: 'What you ordered, and what actually arrived',
            leadingIcon: Icons.receipt_long_rounded,
            onTap: () => context.push('/settings/purchase-orders'),
          ),
          MobileListTile(
            title: 'Stock transfers',
            subtitle: 'Move stock between your shops',
            leadingIcon: Icons.swap_horiz_rounded,
            onTap: () => context.push('/settings/transfers'),
          ),
          // Counting happens on your feet in front of a shelf, so staff reach
          // it too — applying the count is what needs a manager, and the
          // screen itself says so.
          MobileListTile(
            title: 'Stocktake',
            subtitle: 'Count the shelves and fix what the books say',
            leadingIcon: Icons.fact_check_rounded,
            onTap: () => context.push('/settings/stocktake'),
          ),
          // The plan screen and its route already existed but nothing linked to
          // it, so owners had no way to see or change their plan in the app.
          if (owner)
            MobileListTile(
              title: l.settingsPlanBilling,
              subtitle: l.settingsPlanBillingSub,
              leadingIcon: Icons.workspace_premium_rounded,
              onTap: () => context.push('/settings/billing'),
            ),
          if (owner)
            MobileListTile(
              title: l.settingsComparePlans,
              subtitle: l.settingsComparePlansSub,
              leadingIcon: Icons.compare_arrows_rounded,
              onTap: () => context.push('/settings/plan'),
            ),

          if (owner)
            MobileListTile(
              title: 'Staff performance',
              subtitle: 'Who sold how much',
              leadingIcon: Icons.emoji_events_rounded,
              onTap: () => context.push('/settings/staff-performance'),
            ),
          // Manager and above, matching the server. It gates the cash-flow
          // report at MANAGER, and this screen shows cash flow beside best
          // sellers — leaving it open let a cashier read on the phone what the
          // website would refuse them.
          if (managerUp)
            MobileListTile(
              title: 'Business pulse',
              subtitle: 'Best sellers and cash flow',
              leadingIcon: Icons.insights_rounded,
              onTap: () => context.push('/settings/pulse'),
            ),
          // MANAGER on the server, because the figures are built from cost
          // prices. The phone computes this from its own database, so without
          // the same gate a cashier saw a report the API answers 403 to.
          if (managerUp)
            MobileListTile(
              title: 'Dead stock',
              subtitle: 'Money sitting in items that are not selling',
              leadingIcon: Icons.inventory_rounded,
              onTap: () => context.push('/settings/dead-stock'),
            ),
          MobileListTile(
            title: 'Data health',
            subtitle: 'Find and fix duplicates and bad counts',
            leadingIcon: Icons.healing_rounded,
            onTap: () => context.push('/settings/data-health'),
          ),
          MobileListTile(
            title: l.settingsBackup,
            subtitle: l.settingsBackupSub,
            leadingIcon: Icons.backup_rounded,
            onTap: () => context.push('/settings/backup'),
          ),
          if (owner)
            MobileListTile(
              title: l.settingsImport,
              subtitle: l.settingsImportSub,
              leadingIcon: Icons.swap_horiz_rounded,
              onTap: () => context.push('/settings/import'),
            ),
          MobileListTile(
            title: 'Staff till PIN',
            subtitle: 'Identifies who is on the till (not the app lock)',
            leadingIcon: Icons.pin_rounded,
            onTap: () => _changePinDialog(context, ref),
          ),
          if (owner)
            MobileListTile(
              title: l.settingsSecurity,
              subtitle: l.settingsSecuritySub,
              leadingIcon: Icons.security_rounded,
              onTap: () => context.push('/settings/security'),
            ),

          // Sync (only surfaces when there is something to do)
          if (pending > 0) ...<Widget>[
            const SizedBox(height: 22),
            MobilePanel(
              title: l.settingsSync,
              action: MobileTag(
                label: '$pending queued',
                icon: Icons.cloud_upload_rounded,
                accent: AppPalette.warning,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '$pending receipt${pending == 1 ? '' : 's'} waiting to sync.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final result =
                          await syncCoordinator.flushCommerceOutbox();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.message ?? 'Retrying queued receipts.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('Retry sync'),
                  ),
                ],
              ),
            ),
          ],

          // Admin tools (owners only)
          if (owner && shop.supportsAdvancedOps) ...<Widget>[
            const SizedBox(height: 22),
            const _SectionLabel('Advanced'),
            MobileListTile(
              title: l.settingsAdminTools,
              subtitle: l.settingsAdminToolsSub,
              leadingIcon: Icons.tune_rounded,
              accent: AppPalette.textTertiary,
              onTap: () => context.push('/settings/admin'),
            ),
          ],

          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(mobileSessionProvider.notifier).logout();
                if (context.mounted) context.go('/');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.error,
                side: const BorderSide(color: AppPalette.error, width: 1),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Business Hub${version == null ? '' : ' · $version'}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _changePinDialog(BuildContext context, WidgetRef ref) async {
  // Asking for a "current PIN" that was never set made this impossible to use.
  final hasPin = await ref
      .read(mobileSessionProvider.notifier)
      .hasStaffPin();
  if (!context.mounted) return;
  final current = TextEditingController();
  final next = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(hasPin ? 'Change till PIN' : 'Set till PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            hasPin
                ? 'This PIN identifies you on the till. It is not the app '
                    'lock — that lives in Settings > Security.'
                : 'You have not set a till PIN yet. Choose one now.',
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (hasPin)
            TextField(
              controller: current,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Current PIN',
                counterText: '',
              ),
            ),
          TextField(
            controller: next,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: 'New PIN',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    if (next.text.trim().length < 4) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New PIN must be 4 digits.')),
        );
      }
    } else {
      final changed = await ref
          .read(mobileSessionProvider.notifier)
          .changePin(current.text.trim(), next.text.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changed
                  ? (hasPin ? 'Till PIN updated.' : 'Till PIN set.')
                  : 'Current PIN is incorrect.',
            ),
          ),
        );
      }
    }
  }
  current.dispose();
  next.dispose();
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppPalette.textTertiary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

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
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: AppPalette.textTertiary),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppPalette.textTertiary,
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
