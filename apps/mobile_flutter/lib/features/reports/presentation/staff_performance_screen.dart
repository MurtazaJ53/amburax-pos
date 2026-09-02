import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

/// Parse the money fields, which DRF serialises as JSON strings.
double _money(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

int _count(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

final staffPerformanceProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, days) async {
      final session = ref.watch(mobileSessionProvider).asData?.value;
      if (session == null || !session.hasShop) {
        return const <Map<String, dynamic>>[];
      }
      final from = DateTime.now().subtract(Duration(days: days));
      return ref
          .read(backendApiClientProvider)
          .fetchStaffPerformance(
            user: session.user,
            shopId: session.shopId!,
            dateFrom: from.toIso8601String().split('T').first,
          );
    });

/// Who is selling, and how. Useful for targets and for spotting a till that
/// gives away far more discount than anyone else.
class StaffPerformanceScreen extends ConsumerStatefulWidget {
  const StaffPerformanceScreen({super.key});

  @override
  ConsumerState<StaffPerformanceScreen> createState() =>
      _StaffPerformanceScreenState();
}

class _StaffPerformanceScreenState
    extends ConsumerState<StaffPerformanceScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final async = ref.watch(staffPerformanceProvider(_days));
    final rows = async.asData?.value ?? const <Map<String, dynamic>>[];
    final total = rows.fold<double>(0, (sum, r) => sum + _money(r['gross']));

    return MobileStandaloneScaffold(
      title: L.of(context).staffPerformance,
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
          if (async.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (rows.isEmpty)
            const AppPanel(
              title: 'No sales in this period',
              child: AppEmptyState(
                icon: Icons.people_outline_rounded,
                title: 'Nothing to compare yet',
                body:
                    'Sales are credited to whoever was signed in when they '
                    'were billed.',
              ),
            )
          else ...<Widget>[
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StaffTile(
                  rank: i + 1,
                  row: rows[i],
                  shareOfTotal: total <= 0
                      ? 0
                      : _money(rows[i]['gross']) / total,
                ),
              ),
            const SizedBox(height: 10),
            if (rows.length == 1)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  // Be honest rather than let an owner read one row as proof
                  // that one person did everything.
                  'Everything is credited to one account. Give each team member '
                  'their own login from Settings > Team to compare them.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.rank,
    required this.row,
    required this.shareOfTotal,
  });

  final int rank;
  final Map<String, dynamic> row;
  final double shareOfTotal;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final gross = _money(row['gross']);
    final discount = _money(row['discount_given']);
    final count = _count(row['sale_count']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank == 1
                      ? AppPalette.success.withValues(alpha: 0.16)
                      : colors.border.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: rank == 1
                        ? AppPalette.success
                        : colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (row['name'] ?? 'Unattributed').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                formatCurrency(gross),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppPalette.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: shareOfTotal.clamp(0, 1),
              minHeight: 5,
              backgroundColor: colors.border.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$count bill(s)  ·  avg ${formatCurrency(_money(row['average_ticket']))}'
            '${discount > 0.009 ? '  ·  ${formatCurrency(discount)} discount given' : ''}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
