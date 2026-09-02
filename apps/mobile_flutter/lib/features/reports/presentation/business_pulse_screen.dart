import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

final bestSellersProvider = FutureProvider.autoDispose
    .family<List<BestSellerItem>, int>(
      (ref, days) =>
          ref.watch(reportsRepositoryProvider).bestSellers(days: days),
    );

final cashFlowProvider = FutureProvider.autoDispose
    .family<CashFlowSnapshot, int>(
      (ref, days) => ref.watch(reportsRepositoryProvider).cashFlow(days: days),
    );

/// Two questions an owner asks constantly: what is selling, and did the shop
/// actually make money. Dead stock answers the opposite of the first; this is
/// the side that tells you what to buy more of.
class BusinessPulseScreen extends ConsumerStatefulWidget {
  const BusinessPulseScreen({super.key});

  @override
  ConsumerState<BusinessPulseScreen> createState() =>
      _BusinessPulseScreenState();
}

class _BusinessPulseScreenState extends ConsumerState<BusinessPulseScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final sellers =
        ref.watch(bestSellersProvider(_days)).asData?.value ??
        const <BestSellerItem>[];
    final flow =
        ref.watch(cashFlowProvider(_days)).asData?.value ??
        CashFlowSnapshot.empty;

    return MobileStandaloneScaffold(
      title: 'Business pulse',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 7, label: Text('7 days')),
              ButtonSegment<int>(value: 30, label: Text('30 days')),
              ButtonSegment<int>(value: 90, label: Text('90 days')),
            ],
            selected: <int>{_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
          const SizedBox(height: 16),
          _CashFlowCard(flow: flow),
          const SizedBox(height: 20),
          Text(
            'BEST SELLERS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'What to keep in stock. The opposite of the dead stock list.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (sellers.isEmpty)
            const AppPanel(
              title: 'No sales yet',
              child: AppEmptyState(
                icon: Icons.insights_rounded,
                title: 'Nothing sold in this period',
                body: 'Best sellers appear here once you start billing.',
              ),
            )
          else
            for (var i = 0; i < sellers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SellerTile(rank: i + 1, item: sellers[i]),
              ),
        ],
      ),
    );
  }
}

class _CashFlowCard extends StatelessWidget {
  const _CashFlowCard({required this.flow});

  final CashFlowSnapshot flow;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accent = flow.isPositive ? AppPalette.success : AppPalette.error;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'CASH FLOW',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatCurrency(flow.net),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          Text(
            flow.isPositive
                ? 'kept in the business'
                : 'more went out than came in',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          _FlowLine(label: 'Sales', value: flow.salesCollected, positive: true),
          _FlowLine(label: 'Stock purchases', value: -flow.purchases),
          _FlowLine(label: 'Expenses', value: -flow.expenses),
        ],
      ),
    );
  }
}

class _FlowLine extends StatelessWidget {
  const _FlowLine({
    required this.label,
    required this.value,
    this.positive = false,
  });

  final String label;
  final double value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(
            positive
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 14,
            color: positive ? AppPalette.success : AppPalette.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.of(context).textSecondary,
              ),
            ),
          ),
          Text(
            formatCurrency(value.abs()),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SellerTile extends StatelessWidget {
  const _SellerTile({required this.rank, required this.item});

  final int rank;
  final BestSellerItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank <= 3
                  ? AppPalette.success.withValues(alpha: 0.16)
                  : colors.border.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: rank <= 3 ? AppPalette.success : colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
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
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${formatQty(item.quantitySold)} sold  ·  '
                  '${formatCurrency(item.revenue)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          if (item.profit != null)
            Text(
              '+${formatCurrency(item.profit!)}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppPalette.success,
              ),
            ),
        ],
      ),
    );
  }
}
