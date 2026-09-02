import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';

/// Money amounts arrive from DRF as JSON strings.
double parseMoney(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

/// The Jama lines worth showing, largest first, zeroes dropped.
///
/// A day book listing every payment method the software supports, most of them
/// at zero, is a form. The paper one a shopkeeper already keeps lists only what
/// actually came in.
List<MapEntry<String, double>> jamaLines(Map<String, dynamic> jama) {
  const labels = <String, String>{
    'CASH': 'Cash',
    'UPI': 'UPI',
    'CARD': 'Card',
    'BANK': 'Bank',
    'other': 'Other',
    'khata_repayments': 'Khata repaid',
  };
  final rows = <MapEntry<String, double>>[];
  jama.forEach((key, value) {
    // 'total' is the sum of these lines, not another line.
    if (key == 'total') return;
    final amount = parseMoney(value);
    if (amount == 0) return;
    rows.add(MapEntry(labels[key] ?? key, amount));
  });
  rows.sort((a, b) => b.value.compareTo(a.value));
  return rows;
}

final dayBookProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final session = ref.watch(mobileSessionProvider).asData?.value;
  if (session == null || !session.hasShop) return const <String, dynamic>{};
  return ref
      .read(backendApiClientProvider)
      .fetchDayBook(user: session.user, shopId: session.shopId!);
});

/// The day book — Roj Mel — on the phone.
///
/// Shaped like the paper book rather than like a dashboard: what came in on
/// one side, what went out on credit on the other. Keeping those apart is the
/// entire point. A day of strong sales and weak collection looks healthy on a
/// revenue figure and is not, and that is precisely the day a shopkeeper needs
/// to notice.
///
/// Distinct from Day Close, which reconciles the till at the end of a shift.
/// This answers a different question: how much of today's trade was actually
/// paid for.
class DayBookScreen extends ConsumerWidget {
  const DayBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final async = ref.watch(dayBookProvider);
    final payload = async.asData?.value ?? const <String, dynamic>{};

    final jama =
        (payload['jama'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final udhaar =
        (payload['udhaar'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final moneyOut =
        (payload['money_out'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final jamaTotal = parseMoney(jama['total']);
    final creditGiven = parseMoney(udhaar['credit_given']);
    final expenses = parseMoney(moneyOut['expenses']);
    final cashInHand = parseMoney(payload['cash_in_hand']);
    final summaryText = '${payload['summary_text'] ?? ''}';

    return MobileStandaloneScaffold(
      title: 'Day book',
      trailing: summaryText.isEmpty
          ? null
          : IconButton(
              tooltip: 'Copy today’s figures',
              icon: const Icon(Icons.copy_rounded),
              // The server writes this wording so every surface says the same
              // thing; rebuilding it here would let the two drift apart.
              // Clipboard rather than a share sheet: it pastes into WhatsApp,
              // a message to the accountant, or anywhere else, and needs no
              // extra dependency to do it.
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: summaryText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied. Paste it anywhere.')),
                  );
                }
              },
            ),
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dayBookProvider),
        child: async.isLoading && payload.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: CircularProgressIndicator(),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: <Widget>[
                  Text(
                    '${payload['date'] ?? ''} · ${payload['sales_count'] ?? 0} bills',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Panel(
                    title: 'JAMA · MONEY IN',
                    tone: AppPalette.success,
                    total: jamaTotal,
                    caption: 'Actually received today',
                    rows: jamaLines(jama),
                  ),
                  const SizedBox(height: 12),
                  _Panel(
                    title: 'UDHAAR · GIVEN ON CREDIT',
                    tone: AppPalette.warning,
                    total: creditGiven,
                    caption: creditGiven == 0
                        ? 'Nothing went out on credit today'
                        : 'Goods handed over, still owed',
                    rows: const <MapEntry<String, double>>[],
                  ),
                  if (expenses > 0) ...<Widget>[
                    const SizedBox(height: 12),
                    _Panel(
                      title: 'MONEY OUT',
                      tone: AppPalette.error,
                      total: expenses,
                      caption: 'Expenses paid today',
                      rows: const <MapEntry<String, double>>[],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.borderSoft),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Cash that should be in the drawer',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.textSecondary,
                              ),
                            ),
                            Text(
                              'Count it before you close',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          formatCurrency(cashInHand),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: colors.textPrimary,
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

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.tone,
    required this.total,
    required this.caption,
    required this.rows,
  });

  final String title;
  final Color tone;
  final double total;
  final String caption;
  final List<MapEntry<String, double>> rows;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: tone,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatCurrency(total),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: colors.textPrimary,
            ),
          ),
          Text(
            caption,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textTertiary,
            ),
          ),
          if (rows.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      row.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      formatCurrency(row.value),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
