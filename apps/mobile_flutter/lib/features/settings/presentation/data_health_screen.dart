import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/health/data_health.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../ui/ui.dart';

final dataHealthProvider = Provider.autoDispose<DataHealthReport>((ref) {
  // Scan the whole catalog, not a page: a duplicate two screens down is
  // exactly the kind of thing nobody finds by browsing.
  final items =
      ref
          .watch(
            inventoryCatalogPageProvider(
              const InventoryCatalogFilter(page: 1, pageSize: 5000),
            ),
          )
          .asData
          ?.value ??
      const <InventoryCatalogItem>[];
  final customers =
      ref.watch(customersProvider).asData?.value ??
      const <BackendCustomerSummary>[];
  return buildDataHealthReport(items: items, customers: customers);
});

/// Finds and repairs the data problems that quietly corrupt every report built
/// on top of them — duplicate products, impossible stock counts, free items,
/// and debts with no way to chase them.
class DataHealthScreen extends ConsumerStatefulWidget {
  const DataHealthScreen({super.key});

  @override
  ConsumerState<DataHealthScreen> createState() => _DataHealthScreenState();
}

class _DataHealthScreenState extends ConsumerState<DataHealthScreen> {
  bool _busy = false;

  Future<void> _mergeGroup(DuplicateGroup group) async {
    final keeper = group.keeper;
    final combined = group.combinedStock;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Merge ${group.copies} copies'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('"${keeper.name}" appears ${group.copies} times.'),
            const SizedBox(height: 10),
            Text(
              'Keep one item with the combined stock of '
              '${formatQty(combined)}, and archive the other '
              '${group.copies - 1}.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              'Past bills are not affected — they keep the name and price '
              'they were sold at.',
              style: TextStyle(fontSize: 12),
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
            child: Text(L.of(context).healthMerge),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final coordinator = ref.read(mobileSyncCoordinatorProvider);
    try {
      // Move all the stock onto the keeper first. If archiving then fails part
      // way, the shop still has one row holding the real total rather than
      // stock spread across rows that are half-deleted.
      await coordinator.updateInventoryItem(
        itemId: keeper.id,
        name: keeper.name,
        sellPrice: keeper.price,
        stock: combined,
        category: keeper.category,
        sku: keeper.sku ?? '',
        hsnCode: keeper.hsnCode ?? '',
        gstRate: keeper.gstRate,
        priceIncludesTax: keeper.priceIncludesTax,
        costPrice: keeper.costPrice,
        size: keeper.size ?? '',
        subcategory: keeper.subcategory ?? '',
        description: keeper.description ?? '',
        createdAt: keeper.createdAt,
        imagePath: keeper.imagePath,
        unit: keeper.unit,
        reorderLevel: keeper.reorderLevel,
      );
      for (final duplicate in group.duplicates) {
        await coordinator.deleteInventoryItem(
          itemId: duplicate.id,
          name: duplicate.name,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Merged into one item with ${formatQty(combined)} in stock.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Merge failed: $error'),
            backgroundColor: AppPalette.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mergeAll(List<DuplicateGroup> groups) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Merge all ${groups.length} products'),
        content: const Text(
          'Each product will be reduced to a single item holding the combined '
          'stock of its copies. Past bills are not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L.of(context).healthMergeAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final group in groups) {
      if (!mounted) return;
      await _mergeGroupSilently(group);
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Duplicates merged.')));
    }
  }

  Future<void> _mergeGroupSilently(DuplicateGroup group) async {
    final keeper = group.keeper;
    final coordinator = ref.read(mobileSyncCoordinatorProvider);
    try {
      await coordinator.updateInventoryItem(
        itemId: keeper.id,
        name: keeper.name,
        sellPrice: keeper.price,
        stock: group.combinedStock,
        category: keeper.category,
        sku: keeper.sku ?? '',
        hsnCode: keeper.hsnCode ?? '',
        gstRate: keeper.gstRate,
        priceIncludesTax: keeper.priceIncludesTax,
        costPrice: keeper.costPrice,
        size: keeper.size ?? '',
        subcategory: keeper.subcategory ?? '',
        description: keeper.description ?? '',
        createdAt: keeper.createdAt,
        imagePath: keeper.imagePath,
        unit: keeper.unit,
        reorderLevel: keeper.reorderLevel,
      );
      for (final duplicate in group.duplicates) {
        await coordinator.deleteInventoryItem(
          itemId: duplicate.id,
          name: duplicate.name,
        );
      }
    } catch (_) {
      // One bad group shouldn't abandon the rest of the clean-up; the scan
      // re-runs live, so anything that failed simply stays listed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final report = ref.watch(dataHealthProvider);

    return AppScreen(
      scrollable: false,
      title: L.of(context).healthTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          _HeaderCard(report: report),
          const SizedBox(height: 16),
          if (report.isHealthy)
            AppPanel(
              title: L.of(context).healthNothing,
              child: AppEmptyState(
                icon: Icons.verified_rounded,
                title: 'Your data looks healthy',
                body:
                    'No duplicate products, impossible stock counts, free items '
                    'or unreachable debts.',
              ),
            ),
          if (report.duplicateGroups.isNotEmpty) ...<Widget>[
            _SectionHeader(
              title: L.of(context).healthDuplicates,
              count: report.duplicateRowCount,
              explanation:
                  'The same product imported more than once. Copies split one '
                  'product’s stock across rows, so counts and reorder '
                  'suggestions go wrong.',
              action: report.duplicateGroups.length > 1
                  ? TextButton(
                      onPressed: _busy
                          ? null
                          : () => _mergeAll(report.duplicateGroups),
                      child: Text(L.of(context).healthMergeAll),
                    )
                  : null,
            ),
            for (final group in report.duplicateGroups.take(30))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DuplicateTile(
                  group: group,
                  busy: _busy,
                  onMerge: () => _mergeGroup(group),
                ),
              ),
          ],
          if (report.negativeStock.isNotEmpty) ...<Widget>[
            _SectionHeader(
              title: 'Impossible stock counts',
              count: report.negativeStock.length,
              explanation:
                  'Stock below zero means more was sold than the system ever '
                  'had. Open the item and use "Set exact" to enter the real '
                  'count from the shelf.',
            ),
            for (final item in report.negativeStock.take(30))
              _IssueTile(
                title: item.name,
                detail: '${formatQty(item.stock)} in stock',
                accent: AppPalette.error,
                icon: Icons.trending_down_rounded,
              ),
          ],
          if (report.missingPrice.isNotEmpty) ...<Widget>[
            _SectionHeader(
              title: 'Items with no price',
              count: report.missingPrice.length,
              explanation:
                  'These will ring up as free at the till. Set a selling price '
                  'from the Stock screen.',
            ),
            for (final item in report.missingPrice.take(30))
              _IssueTile(
                title: item.name,
                detail: 'No selling price',
                accent: AppPalette.warning,
                icon: Icons.money_off_rounded,
              ),
          ],
          if (report.customersWithoutPhone.isNotEmpty) ...<Widget>[
            _SectionHeader(
              title: 'Debts you cannot chase',
              count: report.customersWithoutPhone.length,
              explanation:
                  'These customers owe money but have no mobile number, so they '
                  'can never be sent a reminder. Add their number from Clients.',
            ),
            for (final customer in report.customersWithoutPhone.take(30))
              _IssueTile(
                title: customer.name,
                detail: '${formatCurrency(customer.balance)} owed, no mobile',
                accent: AppPalette.warning,
                icon: Icons.phone_disabled_rounded,
              ),
          ],
          const SizedBox(height: 16),
          Text(
            'This screen updates as you fix things. Nothing here deletes a '
            'sale or a payment — only duplicate product rows are archived.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.report});

  final DataHealthReport report;

  @override
  Widget build(BuildContext context) {
    final healthy = report.isHealthy;
    final accent = healthy ? AppPalette.success : AppPalette.warning;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            healthy ? Icons.verified_rounded : Icons.healing_rounded,
            color: accent,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  healthy
                      ? 'No problems found'
                      : '${report.totalIssues} thing(s) to fix',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  healthy
                      ? 'Your products and customers look consistent.'
                      : 'Wrong data quietly corrupts every report built on it.',
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.explanation,
    this.action,
  });

  final String title;
  final int count;
  final String explanation;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$title ($count)',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              ?action,
            ],
          ),
          Text(
            explanation,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.of(context).textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateTile extends StatelessWidget {
  const _DuplicateTile({
    required this.group,
    required this.busy,
    required this.onMerge,
  });

  final DuplicateGroup group;
  final bool busy;
  final VoidCallback onMerge;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.keeper.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${group.copies} copies  ·  combined stock '
                  '${formatQty(group.combinedStock)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: busy ? null : onMerge,
            child: Text(L.of(context).healthMerge),
          ),
        ],
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({
    required this.title,
    required this.detail,
    required this.accent,
    required this.icon,
  });

  final String title;
  final String detail;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.borderSoft),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
