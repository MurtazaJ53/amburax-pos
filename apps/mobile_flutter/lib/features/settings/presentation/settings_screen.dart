import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/app_runtime_info.dart';
import '../../../core/runtime/mobile_runtime_config.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/ui.dart';
import 'settings_parts.dart';
import 'shop_switcher_screen.dart';
import 'till_pin_dialog.dart';

/// Settings, grouped the way the website groups them.
///
/// This screen used to be 23 rows under a single heading called "Manage", in
/// no particular order — Language between Expenses and Purchases, Stocktake
/// beside Plan & billing. Two of those 23 checked whether the shop's plan
/// actually included the feature; the rest were shown to everyone and only
/// failed when the server said no.
///
/// The website solved this already (`admin-shell.tsx`): a short Everyday list,
/// the occasional work folded behind "More", and account controls always
/// reachable. Same names and same order here, so the two surfaces stay one
/// product.
///
/// Two gates, kept deliberately separate:
///   * **role** decides *may they* — owner, manager.
///   * **plan** decides *did they pay for it* — `supportsExpenses` and friends,
///     resolved server-side and mirrored here.
///
/// Mixing them is what made the old list unpredictable.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Collapsed by default. A single-branch kirana never opens it.
  bool _moreOpen = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    final pending = ref.watch(pendingOutboxCountProvider).asData?.value ?? 0;
    final version = ref
        .watch(appRuntimeInfoProvider)
        .asData
        ?.value
        .versionLabel;

    final l = L.of(context);
    final owner = session?.isOwnerLike ?? false;
    // Manager and above. Several of these screens are computed on the device
    // from its own database, so the server's role check never runs — the gate
    // has to be repeated here or the two platforms disagree about who may look.
    final managerUp = owner || (session?.isManager ?? false);
    final danger = toneColorsOf(context, AppTone.danger);

    return AppScreen(
      title: l.settingsTitle,
      scrollable: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Gap.lg,
          Gap.md,
          Gap.lg,
          Gap.scrollBottom,
        ),
        children: <Widget>[
          SettingsShopCard(shop: shop, session: session),

          const AppSectionHeader('Everyday'),
          _Group(
            children: <Widget>[
              AppListRow(
                title: 'Day book (Roj Mel)',
                subtitle: 'What came in today, and what went out on credit',
                leadingIcon: Icons.menu_book_rounded,
                onTap: () => context.push('/settings/day-book'),
              ),
              AppListRow(
                title: 'Report',
                subtitle: 'How the shop is doing this week',
                leadingIcon: Icons.trending_up_rounded,
                onTap: () => context.push('/reports'),
              ),
              if (shop.supportsExpenses)
                AppListRow(
                  title: l.settingsExpenses,
                  subtitle: l.settingsExpensesSub,
                  leadingIcon: Icons.payments_rounded,
                  onTap: () => context.push('/settings/expenses'),
                ),
              if (shop.supportsAttendance)
                AppListRow(
                  title: l.settingsAttendance,
                  subtitle: l.settingsAttendanceSub,
                  leadingIcon: Icons.fact_check_rounded,
                  onTap: () => context.push('/settings/attendance'),
                ),
              if (owner)
                AppListRow(
                  title: l.settingsTeam,
                  subtitle: l.settingsTeamSub,
                  leadingIcon: Icons.groups_rounded,
                  onTap: () => context.push('/settings/team'),
                ),
              if (owner)
                AppListRow(
                  title: l.settingsBusiness,
                  subtitle: l.settingsBusinessSub,
                  leadingIcon: Icons.storefront_rounded,
                  onTap: () => context.push('/settings/business'),
                ),
            ],
          ),

          AppSectionHeader(
            'More',
            trailing: TextButton(
              onPressed: () => setState(() => _moreOpen = !_moreOpen),
              child: Text(_moreOpen ? 'Hide' : 'Show'),
            ),
          ),
          if (_moreOpen)
            _Group(children: _moreRows(context, l, shop, owner, managerUp)),

          const AppSectionHeader('Account'),
          _Group(
            children: <Widget>[
              if (owner)
                AppListRow(
                  title: l.settingsPlanBilling,
                  subtitle: l.settingsPlanBillingSub,
                  leadingIcon: Icons.workspace_premium_rounded,
                  onTap: () => context.push('/settings/billing'),
                ),
              if (owner)
                AppListRow(
                  title: l.settingsSecurity,
                  subtitle: l.settingsSecuritySub,
                  leadingIcon: Icons.security_rounded,
                  onTap: () => context.push('/settings/security'),
                ),
              AppListRow(
                title: 'Staff till PIN',
                subtitle: 'Identifies who is on the till (not the app lock)',
                leadingIcon: Icons.pin_rounded,
                showChevron: false,
                onTap: () => showTillPinDialog(context, ref),
              ),
              if (MobileRuntimeConfig.backendAuthMode == 'jwt')
                AppListRow(
                  title: l.settingsSwitchShop,
                  subtitle: l.settingsSwitchShopSub,
                  leadingIcon: Icons.swap_horiz_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ShopSwitcherScreen(),
                    ),
                  ),
                ),
            ],
          ),

          if (pending > 0) ...<Widget>[
            const SizedBox(height: Gap.xl),
            SettingsSyncPanel(pending: pending),
          ],

          const SizedBox(height: Gap.xxl),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(mobileSessionProvider.notifier).logout();
                if (context.mounted) context.go('/');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: danger.foreground,
                side: BorderSide(color: danger.border, width: Strokes.hairline),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
          const SizedBox(height: Gap.md),
          Center(
            child: Text(
              'Business Hub${version == null ? '' : ' · $version'}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  /// Real work, just not daily. Collapsed rather than removed — a wholesaler
  /// lives in Purchase orders, and hiding it outright would break their day.
  List<Widget> _moreRows(
    BuildContext context,
    L l,
    ShopInfo shop,
    bool owner,
    bool managerUp,
  ) {
    return <Widget>[
      AppListRow(
        title: 'Stocktake',
        subtitle: 'Count the shelves and fix what the books say',
        leadingIcon: Icons.fact_check_rounded,
        onTap: () => context.push('/settings/stocktake'),
      ),
      // Plan-gated to match the website, which gates these two on flags the
      // server already resolves. Showing a link the backend then 403s is worse
      // than hiding it: the shopkeeper taps, gets an error, and learns the app
      // is unreliable rather than that the feature costs money.
      if (shop.supportsPurchaseWorkflow)
        AppListRow(
          title: 'Purchase orders',
          subtitle: 'What you ordered, and what actually arrived',
          leadingIcon: Icons.receipt_long_rounded,
          onTap: () => context.push('/settings/purchase-orders'),
        ),
      if (shop.supportsSupplierDirectory)
        AppListRow(
          title: l.settingsPurchases,
          subtitle: l.settingsPurchasesSub,
          leadingIcon: Icons.local_shipping_rounded,
          onTap: () => context.push('/settings/purchases'),
        ),
      // No `multi_branch` flag reaches the phone, so this stays ungated. The
      // website hides it for single-branch shops; matching that needs the flag
      // added to the mobile ShopInfo first.
      AppListRow(
        title: 'Stock transfers',
        subtitle: 'Move stock between your shops',
        leadingIcon: Icons.swap_horiz_rounded,
        onTap: () => context.push('/settings/transfers'),
      ),
      if (owner)
        AppListRow(
          title: 'Staff performance',
          subtitle: 'Who sold how much',
          leadingIcon: Icons.emoji_events_rounded,
          onTap: () => context.push('/settings/staff-performance'),
        ),
      // MANAGER on the server, because these are built from cost prices. The
      // phone computes them from its own database, so without the same gate a
      // cashier saw a report the API answers 403 to.
      if (managerUp)
        AppListRow(
          title: 'Business pulse',
          subtitle: 'Best sellers and cash flow',
          leadingIcon: Icons.insights_rounded,
          onTap: () => context.push('/settings/pulse'),
        ),
      if (managerUp)
        AppListRow(
          title: 'Dead stock',
          subtitle: 'Money sitting in items that are not selling',
          leadingIcon: Icons.inventory_rounded,
          onTap: () => context.push('/settings/dead-stock'),
        ),
      if (owner)
        AppListRow(
          title: l.settingsStaff,
          subtitle: l.settingsStaffSub,
          leadingIcon: Icons.badge_rounded,
          onTap: () => context.push('/settings/staff'),
        ),
      AppListRow(
        title: 'Data health',
        subtitle: 'Find and fix duplicates and bad counts',
        leadingIcon: Icons.healing_rounded,
        onTap: () => context.push('/settings/data-health'),
      ),
      if (owner)
        AppListRow(
          title: l.settingsImport,
          subtitle: l.settingsImportSub,
          leadingIcon: Icons.upload_file_rounded,
          onTap: () => context.push('/settings/import'),
        ),
      AppListRow(
        title: l.settingsBackup,
        subtitle: l.settingsBackupSub,
        leadingIcon: Icons.backup_rounded,
        onTap: () => context.push('/settings/backup'),
      ),
      // The 09:00 low-stock alert and the 21:00 takings summary were being
      // sent to owners who had nowhere in the app to read them.
      AppListRow(
        title: 'Alerts',
        subtitle: 'Low stock in the morning, takings at night',
        leadingIcon: Icons.notifications_active_rounded,
        onTap: () => context.push('/settings/alerts'),
      ),
      AppListRow(
        title: l.settingsLanguage,
        subtitle: l.settingsLanguageSubtitle,
        leadingIcon: Icons.translate_rounded,
        onTap: () => context.push('/settings/language'),
      ),
    ];
  }
}

/// Rows of one group, in a single card so the group reads as a block.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: Gap.xxs),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
