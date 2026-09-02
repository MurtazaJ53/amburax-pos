import 'package:flutter/material.dart';

import '../../onboarding/presentation/setup_wizard_screen.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/update_check.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/premium_components.dart';

/// Home dashboard — today's takings, key stats, recent sales, low stock.
class DashboardScreenV3 extends ConsumerWidget {
  const DashboardScreenV3({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final shopAsync = ref.watch(shopInfoProvider);
    final overviewAsync = ref.watch(
      dashboardOverviewProvider(session?.canViewCost ?? false),
    );
    final historyAsync = ref.watch(historyOverviewProvider);
    final lowStock =
        ref.watch(dashboardLowStockPreviewProvider).asData?.value ??
        const <LowStockItem>[];
    final recentSales =
        ref.watch(dashboardRecentSalesProvider).asData?.value ??
        const <RecentSaleSummary>[];

    final overview = overviewAsync.asData?.value ?? DashboardOverview.empty();
    final history = historyAsync.asData?.value ?? HistoryOverview.empty();
    // Server-computed all-time totals (correct even when the phone only holds a
    // recent window of sales); fall back to local when offline.
    final serverSummary = ref.watch(salesServerSummaryProvider).asData?.value;
    final serverGross = double.tryParse(
      '${serverSummary?['gross_revenue'] ?? ''}',
    );

    final isLoading = shopAsync.isLoading || overviewAsync.isLoading;
    final hasError = shopAsync.hasError || overviewAsync.hasError;

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : hasError
            ? _buildErrorState(context, ref, session)
            : _buildContent(
                context,
                overview: overview,
                history: history,
                serverGross: serverGross,
                lowStock: lowStock,
                recentSales: recentSales,
                needsSetup:
                    ref.watch(needsOnboardingProvider).asData?.value == true,
              ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    MobileSession? session,
  ) {
    return EmptyStateWidget(
      icon: Icons.error_outline_rounded,
      title: 'Unable to load dashboard',
      message: 'Please check your connection and try again.',
      action: PrimaryActionButton(
        label: 'Retry',
        icon: Icons.refresh_rounded,
        onPressed: () {
          ref.invalidate(
            dashboardOverviewProvider(session?.canViewCost ?? false),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required DashboardOverview overview,
    required HistoryOverview history,
    required double? serverGross,
    required List<LowStockItem> lowStock,
    required List<RecentSaleSummary> recentSales,
    required bool needsSetup,
  }) {
    final metrics = overview.metrics;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: <Widget>[
        const _UpdateBanner(),
        const _GettingStartedCard(),
        // First-run prompt: a new shopkeeper otherwise lands here with an empty
        // app and no idea what to do first. Disappears once setup is done.
        if (needsSetup) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: AppPalette.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/setup'),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppPalette.primary.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.rocket_launch_rounded,
                        color: AppPalette.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Finish setting up your shop',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Shop name, UPI ID and your first product',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],

        // Today's takings hero
        HeroMetricCard(
          label: L.of(context).dashTodaySales,
          value: formatCurrency(overview.todayRevenue),
          caption:
              '${overview.todaySalesCount} ${overview.todaySalesCount == 1 ? 'sale' : 'sales'} today',
          trend: history.queuedSales > 0
              ? '${history.queuedSales} queued'
              : null,
        ),
        const SizedBox(height: 16),

        // Key stats
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                label: 'Items',
                value: '${metrics.totalItems}',
                caption: '${formatQty(metrics.totalStock)} in stock',
                icon: Icons.inventory_2_rounded,
                accent: AppPalette.primary,
                onTap: () => context.go('/inventory'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: L.of(context).dashLowStock,
                value: '${metrics.lowStock}',
                caption: metrics.lowStock > 0 ? 'Needs restock' : 'All good',
                icon: Icons.warning_amber_rounded,
                accent: metrics.lowStock > 0
                    ? AppPalette.error
                    : AppPalette.success,
                onTap: () => context.go('/inventory'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _StatCard(
                label: 'Total sales',
                value: formatCurrencyCompact(
                  serverGross ?? history.totalRevenue,
                ),
                caption: 'View reports',
                icon: Icons.insights_rounded,
                accent: AppPalette.info,
                onTap: () => context.push('/reports'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Stock value',
                value: formatCurrencyCompact(metrics.inventoryValue),
                caption: 'At selling price',
                icon: Icons.account_balance_wallet_rounded,
                accent: AppPalette.success,
                onTap: () => context.go('/inventory'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Start a sale
        PrimaryActionButton(
          label: 'Start New Sale',
          icon: Icons.point_of_sale_rounded,
          onPressed: () => context.go('/pos'),
        ),
        const SizedBox(height: 24),

        // Recent sales
        _SectionRow(
          title: L.of(context).dashRecentSales,
          actionLabel: recentSales.isEmpty ? null : L.of(context).dashViewAll,
          onAction: () => context.go('/history'),
        ),
        const SizedBox(height: 12),
        if (recentSales.isEmpty)
          _EmptyHint(
            icon: Icons.receipt_long_outlined,
            text: 'No sales yet. Tap Start New Sale to begin.',
          )
        else
          ...recentSales.take(5).map((sale) => _RecentSaleTile(sale: sale)),

        // Low stock
        if (lowStock.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          _SectionRow(
            title: L.of(context).dashLowStock,
            actionLabel: L.of(context).dashManage,
            onAction: () => context.go('/inventory'),
          ),
          const SizedBox(height: 12),
          ...lowStock
              .take(4)
              .map(
                (item) => _LowStockTile(
                  item: item,
                  onTap: () => context.go('/inventory'),
                ),
              ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(height: 14),
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const Spacer(),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _RecentSaleTile extends StatelessWidget {
  const _RecentSaleTile({required this.sale});

  final RecentSaleSummary sale;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final title = (sale.customerName == null || sale.customerName!.isEmpty)
        ? L.of(context).dashWalkInSale
        : sale.customerName!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_rounded,
              color: AppPalette.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${sale.paymentMode} · ${sale.date}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatCurrency(sale.total),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (sale.hasOutstandingDue)
                Text(
                  'Due ${formatCurrency(sale.amountDue)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LowStockTile extends StatelessWidget {
  const _LowStockTile({required this.item, required this.onTap});

  final LowStockItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.borderSoft),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppPalette.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppPalette.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(
                  label: L.of(context).dashLeft(formatQty(item.stock)),
                  color: AppPalette.error,
                  showDot: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: colors.textTertiary, size: 32),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _GettingStartedCard extends ConsumerStatefulWidget {
  const _GettingStartedCard();

  @override
  ConsumerState<_GettingStartedCard> createState() =>
      _GettingStartedCardState();
}

class _GettingStartedCardState extends ConsumerState<_GettingStartedCard> {
  bool _visible = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final done = await ref
        .read(shopRepositoryProvider)
        .readSetting('onboarding_done');
    if (mounted) {
      setState(() {
        _visible = done != 'true';
        _loaded = true;
      });
    }
  }

  Future<void> _dismiss() async {
    await ref
        .read(shopRepositoryProvider)
        .writeSetting('onboarding_done', 'true');
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !_visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppPalette.primary, AppPalette.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.rocket_launch_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'Getting started',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _dismiss,
                child: const Text(
                  'Dismiss',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _step(
            '1',
            'Set your business details',
            'Name, phone, receipt footer',
            () => context.push('/settings/business'),
          ),
          const SizedBox(height: 8),
          _step(
            '2',
            'Add your first product',
            'Build your inventory',
            () => context.go('/inventory'),
          ),
          const SizedBox(height: 8),
          _step(
            '3',
            'Make your first sale',
            'Open the POS',
            () => context.go('/pos'),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String title, String subtitle, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 13,
                backgroundColor: Colors.white,
                child: Text(
                  n,
                  style: const TextStyle(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateStatusProvider);
    if (!status.updateAvailable) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.system_update_rounded, color: AppPalette.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Update available',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Version ${status.latestVersion} is ready. Please update for the latest fixes.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
