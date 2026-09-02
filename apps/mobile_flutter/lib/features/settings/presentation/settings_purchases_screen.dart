import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

/// Stock buying and supplier dues. Purchases are money-out with a running
/// payable; suppliers roll up from those purchases. Fully local-first.
class SettingsPurchasesScreen extends ConsumerWidget {
  const SettingsPurchasesScreen({super.key});

  static const List<String> _paymentMethods = <String>[
    'CASH',
    'UPI',
    'CARD',
    'BANK',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final summary = ref.watch(purchaseSummaryProvider).asData?.value;
    final suppliers =
        ref.watch(supplierDuesProvider).asData?.value ?? const <SupplierDue>[];
    final purchases =
        ref.watch(purchasesProvider).asData?.value ?? const <PurchaseRecord>[];
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final canManage = session != null && !session.isReadOnly;

    return MobileStandaloneScaffold(
      title: L.of(context).purSuppliers,
      trailing: canManage
          ? IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Record purchase',
              onPressed: () => _openPurchaseSheet(context, ref),
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: MobileMetricCard(
                  label: 'Stock bought',
                  value: formatCurrency(summary?.totalSpent ?? 0),
                  icon: Icons.local_shipping_rounded,
                  accent: AppPalette.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MobileMetricCard(
                  label: 'You owe',
                  value: formatCurrency(summary?.totalPayable ?? 0),
                  icon: Icons.account_balance_wallet_rounded,
                  accent: (summary?.totalPayable ?? 0) > 0
                      ? AppPalette.error
                      : AppPalette.success,
                  caption: '${summary?.supplierCount ?? 0} supplier(s)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (canManage)
            FilledButton.icon(
              onPressed: () => _openPurchaseSheet(context, ref),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Record purchase'),
            ),
          if (suppliers.any((s) => s.payable > 0)) ...<Widget>[
            const SizedBox(height: 16),
            AppPanel(
              title: L.of(context).purOutstanding,
              action: const MobileTag(
                label: 'PAYABLE',
                icon: Icons.trending_up_rounded,
              ),
              child: Column(
                children: <Widget>[
                  for (final s in suppliers.where((s) => s.payable > 0))
                    _SupplierRow(supplier: s),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          AppPanel(
            title: L.of(context).purRecent,
            action: MobileTag(
              label: '${purchases.length} ENTRIES',
              icon: Icons.receipt_long_rounded,
            ),
            child: purchases.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        canManage
                            ? 'No purchases yet. Record your first stock '
                                  'purchase to start tracking supplier dues.'
                            : 'No purchases recorded yet.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final p in purchases)
                        _PurchaseRow(
                          purchase: p,
                          canManage: canManage,
                          onSettle: () => _openSettleSheet(context, ref, p),
                          onDelete: () => _confirmDelete(context, ref, p),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPurchaseSheet(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final referenceController = TextEditingController();
    final totalController = TextEditingController();
    final paidController = TextEditingController();
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final stockLines = <_PurchaseStockDraft>[];
    var method = 'CASH';
    var date = DateTime.now();
    var saving = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              if (formKey.currentState?.validate() != true || saving) return;
              setSheetState(() {
                saving = true;
                errorText = null;
              });
              try {
                final total = double.parse(totalController.text.trim());
                final paid = paidController.text.trim().isEmpty
                    ? 0.0
                    : double.parse(paidController.text.trim());
                final actorName = ref
                    .read(mobileSessionProvider)
                    .asData
                    ?.value
                    ?.user
                    .displayName;
                final supplier = nameController.text.trim();
                final purchaseId = await ref
                    .read(mobileSyncCoordinatorProvider)
                    .recordPurchase(
                      supplierName: supplier,
                      supplierPhone: phoneController.text.trim(),
                      reference: referenceController.text.trim(),
                      total: total,
                      amountPaid: paid,
                      paymentMethod: method,
                      notes: notesController.text.trim(),
                      purchaseDate: date,
                      actorName: actorName,
                    );
                // Optional bridge: raise inventory stock for any received items.
                final inventory = ref.read(inventoryRepositoryProvider);
                for (final line in stockLines) {
                  final qty = double.tryParse(line.qty.text.trim()) ?? 0;
                  if (line.itemId == null || qty <= 0) continue;
                  final unitCost = double.tryParse(line.cost.text.trim());
                  await inventory.applyStockIn(
                    itemId: line.itemId!,
                    quantity: qty,
                    unitCost: unitCost,
                    refId: purchaseId,
                    actorName: actorName,
                    note: supplier.isEmpty
                        ? 'Purchase'
                        : 'Purchase from $supplier',
                  );
                }
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (error) {
                setSheetState(() {
                  saving = false;
                  errorText = error.toString();
                });
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  24 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Form(
                  key: formKey,
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      const MobileSheetHeader(
                        eyebrow: 'Stock buying',
                        title: 'Record purchase',
                        subtitle:
                            'What you bought, and how much you paid now. The '
                            'rest becomes a supplier due.',
                        icon: Icons.local_shipping_rounded,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Supplier name',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Supplier name is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Supplier phone (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Bill / invoice no. (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: totalController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Total bill amount',
                        ),
                        validator: (v) {
                          final parsed = double.tryParse(v?.trim() ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: paidController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Paid now (blank = nothing paid)',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final paid = double.tryParse(v.trim());
                          if (paid == null || paid < 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: method,
                        decoration: const InputDecoration(
                          labelText: 'Payment method',
                        ),
                        items: <DropdownMenuItem<String>>[
                          for (final m in _paymentMethods)
                            DropdownMenuItem<String>(value: m, child: Text(m)),
                        ],
                        onChanged: (v) =>
                            setSheetState(() => method = v ?? 'CASH'),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today_rounded),
                        title: const Text('Purchase date'),
                        subtitle: Text(date.toIso8601String().split('T').first),
                        trailing: TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: sheetContext,
                              initialDate: date,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setSheetState(() => date = picked);
                            }
                          },
                          child: const Text('Change'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              'Received items → stock',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const MobileTag(
                            label: 'OPTIONAL',
                            icon: Icons.inventory_2_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add items you received to raise their stock '
                        'automatically. Cost updates the item too.',
                        style: Theme.of(sheetContext).textTheme.bodySmall
                            ?.copyWith(
                              color: AppColors.of(sheetContext).textSecondary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < stockLines.length; i++)
                        _buildStockLineRow(
                          sheetContext,
                          stockLines[i],
                          () => setSheetState(
                            () => stockLines.removeAt(i).dispose(),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final item = await _pickInventoryItem(
                                  sheetContext,
                                  ref,
                                );
                                if (item != null) {
                                  setSheetState(
                                    () => stockLines.add(
                                      _PurchaseStockDraft(
                                        itemId: item.id,
                                        itemName: item.name,
                                        initialCost: item.costPrice,
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add received item'),
                      ),
                      if (errorText != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: const TextStyle(color: AppPalette.error),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: saving ? null : save,
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(saving ? 'Saving...' : 'Save purchase'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStockLineRow(
    BuildContext context,
    _PurchaseStockDraft line,
    VoidCallback onRemove,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.of(context).borderSoft),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              line.itemName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: line.qty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Qty',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: line.cost,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Cost',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  /// Simple searchable inventory picker for linking received items.
  Future<InventoryCatalogItem?> _pickInventoryItem(
    BuildContext context,
    WidgetRef ref,
  ) {
    final searchController = TextEditingController();
    return showModalBottomSheet<InventoryCatalogItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  18 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      textCapitalization: TextCapitalization.sentences,
                      controller: searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Search item',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: StreamBuilder<List<InventoryCatalogItem>>(
                        stream: ref
                            .read(inventoryRepositoryProvider)
                            .watchCatalogPage(
                              search: searchController.text.trim(),
                              pageSize: 30,
                              includeCost: true,
                            ),
                        builder: (context, snapshot) {
                          final items =
                              snapshot.data ?? const <InventoryCatalogItem>[];
                          if (items.isEmpty) {
                            return const Center(child: Text('No items found.'));
                          }
                          return ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return ListTile(
                                title: Text(item.name),
                                subtitle: Text(
                                  'Stock ${formatQty(item.stock)} · ${formatCurrency(item.price)}',
                                ),
                                onTap: () => Navigator.pop(sheetContext, item),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSettleSheet(
    BuildContext context,
    WidgetRef ref,
    PurchaseRecord purchase,
  ) async {
    final amountController = TextEditingController(
      text: purchase.balanceDue.toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> pay() async {
              if (formKey.currentState?.validate() != true || saving) return;
              setSheetState(() => saving = true);
              await ref
                  .read(purchaseRepositoryProvider)
                  .settlePurchase(
                    purchaseId: purchase.id,
                    amount: double.parse(amountController.text.trim()),
                  );
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  24 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      MobileSheetHeader(
                        eyebrow: purchase.supplierName,
                        title: 'Settle due',
                        subtitle:
                            'Outstanding ${formatCurrency(purchase.balanceDue)} '
                            'on this purchase.',
                        icon: Icons.payments_rounded,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Payment amount',
                        ),
                        validator: (v) {
                          final parsed = double.tryParse(v?.trim() ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: saving ? null : pay,
                        icon: const Icon(Icons.payments_rounded),
                        label: Text(saving ? 'Saving...' : 'Record payment'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PurchaseRecord purchase,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text(
          '${purchase.supplierName} · ${formatCurrency(purchase.total)} will be '
          'removed. This also clears any due it carried.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppPalette.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(purchaseRepositoryProvider).deletePurchase(purchase.id);
    }
  }
}

class _PurchaseStockDraft {
  _PurchaseStockDraft({
    required this.itemId,
    required this.itemName,
    double? initialCost,
  }) {
    if (initialCost != null && initialCost > 0) {
      cost.text = initialCost.toStringAsFixed(2);
    }
  }

  final String? itemId;
  final String itemName;
  final TextEditingController qty = TextEditingController(text: '1');
  final TextEditingController cost = TextEditingController();

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({required this.supplier});

  final SupplierDue supplier;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  supplier.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${supplier.purchaseCount} purchase(s) · '
                  '${formatCurrency(supplier.totalPurchased)} bought',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            formatCurrency(supplier.payable),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppPalette.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({
    required this.purchase,
    required this.canManage,
    required this.onSettle,
    required this.onDelete,
  });

  final PurchaseRecord purchase;
  final bool canManage;
  final VoidCallback onSettle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final settled = purchase.isSettled;
    final subtitleParts = <String>[
      purchase.purchaseDate.toIso8601String().split('T').first,
      purchase.paymentMethod,
      if (purchase.reference.isNotEmpty) '#${purchase.reference}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  purchase.supplierName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitleParts.join(' · '),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                if (purchase.notes.isNotEmpty)
                  Text(
                    purchase.notes,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatCurrency(purchase.total),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              MobileTag(
                label: settled
                    ? 'PAID'
                    : 'DUE ${formatCurrency(purchase.balanceDue)}',
                accent: settled ? AppPalette.success : AppPalette.error,
              ),
              if (canManage && !settled)
                TextButton(
                  onPressed: onSettle,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Settle'),
                ),
              if (canManage)
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppPalette.error,
                  ),
                  child: const Text('Delete'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
