import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../customers/presentation/khata_collection_screen.dart';
import '../../../core/receipt/zreport_pdf.dart';
import '../../../core/reports/day_summary.dart';
import '../../../core/util/whatsapp.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

/// End-of-day close: today's takings, per-mode totals, and a cash count with
/// expected-vs-counted variance.
class DayCloseScreen extends ConsumerStatefulWidget {
  const DayCloseScreen({super.key});

  @override
  ConsumerState<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends ConsumerState<DayCloseScreen> {
  final TextEditingController _counted = TextEditingController();
  final TextEditingController _openingFloat = TextEditingController();

  @override
  void dispose() {
    _counted.dispose();
    _openingFloat.dispose();
    super.dispose();
  }

  /// Send today's figures to the owner's own WhatsApp. Uses the shop's saved
  /// phone number so it lands in their chat list; if none is set we fall back
  /// to the share sheet rather than failing.
  Future<void> _sendDaySummary(ZReportSnapshot z) async {
    final shop = ref.read(shopInfoProvider).asData?.value;
    final debtors =
        ref.read(khataDebtorsProvider).asData?.value ?? const <KhataDebtor>[];
    final lowStock =
        ref.read(dashboardLowStockPreviewProvider).asData?.value ??
        const <LowStockItem>[];

    final message = buildDaySummary(
      shopName: shop?.name ?? '',
      date: DateTime.now(),
      z: z,
      lowStockCount: lowStock.length,
      outstandingUdhaar: debtors.fold<double>(0, (sum, d) => sum + d.balance),
    );

    final phone = shop?.phone ?? '';
    final opened = await openWhatsApp(phone: phone, message: message);
    if (opened || !mounted) return;
    // No usable shop number — say so plainly instead of failing silently.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Add your shop mobile number in Business settings to send the '
          'summary to yourself.',
        ),
      ),
    );
  }

  Future<void> _printZReport(ZReportSnapshot z) async {
    final shop = ref.read(shopInfoProvider).asData?.value;
    if (shop == null) return;
    final opening = double.tryParse(_openingFloat.text.trim()) ?? 0;
    final counted = double.tryParse(_counted.text.trim());
    final today = DateTime.now().toIso8601String().split('T').first;
    await Printing.layoutPdf(
      onLayout: (_) => buildZReportPdf(
        z: z,
        shop: shop,
        dateLabel: today,
        openingFloat: opening,
        countedCash: counted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final z =
        ref.watch(zReportProvider(HistoryDateWindow.today)).asData?.value ??
        ZReportSnapshot.empty;

    final opening = double.tryParse(_openingFloat.text.trim()) ?? 0;
    final expectedCash = opening + z.cashCollected;
    final counted = double.tryParse(_counted.text.trim());
    final variance = counted == null ? null : counted - expectedCash;

    final modeEntries = z.tenderBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return MobileStandaloneScaffold(
      title: 'Day close',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          AppPanel(
            title: 'Today',
            action: AppTag(
              label: '${z.salesCount} sales',
              icon: Icons.today_rounded,
              tone: AppTone.primary,
            ),
            child: Column(
              children: <Widget>[
                _kv('Gross sales', formatCurrency(z.grossSales), bold: true),
                const SizedBox(height: 8),
                _kv('Discounts given', formatCurrency(z.discountTotal)),
                const SizedBox(height: 8),
                _kv('Tax collected', formatCurrency(z.taxCollected)),
                const SizedBox(height: 8),
                _kv(
                  'Collected',
                  formatCurrency(z.collected),
                  color: AppPalette.success,
                ),
                const SizedBox(height: 8),
                _kv(
                  'Outstanding due',
                  formatCurrency(z.due),
                  color: z.due > 0 ? AppPalette.warning : AppPalette.success,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Collected by tender',
            action: const AppTag(label: 'TODAY', icon: Icons.payments_rounded),
            child: modeEntries.isEmpty
                ? const AppEmptyState(
                    icon: Icons.query_stats_rounded,
                    title: 'No sales today',
                    body: 'Payment totals will appear here as you sell.',
                  )
                : Column(
                    children: <Widget>[
                      for (final e in modeEntries) ...<Widget>[
                        _kv(e.key, formatCurrency(e.value)),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Cash count',
            action: const AppTag(
              label: 'RECONCILE',
              icon: Icons.account_balance_wallet_rounded,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _openingFloat,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Opening float (cash you started with)',
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 12),
                _kv('+ Cash sales', formatCurrency(z.cashCollected)),
                const SizedBox(height: 8),
                _kv(
                  '= Expected in drawer',
                  formatCurrency(expectedCash),
                  bold: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _counted,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Counted cash in drawer',
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 14),
                if (variance != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          (variance.abs() < 0.01
                                  ? AppPalette.success
                                  : AppPalette.error)
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          variance.abs() < 0.01
                              ? Icons.check_circle_rounded
                              : Icons.error_rounded,
                          color: variance.abs() < 0.01
                              ? AppPalette.success
                              : AppPalette.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            variance.abs() < 0.01
                                ? 'Drawer matches — all good.'
                                : variance > 0
                                ? 'Over by ${formatCurrency(variance)}.'
                                : 'Short by ${formatCurrency(-variance)}.',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // The owner is often not in the shop at closing time, so the day's
          // numbers should reach their phone without them opening the app.
          FilledButton.icon(
            onPressed: () => _sendDaySummary(z),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('Send day summary on WhatsApp'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: z.salesCount == 0 ? null : () => _printZReport(z),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.print_rounded),
            label: const Text('Print / share Z-report'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false, Color? color}) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text(
          k,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          v,
          style:
              (bold ? theme.textTheme.titleMedium : theme.textTheme.bodyLarge)
                  ?.copyWith(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}
