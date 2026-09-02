import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../ui/ui.dart';

final deadStockProvider = StreamProvider.autoDispose
    .family<List<DeadStockItem>, int>(
      (ref, days) =>
          ref.watch(inventoryRepositoryProvider).watchDeadStock(days: days),
    );

/// What money is sitting on the shelf not moving.
///
/// For a clothing or general store this is usually the largest hidden problem:
/// cash converted into stock that nobody is buying, invisible because every
/// other screen shows what IS selling.
class DeadStockScreen extends ConsumerStatefulWidget {
  const DeadStockScreen({super.key});

  @override
  ConsumerState<DeadStockScreen> createState() => _DeadStockScreenState();
}

class _DeadStockScreenState extends ConsumerState<DeadStockScreen> {
  int _days = 90;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final async = ref.watch(deadStockProvider(_days));
    final items = async.asData?.value ?? const <DeadStockItem>[];
    final tiedUp = items.fold<double>(0, (sum, i) => sum + i.tiedUpValue);
    final neverSold = items.where((i) => i.neverSold).length;

    return AppScreen(
      scrollable: false,
      title: L.of(context).deadStockTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppPalette.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppPalette.warning.withValues(alpha: 0.30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'MONEY SITTING ON THE SHELF',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(tiedUp),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppPalette.warning,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${items.length} item(s) unsold for $_days days'
                  '${neverSold > 0 ? '  ·  $neverSold never sold at all' : ''}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 30, label: Text('30 days')),
              ButtonSegment<int>(value: 90, label: Text('90 days')),
              ButtonSegment<int>(value: 180, label: Text('6 months')),
            ],
            selected: <int>{_days},
            onSelectionChanged: (selection) =>
                setState(() => _days = selection.first),
          ),
          const SizedBox(height: 16),
          if (async.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (items.isEmpty)
            AppPanel(
              title: 'Nothing stuck',
              child: AppEmptyState(
                icon: Icons.check_circle_rounded,
                title: 'Everything is moving',
                body: 'No stock has been sitting unsold for $_days days.',
              ),
            )
          else ...<Widget>[
            Text(
              'Worst first, by money tied up. Consider a discount, a bundle, or '
              'returning it to the supplier.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 12),
            for (final item in items.take(100))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DeadStockTile(item: item),
              ),
          ],
        ],
      ),
    );
  }
}

class _DeadStockTile extends StatelessWidget {
  const _DeadStockTile({required this.item});

  final DeadStockItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accent = item.neverSold ? AppPalette.error : AppPalette.warning;
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
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.lastSoldLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${formatQty(item.stock)} in stock',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatCurrency(item.tiedUpValue),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppPalette.warning,
                ),
              ),
              Text(
                item.costPrice == null ? 'at sale price' : 'at cost',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
