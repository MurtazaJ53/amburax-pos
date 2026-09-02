import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import 'dead_letter_banner.dart';
import 'sale_return_sheet.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/database/mobile_repository.dart';
import '../../../core/insights/mobile_operational_insights.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/printer/receipt_printer.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/providers/printer_provider.dart';
import '../../../core/receipt/receipt_pdf.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/tax/gst.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';

/// Server-computed sales totals across ALL sales (accurate even when the phone
/// only pulls a recent window of receipts). Falls back to null on error so the
/// screen uses local figures.
final historyServerSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(mobileSessionProvider).asData?.value;
  if (session == null || !session.hasShop) return null;
  try {
    return await ref
        .read(backendApiClientProvider)
        .fetchSalesSummary(user: session.user, shopId: session.shopId!);
  } catch (_) {
    return null;
  }
});

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  HistoryFilter _filter = const HistoryFilter();
  Timer? _histSearchDebounce;
  // Filters are collapsed by default so History opens straight to the receipts.
  bool _showFilters = false;

  int _activeFilterCount() {
    var n = 0;
    if (_filter.search.trim().isNotEmpty) n++;
    if (_filter.syncState != null) n++;
    if (_filter.paymentMode != null) n++;
    if (_filter.dateWindow != HistoryDateWindow.all) n++;
    if (_filter.onlyDueSales) n++;
    return n;
  }

  @override
  void dispose() {
    _histSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _filter = const HistoryFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final salesRepository = ref.read(salesRepositoryProvider);
    final syncCoordinator = ref.watch(mobileSyncCoordinatorProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    final overview =
        ref.watch(historyOverviewProvider).asData?.value ??
        HistoryOverview.empty();
    // Prefer server-computed totals so revenue is correct across ALL sales,
    // not just the recent window pulled to the phone.
    final serverSummary = ref.watch(historyServerSummaryProvider).asData?.value;
    final grossValue =
        double.tryParse('${serverSummary?['gross_revenue'] ?? ''}') ??
        overview.totalRevenue;
    final grossCount =
        (serverSummary?['total_sales'] as num?)?.toInt() ?? overview.totalSales;
    final sales =
        ref.watch(historySalesProvider(_filter)).asData?.value ??
        const <RecentSaleSummary>[];
    final report = HistoryReportSnapshot.fromSales(sales);
    final showOperationalSummary = shop.normalizedPlanTier != 'starter';
    final showAdvancedReport = shop.supportsAdvancedReports;
    final hasActiveFilters =
        _filter.search.trim().isNotEmpty ||
        _filter.syncState != null ||
        _filter.paymentMode != null ||
        _filter.dateWindow != HistoryDateWindow.all ||
        _filter.onlyDueSales;
    final roleProfile = _HistoryRoleProfile.fromSession(
      session: session,
      overview: overview,
      syncStatus: syncStatus,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
      children: <Widget>[
        const DeadLetterBanner(),
        MobileScreenLead(
          title: roleProfile.leadTitle,
          subtitle: roleProfile.leadSubtitle,
          icon: roleProfile.leadIcon,
          accent: roleProfile.leadAccent,
          primaryTag: MobileTag(
            label: roleProfile.primaryTagLabel,
            icon: roleProfile.primaryTagIcon,
            accent: roleProfile.primaryTagAccent,
          ),
          secondaryTag: MobileTag(
            label: roleProfile.secondaryTagLabel,
            icon: roleProfile.secondaryTagIcon,
            accent: roleProfile.secondaryTagAccent,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final count = constraints.maxWidth > 520 ? 4 : 2;
            return GridView.count(
              crossAxisCount: count,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              // Phones use the dense inline-icon card, so the tile can be much
              // shorter; wider screens keep the taller stacked layout.
              childAspectRatio: constraints.maxWidth < 420 ? 1.45 : 1.02,
              children: <Widget>[
                MobileMetricCard(
                  label: 'Gross',
                  value: formatCurrency(grossValue),
                  caption: '$grossCount receipts',
                  icon: Icons.currency_rupee_rounded,
                ),
                MobileMetricCard(
                  label: 'Synced',
                  value: '${overview.syncedSales}',
                  caption: 'Accepted by backend',
                  icon: Icons.verified_rounded,
                  accent: AppPalette.success,
                ),
                MobileMetricCard(
                  label: 'Queued',
                  value: '${overview.queuedSales}',
                  caption: overview.queuedSales > 0
                      ? formatCurrency(overview.queuedRevenue)
                      : 'Outbox clear',
                  icon: Icons.cloud_upload_rounded,
                  accent: AppPalette.warning,
                ),
                // Only a server *rejection* needs the owner. A transient push
                // failure retries itself on the next flush, so showing it in
                // alarm-red as "needs review" sent people hunting for nothing.
                if (overview.rejectedSales > 0)
                  MobileMetricCard(
                    label: 'Attention',
                    value: '${overview.rejectedSales}',
                    caption: 'Rejected — tap banner',
                    icon: Icons.error_outline_rounded,
                    accent: AppPalette.error,
                  )
                else
                  MobileMetricCard(
                    label: 'Retrying',
                    value: '${overview.failedSales}',
                    caption: overview.failedSales > 0
                        ? 'Auto-retries when online'
                        : 'All receipts healthy',
                    icon: overview.failedSales > 0
                        ? Icons.sync_problem_rounded
                        : Icons.verified_rounded,
                    accent: overview.failedSales > 0
                        ? AppPalette.warning
                        : AppPalette.success,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _FilterToggleBar(
          title: roleProfile.filterPanelTitle,
          activeCount: _activeFilterCount(),
          expanded: _showFilters,
          onToggle: () => setState(() => _showFilters = !_showFilters),
          onClear: hasActiveFilters ? _resetFilters : null,
        ),
        if (_showFilters) const SizedBox(height: 12),
        if (_showFilters)
        MobilePanel(
          title: roleProfile.filterPanelTitle,
          action: MobileTag(
            label: _filter.syncState == null
                ? 'ALL STATES'
                : _syncLabel(_filter.syncState!),
            icon: Icons.tune_rounded,
            accent: AppPalette.info,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
      textCapitalization: TextCapitalization.sentences,
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _filter = _filter.copyWith(search: value);
                  });
                  // Pull matching receipts from the server (beyond the local
                  // window) and cache them; the local list stream updates.
                  _histSearchDebounce?.cancel();
                  _histSearchDebounce =
                      Timer(const Duration(milliseconds: 350), () {
                    ref
                        .read(mobileSyncCoordinatorProvider)
                        .searchSalesFromServer(value);
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search customer, phone, or local receipt id',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _filter.search.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _filter = _filter.copyWith(search: '');
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _SyncFilterChip(
                    label: 'All',
                    active: _filter.syncState == null,
                    onTap: () {
                      setState(() {
                        _filter = _filter.copyWith(clearSyncState: true);
                      });
                    },
                  ),
                  ...CommerceSyncState.values.map(
                    (state) => _SyncFilterChip(
                      label: _syncLabel(state),
                      active: _filter.syncState == state,
                      onTap: () {
                        setState(() {
                          _filter = _filter.copyWith(syncState: state);
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _SyncFilterChip(
                    label: 'Any pay',
                    active: _filter.paymentMode == null,
                    onTap: () {
                      setState(() {
                        _filter = _filter.copyWith(clearPaymentMode: true);
                      });
                    },
                  ),
                  ..._historyPaymentModes.map(
                    (mode) => _SyncFilterChip(
                      label: mode,
                      active: _filter.paymentMode == mode,
                      onTap: () {
                        setState(() {
                          _filter = _filter.copyWith(paymentMode: mode);
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: HistoryDateWindow.values
                    .map(
                      (window) => _SyncFilterChip(
                        label: window.label,
                        active: _filter.dateWindow == window,
                        onTap: () {
                          setState(() {
                            _filter = _filter.copyWith(dateWindow: window);
                          });
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _SyncFilterChip(
                    label: _filter.onlyDueSales ? 'Due only' : 'All balances',
                    active: _filter.onlyDueSales,
                    onTap: () {
                      setState(() {
                        _filter = _filter.copyWith(
                          onlyDueSales: !_filter.onlyDueSales,
                        );
                      });
                    },
                  ),
                ],
              ),
              if (hasActiveFilters) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (_filter.search.trim().isNotEmpty)
                      MobileTag(
                        label: 'Search: ${_filter.search.trim()}',
                        icon: Icons.search_rounded,
                        accent: AppPalette.primary,
                      ),
                    if (_filter.syncState != null)
                      MobileTag(
                        label: _syncLabel(_filter.syncState!),
                        icon: Icons.sync_alt_rounded,
                        accent: AppPalette.info,
                      ),
                    if (_filter.paymentMode != null)
                      MobileTag(
                        label: _filter.paymentMode!,
                        icon: Icons.payments_rounded,
                        accent: AppPalette.success,
                      ),
                    if (_filter.dateWindow != HistoryDateWindow.all)
                      MobileTag(
                        label: _filter.dateWindow.label,
                        icon: Icons.date_range_rounded,
                        accent: AppPalette.warning,
                      ),
                    if (_filter.onlyDueSales)
                      const MobileTag(
                        label: 'Due only',
                        icon: Icons.account_balance_wallet_rounded,
                        accent: AppPalette.error,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _resetFilters,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Clear filters'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: overview.queuedSales > 0 || overview.failedSales > 0
                    ? () async {
                        final result = await syncCoordinator
                            .flushCommerceOutbox(force: true);
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.message ??
                                  'Queued receipts are being retried.',
                            ),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: const Text('Retry receipt sync'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        MobilePanel(
          title: roleProfile.summaryPanelTitle,
          action: MobileTag(
            label: _filter.dateWindow.label,
            icon: Icons.insights_rounded,
            accent: AppPalette.success,
          ),
          child: sales.isEmpty
              ? const MobileEmptyState(
                  icon: Icons.query_stats_rounded,
                  title: 'No data for this filter',
                  body:
                      'Broaden the search, date window, or payment filters to generate a live report pulse.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _HistoryMetricTile(
                          label: 'Receipts',
                          value: '${report.receiptCount}',
                          tone: AppPalette.warning,
                        ),
                        _HistoryMetricTile(
                          label: 'Gross',
                          value: formatCurrency(report.grossTotal),
                          tone: AppPalette.success,
                        ),
                        if (showOperationalSummary)
                          _HistoryMetricTile(
                            label: 'Collected',
                            value: formatCurrency(report.collectedTotal),
                            tone: AppPalette.primary,
                          ),
                        if (showOperationalSummary)
                          _HistoryMetricTile(
                            label: 'Due',
                            value: formatCurrency(report.dueTotal),
                            tone: report.dueTotal > 0
                                ? AppPalette.warning
                                : AppPalette.success,
                          ),
                        if (showAdvancedReport)
                          _HistoryMetricTile(
                            label: 'Avg ticket',
                            value: formatCurrency(report.averageTicketValue),
                            tone: AppPalette.info,
                          ),
                        if (showAdvancedReport)
                          _HistoryMetricTile(
                            label: 'Named buyers',
                            value: '${report.namedBuyerCount}',
                            tone: AppPalette.success,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${report.syncedCount} synced | ${report.queuedCount} queued | ${report.failedCount} failed',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      showAdvancedReport
                          ? (report.topPaymentMode == null
                                ? 'No payment mode mix available yet.'
                                : 'Top mode ${report.topPaymentMode} | ${report.dueReceiptCount} receipt(s) still carry due balance | ${report.walkInCount} walk-in sale(s).')
                          : showOperationalSummary
                          ? '${shop.planLabel} keeps reporting lighter here. Upgrade to Pro for payment-mix and buyer-pattern insights.'
                          : '${shop.planLabel} focuses on simple receipt review. Upgrade to unlock deeper report rollups.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black.withValues(alpha: 0.54),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (showAdvancedReport &&
                        report.paymentMix.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      Text(
                        'Payment mix',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...report.paymentMix.map(
                        (mix) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _HistoryPaymentMixRow(mix: mix),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 18),
        MobilePanel(
          title: roleProfile.feedPanelTitle,
          action: MobileTag(
            label: overview.lastSyncedAt == null
                ? 'Freshness unknown'
                : 'Last sync ${formatCompactDate(overview.lastSyncedAt!)}',
            icon: Icons.schedule_rounded,
            accent: AppPalette.info,
          ),
          child: sales.isEmpty
              ? MobileEmptyState(
                  icon: syncStatus == MobileSyncStatus.syncing
                      ? Icons.sync_rounded
                      : Icons.history_toggle_off_rounded,
                  title: syncStatus == MobileSyncStatus.syncing
                      ? 'Receipt feed is still landing'
                      : 'No receipt history yet',
                  body: syncStatus == MobileSyncStatus.syncing
                      ? 'Give the mobile vault a moment while it hydrates the recent commerce trail.'
                      : 'As soon as sales hit the local vault or backend replay, they will appear here.',
                )
              : Column(
                  children: sales
                      .map(
                        (sale) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _HistorySaleRow(
                            sale: sale,
                            onTap: () =>
                                _openSaleDetail(context, salesRepository, sale),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Future<void> _openSaleDetail(
    BuildContext context,
    SalesRepository salesRepository,
    RecentSaleSummary sale,
  ) async {
    final colors = AppColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: FutureBuilder<SaleRecordDetail?>(
              future: salesRepository.getSaleDetail(sale.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const MobileEmptyState(
                    icon: Icons.sync_rounded,
                    title: 'Loading receipt detail',
                    body:
                        'The mobile vault is unpacking the full receipt payload for this sale.',
                  );
                }

                final detail = snapshot.data;
                if (detail == null) {
                  return const MobileEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Receipt detail unavailable',
                    body:
                        'This receipt summary exists, but the full local payload could not be loaded.',
                  );
                }

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 680),
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      MobileSheetHeader(
                        title: formatCurrency(detail.total),
                        subtitle:
                            '${detail.customerName?.isNotEmpty == true ? detail.customerName : 'Walk-in customer'} | ${detail.date}',
                        icon: Icons.receipt_long_rounded,
                        accent: AppPalette.warning,
                        tags: <Widget>[
                          MobileTag(
                            label: _syncLabel(detail.syncState),
                            icon: Icons.cloud_done_rounded,
                            accent: _syncTone(context, detail.syncState),
                          ),
                          MobileTag(
                            label: detail.paymentMode,
                            icon: Icons.payments_rounded,
                            accent: AppPalette.primary,
                          ),
                          MobileTag(
                            label: '${detail.itemCount} items',
                            icon: Icons.shopping_bag_rounded,
                            accent: AppPalette.info,
                          ),
                          if (detail.footerNote != null && detail.footerNote!.contains('Buyer GSTIN:'))
                            const MobileTag(
                              label: 'Tax Invoice',
                              icon: Icons.account_balance_rounded,
                              accent: AppPalette.success,
                            ),
                          if (detail.hasOutstandingDue)
                            MobileTag(
                              label: 'Due ${formatCurrency(detail.amountDue)}',
                              icon: Icons.warning_amber_rounded,
                              accent: AppPalette.warning,
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _SaleDetailSection(
                        title: 'Items',
                        child: Column(
                          children: detail.items
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SaleItemRow(item: item),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SaleDetailSection(
                        title: 'Payments',
                        child: Column(
                          children: detail.payments
                              .map(
                                (payment) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _SalePaymentRow(payment: payment),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SaleDetailSection(
                        title: 'Summary',
                        child: Column(
                          children: <Widget>[
                            _SaleSummaryRow(
                              label: 'Subtotal',
                              value: formatCurrency(detail.subtotal),
                            ),
                            _SaleSummaryRow(
                              label: 'Discount',
                              value: formatCurrency(detail.discount),
                            ),
                            _SaleSummaryRow(
                              label: 'Total',
                              value: formatCurrency(detail.total),
                              emphasize: true,
                            ),
                            Builder(
                              builder: (context) {
                                // Compute GST locally from items
                                var taxableAmount = 0.0;
                                var taxAmount = 0.0;
                                var cgstAmount = 0.0;
                                var sgstAmount = 0.0;
                                var igstAmount = 0.0;

                                // Only apportion discount for local calc if items exist
                                final discountToApportion = detail.discount;
                                final lineTotals = detail.items.map((i) => i.lineTotal).toList();
                                final apportionedDiscounts = apportionDiscount(lineTotals, discountToApportion);

                                for (var i = 0; i < detail.items.length; i++) {
                                  final item = detail.items[i];
                                  final postDiscountTotal = item.lineTotal - apportionedDiscounts[i];
                                  final effectiveTotal = postDiscountTotal < 0 ? 0.0 : postDiscountTotal;

                                  final lineGst = computeLineGst(
                                    lineTotal: effectiveTotal,
                                    gstRate: item.gstRate,
                                    priceIncludesTax: item.priceIncludesTax,
                                    intraState: true,
                                  );

                                  // If backend synced fields are available (non-zero), use them, else fallback to local calc
                                  if (item.taxAmount > 0.009) {
                                    taxableAmount += item.taxableAmount;
                                    taxAmount += item.taxAmount;
                                    cgstAmount += item.cgstAmount;
                                    sgstAmount += item.sgstAmount;
                                    igstAmount += item.igstAmount;
                                  } else {
                                    taxableAmount += lineGst.taxableAmount;
                                    taxAmount += lineGst.taxAmount;
                                    cgstAmount += lineGst.cgstAmount;
                                    sgstAmount += lineGst.sgstAmount;
                                    igstAmount += lineGst.igstAmount;
                                  }
                                }

                                if (taxAmount > 0.009) {
                                  return Column(
                                    children: [
                                      const SizedBox(height: 10),
                                      _SaleSummaryRow(
                                        label: 'Taxable value',
                                        value: formatCurrency(taxableAmount),
                                      ),
                                      _SaleSummaryRow(
                                        label: 'GST total',
                                        value: formatCurrency(taxAmount),
                                      ),
                                      _SaleSummaryRow(
                                        label: 'CGST / SGST',
                                        value: '${formatCurrency(cgstAmount)} / ${formatCurrency(sgstAmount)}',
                                      ),
                                      if (igstAmount > 0.009)
                                        _SaleSummaryRow(
                                          label: 'IGST',
                                          value: formatCurrency(igstAmount),
                                        ),
                                      const SizedBox(height: 10),
                                    ],
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            _SaleSummaryRow(
                              label: 'Collected',
                              value: formatCurrency(detail.amountReceived),
                            ),
                            _SaleSummaryRow(
                              label: 'Due outstanding',
                              value: formatCurrency(detail.amountDue),
                              emphasize: detail.hasOutstandingDue,
                            ),
                            if ((detail.customerPhone ?? '').isNotEmpty)
                              _SaleSummaryRow(
                                label: 'Phone',
                                value: detail.customerPhone!,
                              ),
                            if ((detail.footerNote ?? '').isNotEmpty)
                              _SaleSummaryRow(
                                label: 'Footer note',
                                value: detail.footerNote!,
                              ),
                            if ((detail.commandId ?? '').isNotEmpty)
                              _SaleSummaryRow(
                                label: 'Command',
                                value: detail.commandId!,
                              ),
                            if ((detail.lastSyncError ?? '').isNotEmpty)
                              _SaleSummaryRow(
                                label: 'Last sync error',
                                value: detail.lastSyncError!,
                                emphasize: true,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Android only — iOS cannot drive a Bluetooth Classic
                      // thermal printer, so the button is hidden there rather
                      // than shown and then failing.
                      if (ReceiptPrinterService.supportsBluetoothPrinting)
                      Consumer(
                        builder: (context, ref, child) {
                          return ElevatedButton.icon(
                            onPressed: () async {
                              final printerService = ref.read(receiptPrinterProvider);
                              final shop = ref.read(shopInfoProvider).asData?.value;
                              if (shop == null) return;
                              
                              try {
                                final devices = await printerService.getDevices();
                                if (devices.isEmpty) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('No Bluetooth printers found.')),
                                    );
                                  }
                                  return;
                                }
                                
                                // Connect to first device for now
                                await printerService.connect(devices.first);
                                await printerService.printTaxInvoice(detail, shop);
                                await printerService.disconnect();
                                
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Receipt printed successfully.')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed to print: $e')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.print_rounded),
                            label: Text(
                              detail.footerNote != null && detail.footerNote!.contains('Buyer GSTIN:') 
                                ? 'PRINT TAX INVOICE' 
                                : 'PRINT RECEIPT'
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppPalette.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _shareReceiptPdf(detail),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('SHARE PDF / WHATSAPP'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      // A partial return is a counter action the server lets
                      // staff perform; voiding the whole bill is not. So the
                      // button appears for anyone when the bill has synced,
                      // and only for a manager when the local void is the one
                      // path available.
                      if (detail.total >= 0 &&
                          detail.syncState != CommerceSyncState.refunded &&
                          !(detail.footerNote ?? '').contains('RETURN') &&
                          (_hasBackendId(detail) || _canRefund())) ...<Widget>[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _startReturn(context, detail, salesRepository),
                          icon: const Icon(Icons.assignment_return_rounded),
                          label: const Text('RETURN / REFUND'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.error,
                            side: const BorderSide(color: AppPalette.error),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  bool _canRefund() {
    final s = ref.read(mobileSessionProvider).asData?.value;
    return s != null && (s.isOwnerLike || s.isManager);
  }

  Future<void> _shareReceiptPdf(SaleRecordDetail detail) async {
    try {
      final shop = ref.read(shopInfoProvider).asData?.value;
      if (shop == null) return;
      final bytes = await buildReceiptPdf(detail, shop);
      await Printing.sharePdf(bytes: bytes, filename: 'receipt-${detail.id}.pdf');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $error')),
        );
      }
    }
  }

  /// Whether the server knows about this bill, and so whether a partial return
  /// is possible at all. A sale that has not synced exists only on this phone.
  bool _hasBackendId(SaleRecordDetail detail) =>
      (detail.backendSaleId ?? '').trim().isNotEmpty;

  /// Take goods back against a bill.
  ///
  /// The good path is a partial return on the server: one shirt out of four,
  /// or a swap for a different size, with the rest of the bill left intact.
  /// That needs the sale to exist server-side, because the quantity still
  /// returnable depends on returns this device may never have seen.
  ///
  /// When the bill has not synced there is nothing to return against, so the
  /// only honest option is the old all-or-nothing local void — offered with
  /// the reason stated rather than silently doing something different from
  /// what the same button does on every other bill.
  Future<void> _startReturn(
    BuildContext sheetContext,
    SaleRecordDetail detail,
    SalesRepository salesRepository,
  ) async {
    if (_hasBackendId(detail)) {
      final done = await showModalBottomSheet<bool>(
        context: sheetContext,
        isScrollControlled: true,
        backgroundColor: AppColors.of(sheetContext).surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => SaleReturnSheet(
          backendSaleId: detail.backendSaleId!.trim(),
          // A local placeholder; the sheet shows the server's receipt number
          // once the bill loads.
          receiptNumber: detail.id,
        ),
      );
      if (done == true) {
        // Server totals move; the local sale record correctly does not, since
        // the sale really did happen as recorded.
        ref.invalidate(historyServerSummaryProvider);
        if (sheetContext.mounted) Navigator.pop(sheetContext);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Return recorded.')),
          );
        }
      }
      return;
    }

    if (!_canRefund()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This bill has not reached the server yet. A manager can void it, '
            'or wait for it to sync to return part of it.',
          ),
        ),
      );
      return;
    }

    await _voidWholeSale(sheetContext, detail, salesRepository);
  }

  Future<void> _voidWholeSale(
    BuildContext sheetContext,
    SaleRecordDetail detail,
    SalesRepository salesRepository,
  ) async {
    var restock = true;
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(L.of(context).histRefund),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Refund ${formatCurrency(detail.total)} for this receipt.'),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: restock,
                onChanged: (v) => setDialogState(() => restock = v),
                title: const Text('Put items back in stock'),
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
              style: FilledButton.styleFrom(backgroundColor: AppPalette.error),
              child: const Text('Refund'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final session = ref.read(mobileSessionProvider).asData?.value;
    final shopId = session?.shopId;
    if (session == null || shopId == null || shopId.isEmpty) return;
    try {
      // Local only. _startReturn sends every synced bill to the partial-return
      // sheet, so by the time execution reaches here the server has no record
      // of this sale to void.
      await salesRepository.recordReturn(
        shopId: shopId,
        original: detail,
        restock: restock,
      );
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refunded ${formatCurrency(detail.total)}.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refund failed: $error')),
        );
      }
    }
  }
}

class _HistoryRoleProfile {
  const _HistoryRoleProfile({
    required this.leadTitle,
    required this.leadSubtitle,
    required this.leadIcon,
    required this.leadAccent,
    required this.primaryTagLabel,
    required this.primaryTagIcon,
    required this.primaryTagAccent,
    required this.secondaryTagLabel,
    required this.secondaryTagIcon,
    required this.secondaryTagAccent,
    required this.filterPanelTitle,
    required this.summaryPanelTitle,
    required this.feedPanelTitle,
  });

  final String leadTitle;
  final String leadSubtitle;
  final IconData leadIcon;
  final Color leadAccent;
  final String primaryTagLabel;
  final IconData primaryTagIcon;
  final Color primaryTagAccent;
  final String secondaryTagLabel;
  final IconData secondaryTagIcon;
  final Color secondaryTagAccent;
  final String filterPanelTitle;
  final String summaryPanelTitle;
  final String feedPanelTitle;

  factory _HistoryRoleProfile.fromSession({
    required dynamic session,
    required HistoryOverview overview,
    required MobileSyncStatus syncStatus,
  }) {
    final primaryLabel = '${overview.totalSales} receipts';
    final primaryIcon = Icons.receipt_long_rounded;
    final primaryAccent = AppPalette.warning;
    final secondaryLabel = overview.queuedSales > 0
        ? '${overview.queuedSales} queued'
        : (syncStatus == MobileSyncStatus.syncing ? 'Syncing' : 'Replay clear');
    final secondaryIcon = overview.queuedSales > 0
        ? Icons.cloud_upload_rounded
        : (syncStatus == MobileSyncStatus.syncing
              ? Icons.sync_rounded
              : Icons.verified_rounded);
    final secondaryAccent = overview.queuedSales > 0
        ? AppPalette.warning
        : AppPalette.success;

    if (session?.isCashierLike ?? false) {
      return _HistoryRoleProfile(
        leadTitle: overview.totalSales > 0
            ? 'Recent sales are ready'
            : 'Receipt search is ready',
        leadSubtitle: 'Find receipts, check sync, open sale details.',
        leadIcon: Icons.receipt_long_rounded,
        leadAccent: AppPalette.warning,
        primaryTagLabel: primaryLabel,
        primaryTagIcon: primaryIcon,
        primaryTagAccent: primaryAccent,
        secondaryTagLabel: secondaryLabel,
        secondaryTagIcon: secondaryIcon,
        secondaryTagAccent: secondaryAccent,
        filterPanelTitle: 'Find sales',
        summaryPanelTitle: 'Quick summary',
        feedPanelTitle: 'Receipt list',
      );
    }

    if (session?.isManager ?? false) {
      return _HistoryRoleProfile(
        leadTitle: overview.totalSales > 0
            ? 'Sales history is live'
            : 'History is ready',
        leadSubtitle: 'Recent receipts, queue posture and summaries.',
        leadIcon: Icons.receipt_long_rounded,
        leadAccent: AppPalette.warning,
        primaryTagLabel: primaryLabel,
        primaryTagIcon: primaryIcon,
        primaryTagAccent: primaryAccent,
        secondaryTagLabel: secondaryLabel,
        secondaryTagIcon: secondaryIcon,
        secondaryTagAccent: secondaryAccent,
        filterPanelTitle: 'Find receipts',
        summaryPanelTitle: 'Quick summary',
        feedPanelTitle: 'Receipt list',
      );
    }

    return _HistoryRoleProfile(
      leadTitle: overview.totalSales > 0
          ? 'Receipt history is live'
          : 'History pulse is ready',
      leadSubtitle: 'Revenue, sync posture and recent sales at a glance.',
      leadIcon: Icons.receipt_long_rounded,
      leadAccent: AppPalette.warning,
      primaryTagLabel: primaryLabel,
      primaryTagIcon: primaryIcon,
      primaryTagAccent: primaryAccent,
      secondaryTagLabel: secondaryLabel,
      secondaryTagIcon: secondaryIcon,
      secondaryTagAccent: secondaryAccent,
      filterPanelTitle: 'Find receipts',
      summaryPanelTitle: 'Quick summary',
      feedPanelTitle: 'Receipt list',
    );
  }
}

/// Slim bar that keeps the receipt filters collapsed until tapped, so History
/// opens straight to the list instead of a tall filter block.
class _FilterToggleBar extends StatelessWidget {
  const _FilterToggleBar({
    required this.title,
    required this.activeCount,
    required this.expanded,
    required this.onToggle,
    this.onClear,
  });

  final String title;
  final int activeCount;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.tune_rounded, size: 20, color: AppPalette.primary),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (activeCount > 0) ...<Widget>[
            const SizedBox(width: 8),
            MobileTag(label: '$activeCount', accent: AppPalette.info),
          ],
          const Spacer(),
          if (onClear != null)
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
              ),
              child: const Text('Clear'),
            ),
          IconButton(
            onPressed: onToggle,
            tooltip: expanded ? 'Hide filters' : 'Filter receipts',
            icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncFilterChip extends StatelessWidget {
  const _SyncFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final activeColor = AppPalette.info;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active
            ? activeColor.withValues(alpha: 0.14)
            : colors.surfaceStrong,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                color: active ? activeColor : colors.textTertiary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistorySaleRow extends StatelessWidget {
  const _HistorySaleRow({required this.sale, required this.onTap});

  final RecentSaleSummary sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tone = _syncTone(context, sale.syncState);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: colors.surfaceStrong.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: tone),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        formatCurrency(sale.total),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${sale.displayTitle} | ${sale.date}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black.withValues(alpha: 0.58),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          MobileTag(
                            label: sale.paymentMode,
                            icon: Icons.payments_rounded,
                            accent: AppPalette.primary,
                          ),
                          if (sale.hasOutstandingDue &&
                              sale.syncState != CommerceSyncState.refunded)
                            MobileTag(
                              label: 'Due ${formatCurrency(sale.amountDue)}',
                              icon: Icons.warning_amber_rounded,
                              accent: AppPalette.warning,
                            ),
                          Text(
                            'Tap for detail',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.black.withValues(alpha: 0.56),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _syncLabel(sale.syncState),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SaleDetailSection extends StatelessWidget {
  const _SaleDetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MobileSheetSection(
      title: title,
      accent: AppPalette.warning,
      child: child,
    );
  }
}

class _SaleItemRow extends StatelessWidget {
  const _SaleItemRow({required this.item});

  final SaleDetailItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.name,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatQty(item.quantity)} x ${formatCurrency(item.unitPrice)}'
                '${item.size?.isNotEmpty == true ? ' | ${item.size}' : ''}'
                '${item.gstRate > 0 ? ' | GST ${item.gstRate.toStringAsFixed(item.gstRate.truncateToDouble() == item.gstRate ? 0 : 2)}%' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (item.taxAmount > 0.009) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  'Taxable ${formatCurrency(item.taxableAmount)} | Tax ${formatCurrency(item.taxAmount)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.info.withValues(alpha: 0.86),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          formatCurrency(item.lineTotal),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppPalette.success,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _SalePaymentRow extends StatelessWidget {
  const _SalePaymentRow({required this.payment});

  final SaleDetailPayment payment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                payment.mode,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if ((payment.referenceCode ?? '').isNotEmpty ||
                  (payment.note ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  payment.referenceCode ?? payment.note!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          formatCurrency(payment.amount),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppPalette.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _HistoryMetricTile extends StatelessWidget {
  const _HistoryMetricTile({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.black.withValues(alpha: 0.58),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tone,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryPaymentMixRow extends StatelessWidget {
  const _HistoryPaymentMixRow({required this.mix});

  final PaymentModeMixStats mix;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    mix.mode,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${mix.count} receipt(s) Â· ${mix.shareLabel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black.withValues(alpha: 0.58),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatCurrency(mix.grossAmount),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppPalette.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleSummaryRow extends StatelessWidget {
  const _SaleSummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: emphasize ? colors.textPrimary : Colors.black.withValues(alpha: 0.72),
      fontWeight: emphasize ? FontWeight.w900 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(value, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

String _syncLabel(CommerceSyncState state) {
  return switch (state) {
    CommerceSyncState.localOnly => 'LOCAL',
    CommerceSyncState.queued => 'QUEUED',
    CommerceSyncState.syncing => 'SYNCING',
    CommerceSyncState.synced => 'SYNCED',
    // Transient: the outbox re-picks these up automatically.
    CommerceSyncState.failed => 'RETRYING',
    CommerceSyncState.refunded => 'REFUNDED',
  };
}

const List<String> _historyPaymentModes = <String>[
  'CASH',
  'UPI',
  'BANK',
  'CARD',
  'CREDIT',
  'OTHER',
  'SPLIT',
  'OTHERS',
];

Color _syncTone(BuildContext context, CommerceSyncState state) {
  return switch (state) {
    CommerceSyncState.synced => AppPalette.success,
    CommerceSyncState.queued => AppPalette.warning,
    CommerceSyncState.syncing => AppPalette.primary,
    CommerceSyncState.failed => AppPalette.warning,
    CommerceSyncState.localOnly => AppColors.of(context).textTertiary,
    CommerceSyncState.refunded => AppPalette.error,
  };
}


