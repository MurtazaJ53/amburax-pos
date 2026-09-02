import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/widgets/adaptive_layout.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/pos/cart_pricing.dart';
import '../../../core/pos/held_sales.dart';
import '../../../core/pos/upi_qr.dart';
import '../../../core/pos/weight_barcode.dart';
import '../../../core/security/manager_gate.dart';
import 'upi_qr_view.dart';
import '../../../core/receipt/receipt_pdf.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/printer/receipt_printer.dart';
import '../../../core/providers/printer_provider.dart';
import '../../../core/runtime/mobile_runtime_config.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/tax/gst.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../ui/ui.dart';
import '../../shell/presentation/mobile_surface.dart';
import 'checkout_payment_sheet.dart';
import 'pos_catalog_grouping.dart';
import 'pos_scanner_sheet.dart';

/// Point of Sale — clean product list, editable cart, prominent total.
class PosScreenV3 extends ConsumerStatefulWidget {
  const PosScreenV3({super.key});

  @override
  ConsumerState<PosScreenV3> createState() => _PosScreenV3State();
}

class _PosScreenV3State extends ConsumerState<PosScreenV3> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final List<PosCartItem> _cart = <PosCartItem>[];

  /// Loyalty points held by the customer attached to this bill.
  int _customerPoints = 0;

  String _search = '';
  String? _selectedCategory;
  bool _saving = false;
  bool _discountIsPercent = false;
  DateTime? _saleDate; // null = today
  Timer? _searchDebounce;

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = value);
    });
  }

  static const int _pageSize = 50;

  double get _cartTotal => CartPricing.subtotal(_cart);
  int get _cartCount =>
      _cart.fold<double>(0, (sum, item) => sum + item.quantity).round();

  // GST is computed on the discounted (net) cart so the tax shown matches the
  // amount actually charged.
  GstCartSummary get _gstSummary =>
      computeCartGst(_cart, discount: _discountAmount);

  double get _discountAmount => CartPricing.discountAmount(
    subtotal: _cartTotal,
    value: double.tryParse(_discountController.text.trim()) ?? 0,
    isPercent: _discountIsPercent,
  );

  /// How far the bill has fallen below what the stock cost, after every
  /// discount. Only counts lines where a cost price is actually known, so an
  /// item with no cost never produces a false warning.
  double get _belowCostBy {
    var cost = 0.0;
    var priced = 0.0;
    for (final line in _cart) {
      final unitCost = line.costPrice;
      if (unitCost == null || unitCost <= 0) continue;
      cost += unitCost * line.quantity;
      priced += line.lineTotal;
    }
    if (cost <= 0) return 0;
    // Spread the bill-level discount only across lines we can judge.
    final share = _cartTotal <= 0 ? 0.0 : priced / _cartTotal;
    final net = priced - (_discountAmount * share);
    final gap = cost - net;
    return gap > 0.009 ? gap : 0;
  }

  double get _netTotal =>
      CartPricing.net(subtotal: _cartTotal, discount: _discountAmount);

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _discountController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _addCustomItem() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Price'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final name = nameController.text.trim();
    final price = double.tryParse(priceController.text.trim()) ?? 0;
    nameController.dispose();
    priceController.dispose();
    if (added != true || name.isEmpty || price <= 0) return;
    setState(() {
      _cart.add(
        PosCartItem(
          id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          price: price,
          quantity: 1,
          stock: 999999,
          category: 'Custom',
        ),
      );
    });
  }

  /// Sell loose goods by weight: rate (per kg/unit) x weight -> a priced line.
  /// Uses a non-inventory line, so it needs no fractional-stock plumbing.
  Future<void> _addWeighedItem() async {
    final nameController = TextEditingController();
    final rateController = TextEditingController();
    final weightController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final rate = double.tryParse(rateController.text.trim()) ?? 0;
          final weight = double.tryParse(weightController.text.trim()) ?? 0;
          final linePrice = weighedLinePrice(rate: rate, weight: weight);
          return AlertDialog(
            title: const Text('Weighed item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Item (e.g. Rice)',
                  ),
                ),
                TextField(
                  controller: rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Rate per kg/unit',
                  ),
                ),
                TextField(
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(labelText: 'Weight / qty'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Line total: ${formatCurrency(linePrice)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
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
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
    final name = nameController.text.trim();
    final rate = double.tryParse(rateController.text.trim()) ?? 0;
    final weight = double.tryParse(weightController.text.trim()) ?? 0;
    final linePrice = weighedLinePrice(rate: rate, weight: weight);
    nameController.dispose();
    rateController.dispose();
    weightController.dispose();
    if (added != true || name.isEmpty || linePrice <= 0) return;
    _addCartLine(
      id: 'weigh-${DateTime.now().microsecondsSinceEpoch}',
      name: '$name (${_trimNum(weight)} @ ${formatCurrency(rate)})',
      price: linePrice,
    );
  }

  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  // ---- cart mutations -------------------------------------------------------

  void _warnLowStock(String name, double stock) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Only ${formatQuantity(stock)} of $name left in stock.'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppPalette.warning,
      ),
    );
  }

  void _addToCart(InventoryCatalogItem item) {
    final existingIndex = _cart.indexWhere((c) => c.id == item.id);
    final nextQty = existingIndex >= 0 ? _cart[existingIndex].quantity + 1 : 1;
    setState(() {
      final index = _cart.indexWhere((c) => c.id == item.id);
      if (index >= 0) {
        _cart[index] = _cart[index].copyWith(
          quantity: _cart[index].quantity + 1,
        );
      } else {
        _cart.add(
          PosCartItem(
            id: item.id,
            name: item.name,
            price: item.price,
            quantity: 1,
            stock: item.stock,
            category: item.category,
            size: item.size,
            sku: item.sku,
            costPrice: item.costPrice,
            hsnCode: item.hsnCode,
            gstRate: item.gstRate,
            priceIncludesTax: item.priceIncludesTax,
          ),
        );
      }
    });
    HapticFeedback.selectionClick();
    if (item.stock < 999999 && nextQty > item.stock) {
      _warnLowStock(item.name, item.stock);
    }
  }

  void _changeQtyById(String id, int delta) {
    final index = _cart.indexWhere((c) => c.id == id);
    if (index < 0) return;
    final line = _cart[index];
    final next = line.quantity + delta;
    setState(() {
      if (next <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index] = line.copyWith(quantity: next);
      }
    });
    if (delta > 0 && line.stock < 999999 && next > line.stock) {
      _warnLowStock(line.name, line.stock);
    }
  }

  /// Set an exact (possibly fractional, e.g. 1.5 kg) quantity on a cart line.
  void _setLineQuantity(String id, double qty) {
    final index = _cart.indexWhere((c) => c.id == id);
    if (index < 0) return;
    setState(() {
      if (qty <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index] = _cart[index].copyWith(quantity: qty);
      }
    });
  }

  /// Set a per-item discount (money off just this line). Clamped to the line
  /// total so a line can never go negative.
  void _setLineDiscount(String id, double discount) {
    final index = _cart.indexWhere((c) => c.id == id);
    if (index < 0) return;
    setState(() {
      final line = _cart[index];
      final safe = discount < 0 ? 0.0 : discount;
      _cart[index] = line.copyWith(
        discount: safe > line.grossLineTotal ? line.grossLineTotal : safe,
      );
    });
  }

  double _qtyInCart(String id) {
    final index = _cart.indexWhere((c) => c.id == id);
    return index < 0 ? 0 : _cart[index].quantity;
  }

  Future<void> _openVariantPicker(VariantGroup group) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    MobileSheetHeader(
                      eyebrow: 'Choose variant',
                      title: group.baseName,
                      subtitle:
                          '${group.variants.length} variants · tap to add to '
                          'the bill.',
                      icon: Icons.category_rounded,
                    ),
                    const SizedBox(height: 12),
                    ...group.variants.map((v) {
                      final qty = _qtyInCart(v.id);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    v.variantLabel ?? v.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${formatCurrency(v.price)} · stock ${formatQuantity(v.stock)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: v.isLowStock
                                          ? AppPalette.error
                                          : AppColors.of(
                                              sheetContext,
                                            ).textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            qty > 0
                                ? QuantityStepper(
                                    quantity: qty,
                                    onIncrement: () {
                                      _changeQtyById(v.id, 1);
                                      setSheetState(() {});
                                    },
                                    onDecrement: () {
                                      _changeQtyById(v.id, -1);
                                      setSheetState(() {});
                                    },
                                  )
                                : _AddButton(
                                    onTap: () {
                                      _addToCart(v);
                                      setSheetState(() {});
                                    },
                                  ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---- actions --------------------------------------------------------------

  void _holdCurrentSale() {
    if (_cart.isEmpty) return;
    ref
        .read(heldSalesProvider.notifier)
        .hold(
          HeldSale(
            id: 'held-${DateTime.now().microsecondsSinceEpoch}',
            items: List<PosCartItem>.from(_cart),
            discountText: _discountController.text,
            discountIsPercent: _discountIsPercent,
            customerName: _customerNameController.text,
            customerPhone: _customerPhoneController.text,
            saleDate: _saleDate,
            heldAt: DateTime.now(),
          ),
        );
    _discountController.clear();
    _customerNameController.clear();
    _customerPhoneController.clear();
    setState(() {
      _cart.clear();
      _discountIsPercent = false;
      _saleDate = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sale held.')));
  }

  void _resumeHeldSale(HeldSale held) {
    _discountController.text = held.discountText;
    _customerNameController.text = held.customerName;
    _customerPhoneController.text = held.customerPhone;
    setState(() {
      _cart
        ..clear()
        ..addAll(held.items);
      _discountIsPercent = held.discountIsPercent;
      _saleDate = held.saleDate;
    });
    ref.read(heldSalesProvider.notifier).remove(held.id);
  }

  Future<void> _showHeldSales() async {
    final held = ref.read(heldSalesProvider);
    if (held.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = AppColors.of(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Held sales',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ...held.map(
                  (h) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.borderSoft),
                    ),
                    child: ListTile(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _resumeHeldSale(h);
                      },
                      leading: const Icon(
                        Icons.pause_circle_filled_rounded,
                        color: AppPalette.primary,
                      ),
                      title: Text(
                        h.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${h.itemCount} item${h.itemCount == 1 ? '' : 's'} · ${formatCurrency(h.total)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: AppPalette.error,
                        onPressed: () {
                          ref.read(heldSalesProvider.notifier).remove(h.id);
                          Navigator.pop(sheetContext);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openScanner(List<InventoryCatalogItem> items) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PosScannerSheet(),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    // Price/weight-embedded scale barcode: match the item by its PLU digits and
    // charge the embedded price for this line.
    final weigh = parseWeightBarcode(code.trim());
    if (weigh != null) {
      final plu = weigh.itemCode.toLowerCase();
      final byPlu = items.where((item) {
        final sku = item.sku?.toLowerCase() ?? '';
        return sku == plu || sku.contains(plu) || item.id.toLowerCase() == plu;
      }).toList();
      final name = byPlu.isNotEmpty ? byPlu.first.name : 'Weighed item $plu';
      // For a weight-embedded barcode charge rate x weight using the matched
      // item's price; a price-embedded barcode charges the embedded amount.
      final rate = byPlu.isNotEmpty ? byPlu.first.price : 0.0;
      final linePrice = weigh.resolveLinePrice(rate);
      _addCartLine(
        id: 'weigh-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        price: linePrice,
        category: byPlu.isNotEmpty ? byPlu.first.category : 'General',
        gstRate: byPlu.isNotEmpty ? byPlu.first.gstRate : 0,
        priceIncludesTax: byPlu.isNotEmpty
            ? byPlu.first.priceIncludesTax
            : true,
      );
      return;
    }

    final needle = code.trim().toLowerCase();
    final match = items.where((item) {
      final sku = item.sku?.toLowerCase() ?? '';
      return sku == needle || item.id.toLowerCase() == needle;
    }).toList();
    if (match.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No product matches "$code".')));
      return;
    }
    _addToCart(match.first);
  }

  /// Add an arbitrary line to the cart (custom/open item, or a weighed item)
  /// without needing an inventory SKU. Uses a very high stock so no low-stock
  /// warnings fire; ids are non-inventory so no stock is decremented on sale.
  void _addCartLine({
    required String id,
    required String name,
    required double price,
    String category = 'General',
    double gstRate = 0,
    bool priceIncludesTax = true,
  }) {
    setState(() {
      _cart.add(
        PosCartItem(
          id: id,
          name: name,
          price: price,
          quantity: 1,
          stock: 999999,
          category: category,
          gstRate: gstRate,
          priceIncludesTax: priceIncludesTax,
        ),
      );
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _openCart() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CartSheet(
        cart: _cart,
        onChangeQty: _changeQtyById,
        onSetQty: _setLineQuantity,
        onSetLineDiscount: _setLineDiscount,
        gstSummary: () => _gstSummary,
        grossTotal: () => _cartTotal,
        discountAmount: () => _discountAmount,
        netTotal: () => _netTotal,
        discountController: _discountController,
        isPercent: () => _discountIsPercent,
        onToggleType: () =>
            setState(() => _discountIsPercent = !_discountIsPercent),
        customerNameController: _customerNameController,
        customerPhoneController: _customerPhoneController,
        saleDate: () => _saleDate,
        onPickDate: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _saleDate ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
          );
          if (picked != null && mounted) {
            setState(() => _saleDate = picked);
          }
        },
        onPickCustomer: _pickCustomer,
      ),
    );
    setState(() {}); // reflect any edits made inside the sheet
    if (action == 'checkout' && mounted) {
      await _openCheckout();
    }
  }

  /// Mandatory customer capture for a credit (part/unpaid) sale. Name and
  /// mobile are required; address is optional. Returns null if the cashier
  /// backs out (the sale is then not completed).
  Future<Map<String, String>?> _captureCreditCustomer({
    required double due,
    required String name,
    required String phone,
  }) async {
    final nameCtrl = TextEditingController(text: name);
    final phoneCtrl = TextEditingController(text: phone);
    final addressCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Credit sale — add customer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${formatCurrency(due)} will be recorded as due. A name and '
                    'mobile number are required so you can recover it later.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Customer name *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile number *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final n = nameCtrl.text.trim();
                    final p = phoneCtrl.text.trim();
                    if (n.isEmpty || p.length < 7) {
                      setDialogState(
                        () => error = 'Enter a name and a valid mobile number.',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, <String, String>{
                      'name': n,
                      'phone': p,
                      'address': addressCtrl.text.trim(),
                    });
                  },
                  child: const Text('Save & complete'),
                ),
              ],
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    return result;
  }

  /// When a sale leaves a balance due, attach it to a real customer (matched
  /// by phone, or created) so the due lands in the Clients khata. Returns the
  /// customer id to record on the sale, or null for a fully-paid walk-in.
  Future<String?> _resolveCustomerForSale({
    required List<PosPayment> payments,
    required String customerName,
    required String customerPhone,
    String customerAddress = '',
  }) async {
    final paid = payments.fold<double>(0, (sum, p) => sum + p.amount);
    final saleDue = _netTotal - paid;
    final hasCustomer = customerName.isNotEmpty || customerPhone.isNotEmpty;
    if (saleDue <= 0.009 || !hasCustomer) {
      return null;
    }

    final existing =
        ref.read(customersProvider).asData?.value ??
        const <BackendCustomerSummary>[];
    if (customerPhone.isNotEmpty) {
      for (final c in existing) {
        if ((c.phone ?? '').trim() == customerPhone) {
          return c.id;
        }
      }
    }

    final now = DateTime.now();
    final session = ref.read(mobileSessionProvider).asData?.value;
    final resolvedName = customerName.isEmpty ? 'Customer' : customerName;

    // Push the new customer to the server so the credit due lands in a real,
    // recoverable khata and the synced sale can reference a valid customer id.
    // Fall back to a local record when offline (the sale still records the
    // name/phone; the pull reconciles the customer later).
    if (session != null &&
        session.hasShop &&
        MobileRuntimeConfig.backendSyncEnabled) {
      try {
        final created = await ref
            .read(backendApiClientProvider)
            .createCustomer(
              user: session.user,
              shopId: session.shopId!,
              name: resolvedName,
              phone: customerPhone,
              notes: customerAddress.isEmpty ? '' : 'Address: $customerAddress',
            );
        await ref
            .read(customerRepositoryProvider)
            .mergeRemoteCustomerDocument(created.id, <String, dynamic>{
              'name': created.name,
              'phone': created.phone ?? customerPhone,
              'status': 'active',
              'balance': created.balance,
              'total_spent': created.totalSpent,
              'tombstone': false,
              'updatedAt': now.toIso8601String(),
            }, updatedAt: now.millisecondsSinceEpoch);
        return created.id;
      } catch (_) {
        // fall through to local-only creation
      }
    }

    final id = 'local-cust-${now.microsecondsSinceEpoch}';
    await ref
        .read(customerRepositoryProvider)
        .mergeRemoteCustomerDocument(id, <String, dynamic>{
          'name': resolvedName,
          'phone': customerPhone,
          if (customerAddress.isNotEmpty) 'address': customerAddress,
          'status': 'active',
          'balance': 0,
          'total_spent': 0,
          'tombstone': false,
          'updatedAt': now.toIso8601String(),
        }, updatedAt: now.millisecondsSinceEpoch);
    return id;
  }

  Future<void> _pickCustomer() async {
    final all =
        ref.read(customersProvider).asData?.value ??
        const <BackendCustomerSummary>[];
    final searchController = TextEditingController();
    final selected = await showModalBottomSheet<BackendCustomerSummary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = AppColors.of(sheetContext);
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final q = searchController.text.trim().toLowerCase();
            final filtered = q.isEmpty
                ? all
                : all
                      .where(
                        (c) =>
                            c.name.toLowerCase().contains(q) ||
                            (c.phone ?? '').contains(q),
                      )
                      .toList(growable: false);
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Choose customer',
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: searchController,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search name or phone',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('No customers found.'),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: filtered
                                    .map(
                                      (c) => ListTile(
                                        leading: const Icon(
                                          Icons.person_rounded,
                                        ),
                                        title: Text(
                                          c.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${c.phone ?? ''}${c.balance > 0 ? ' · due ${formatCurrency(c.balance)}' : ''}',
                                        ),
                                        onTap: () =>
                                            Navigator.pop(sheetContext, c),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
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
    searchController.dispose();
    if (selected != null) {
      _customerNameController.text = selected.name;
      _customerPhoneController.text = selected.phone ?? '';
      _customerPoints = selected.loyaltyPoints;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openCheckout() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    final shop =
        ref.read(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    final salesRepository = ref.read(salesRepositoryProvider);
    final syncCoordinator = ref.read(mobileSyncCoordinatorProvider);
    final activeShopId = session?.shopId;

    if (activeShopId == null || activeShopId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop session is still loading.')),
      );
      return;
    }
    if (_cart.isEmpty) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CheckoutPaymentSheet(
        cartTotal: _netTotal,
        gstSummary: _gstSummary,
        upiVpa: shop.upiVpa.trim(),
        shopName: shop.name,
        availablePoints: _customerPoints,
      ),
    );
    if (result == null || !mounted) return;

    // Selling below cost is a silent way to lose money — the bill still looks
    // fine, it just doesn't cover what the stock cost. Warn before saving.
    final belowCost = _belowCostBy;
    if (belowCost > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Selling below cost'),
          content: Text(
            'This bill is ${formatCurrency(belowCost)} below what the stock '
            'cost you.\n\nSave it anyway?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: AppPalette.error),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    // Fraud guard: a discount above zero needs manager approval (no-op unless a
    // manager PIN is configured). Same gate can wrap void / Khata-delete flows.
    if (_discountAmount > 0) {
      final approved = await ManagerGate.requireManagerApproval(
        context,
        reason:
            'Approve a ${formatCurrency(_discountAmount)} discount on this sale?',
      );
      if (!approved || !mounted) return;
    }

    final payments = result['payments'] as List<PosPayment>;
    final paymentMode = result['paymentMode'] as String;
    final buyerGstin = result['buyerGstin'] as String?;
    var customerName = _customerNameController.text.trim();
    var customerPhone = _customerPhoneController.text.trim();
    var customerAddress = '';

    // Credit (udhaar) guard: a sale that leaves a balance due MUST be tied to a
    // customer with a name and mobile number, so the due is recoverable from
    // the Clients khata. Address stays optional. Fully-paid sales skip this.
    final paidNow = payments.fold<double>(0, (sum, p) => sum + p.amount);
    final creditDue = _netTotal - paidNow;
    if (creditDue > 0.009 && (customerName.isEmpty || customerPhone.isEmpty)) {
      final captured = await _captureCreditCustomer(
        due: creditDue,
        name: customerName,
        phone: customerPhone,
      );
      if (captured == null || !mounted) {
        return; // cancelled — do not complete an untracked credit sale
      }
      customerName = (captured['name'] ?? '').trim();
      customerPhone = (captured['phone'] ?? '').trim();
      customerAddress = (captured['address'] ?? '').trim();
      _customerNameController.text = customerName;
      _customerPhoneController.text = customerPhone;
    }

    setState(() => _saving = true);
    try {
      final customerId = await _resolveCustomerForSale(
        payments: payments,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
      );
      final redeemPoints = (result['redeemPoints'] as int?) ?? 0;
      final commit = await salesRepository.recordLocalSale(
        shopId: activeShopId,
        redeemPoints: redeemPoints,
        items: List<PosCartItem>.from(_cart),
        payments: payments,
        paymentMode: paymentMode,
        footerNote: shop.footer,
        buyerGstin: buyerGstin,
        discount: _discountAmount,
        customerId: customerId,
        customerName: customerName.isEmpty ? null : customerName,
        customerPhone: customerPhone.isEmpty ? null : customerPhone,
        saleDate: _saleDate,
      );
      // Kick the cash drawer for cash sales (no-op without a connected drawer).
      if (paymentMode == 'CASH') {
        unawaited(ref.read(receiptPrinterProvider).openCashDrawer());
      }
      // Auto-print the receipt when a printer is paired. printTaxInvoice throws
      // if nothing is connected, so this is best-effort: no printer simply means
      // the on-screen receipt sheet below is the confirmation.
      unawaited(_autoPrintReceipt(commit.saleId, shop));
      if (!mounted) return;
      // Local-first: the sale is committed to the device now, so confirm and
      // reset immediately. Backend sync runs in the background (its result is
      // reflected by the sync status chip), so checkout never waits on the
      // network.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sale saved: ${formatCurrency(commit.total)}'),
          backgroundColor: AppPalette.success,
        ),
      );
      _discountController.clear();
      _customerNameController.clear();
      _customerPhoneController.clear();
      setState(() {
        _cart.clear();
        _customerPoints = 0;
        _discountIsPercent = false;
        _saleDate = null;
        _saving = false;
      });
      unawaited(syncCoordinator.submitSale(commit));
      if (mounted) await _showReceiptSheet(commit);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sale failed: $error'),
          backgroundColor: AppPalette.error,
        ),
      );
    }
  }

  /// Best-effort receipt print straight after a sale. Never surfaces an error
  /// when no printer is paired — that's the normal case for most shops.
  Future<void> _autoPrintReceipt(String saleId, ShopInfo shop) async {
    try {
      final detail = await ref
          .read(salesRepositoryProvider)
          .getSaleDetail(saleId);
      if (detail == null) return;
      if (!ReceiptPrinterService.supportsBluetoothPrinting) return;
      await ref.read(receiptPrinterProvider).printTaxInvoice(detail, shop);
    } catch (_) {
      // No printer connected (or it failed) — the receipt sheet still shows.
    }
  }

  Future<void> _shareReceipt(String saleId) async {
    try {
      final detail = await ref
          .read(salesRepositoryProvider)
          .getSaleDetail(saleId);
      final shop = ref.read(shopInfoProvider).asData?.value;
      if (detail == null || shop == null) {
        throw Exception('Receipt is not available yet.');
      }
      final bytes = await buildReceiptPdf(detail, shop);
      await Printing.sharePdf(bytes: bytes, filename: 'receipt-$saleId.pdf');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Share failed: $error')));
      }
    }
  }

  Future<void> _showReceiptSheet(LocalSaleCommit commit) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = AppColors.of(sheetContext);
        var printing = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> printReceipt() async {
              if (printing) return;
              // Capture the messenger before any async gap so we can show a
              // confirmation after the sheet is popped without touching a
              // possibly-unmounted BuildContext.
              final messenger = ScaffoldMessenger.of(context);
              setSheetState(() => printing = true);
              try {
                final detail = await ref
                    .read(salesRepositoryProvider)
                    .getSaleDetail(commit.saleId);
                final shop = ref.read(shopInfoProvider).asData?.value;
                if (detail == null || shop == null) {
                  throw Exception('Receipt detail is not available yet.');
                }
                final printer = ref.read(receiptPrinterProvider);
                final devices = await printer.getDevices();
                if (devices.isEmpty) {
                  if (sheetContext.mounted) {
                    setSheetState(() => printing = false);
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text('No paired Bluetooth printer found.'),
                      ),
                    );
                  }
                  return;
                }
                await printer.connect(devices.first);
                await printer.printTaxInvoice(detail, shop);
                await printer.disconnect();
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
                messenger.showSnackBar(
                  const SnackBar(content: Text('Receipt printed.')),
                );
              } catch (error) {
                if (sheetContext.mounted) {
                  setSheetState(() => printing = false);
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(content: Text('Print failed: $error')),
                  );
                }
              }
            }

            return Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppPalette.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: AppPalette.success,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sale complete',
                      style: Theme.of(sheetContext).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatCurrency(commit.total),
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppPalette.primary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    // Bluetooth printing is Android-only: iOS does not expose
                    // Bluetooth Classic SPP to apps. Offering a button that can
                    // only fail is worse than not offering it, and the Share /
                    // PDF action below works on both platforms.
                    if (ReceiptPrinterService.supportsBluetoothPrinting)
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: printing ? null : printReceipt,
                          icon: printing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.print_rounded),
                          label: Text(
                            printing ? 'Printing...' : 'Print receipt',
                          ),
                        ),
                      ),
                    if (ReceiptPrinterService.supportsBluetoothPrinting)
                      const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: () => _shareReceipt(commit.saleId),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share / WhatsApp'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Done'),
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

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final categories =
        ref.watch(inventoryCategoriesProvider).asData?.value ??
        const <InventoryCategorySummary>[];

    final catalogFilter = PosCatalogFilter(
      search: _search,
      category: _selectedCategory,
      page: 1,
      pageSize: _pageSize,
      includeCost: session?.canViewCost ?? false,
    );
    final items =
        ref.watch(posCatalogPageProvider(catalogFilter)).asData?.value ??
        const <InventoryCatalogItem>[];

    final allEntries = items.isEmpty ? const [] : groupCatalog(items);
    final entries = allEntries.take(100).toList(growable: false);

    final mainContent = CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _buildHeader(context, items)),
        if (categories.isNotEmpty)
          SliverToBoxAdapter(child: _buildCategoryFilters(categories)),
        SliverToBoxAdapter(child: _buildFavouritesStrip()),
        SliverToBoxAdapter(child: _buildQuickWeighGrid(items)),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyCatalog(searching: _search.isNotEmpty),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              AdaptiveLayout.isPhone(context) && _cart.isEmpty ? 24 : 108,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.60,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry is VariantGroup) {
                  return _VariantGroupCard(
                    group: entry,
                    qtyInCart: entry.variants.fold<double>(
                      0,
                      (sum, v) => sum + _qtyInCart(v.id),
                    ),
                    onTap: () => _openVariantPicker(entry),
                  );
                }
                final item = entry as InventoryCatalogItem;
                return _ProductCard(
                  item: item,
                  qtyInCart: _qtyInCart(item.id),
                  onAdd: () => _addToCart(item),
                  onInc: () => _changeQtyById(item.id, 1),
                  onDec: () => _changeQtyById(item.id, -1),
                  onLongPress: () => _toggleFavourite(item),
                );
              },
            ),
          ),
      ],
    );

    Widget cartPane() => _CartSheet(
      cart: _cart,
      inline: true,
      onChangeQty: _changeQtyById,
      onSetQty: _setLineQuantity,
      onSetLineDiscount: _setLineDiscount,
      gstSummary: () => _gstSummary,
      grossTotal: () => _cartTotal,
      discountAmount: () => _discountAmount,
      netTotal: () => _netTotal,
      discountController: _discountController,
      isPercent: () => _discountIsPercent,
      onToggleType: () =>
          setState(() => _discountIsPercent = !_discountIsPercent),
      customerNameController: _customerNameController,
      customerPhoneController: _customerPhoneController,
      saleDate: () => _saleDate,
      onCheckout: () => _openCheckout(),
      onPickDate: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _saleDate ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null && mounted) {
          setState(() => _saleDate = picked);
        }
      },
      onPickCustomer: _pickCustomer,
    );

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: AdaptiveLayout(
          phone: (_) => mainContent,
          tablet: (_) => Row(
            children: <Widget>[
              Expanded(flex: 6, child: mainContent),
              VerticalDivider(width: 1, color: colors.border),
              Expanded(flex: 4, child: cartPane()),
            ],
          ),
          desktop: (_) => Row(
            children: <Widget>[
              Expanded(flex: 7, child: mainContent),
              VerticalDivider(width: 1, color: colors.border),
              Expanded(flex: 4, child: cartPane()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AdaptiveLayout.isPhone(context) && _cart.isNotEmpty
          ? _CartBar(
              count: _cartCount,
              total: _cartTotal,
              saving: _saving,
              onTap: _openCart,
            )
          : null,
    );
  }

  Widget _buildHeader(BuildContext context, List<InventoryCatalogItem> items) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Point of Sale',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              if (ref.watch(heldSalesProvider).isNotEmpty)
                TextButton.icon(
                  onPressed: _showHeldSales,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text('Held ${ref.watch(heldSalesProvider).length}'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              if (_cart.isNotEmpty)
                IconButton(
                  onPressed: _holdCurrentSale,
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                  tooltip: 'Hold sale',
                ),
              if (_cart.isNotEmpty)
                IconButton(
                  onPressed: () => _showUpiQr(_netTotal),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  tooltip: 'Collect via UPI QR',
                ),
              TextButton.icon(
                onPressed: _addCustomItem,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text(L.of(context).posCustomItem),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              TextButton.icon(
                onPressed: _addWeighedItem,
                icon: const Icon(Icons.scale_rounded, size: 18),
                label: const Text('Weigh'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  // A hardware (keyboard-wedge) barcode scanner types the code
                  // then sends Enter — if it narrows to one item, add it.
                  onSubmitted: (value) {
                    if (items.length == 1) {
                      _addToCart(items.first);
                      _searchController.clear();
                      setState(() => _search = '');
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by name, SKU or barcode',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          ),
                    filled: true,
                    fillColor: colors.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ScanButton(onTap: () => _openScanner(items)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavourite(InventoryCatalogItem item) async {
    await ref.read(favouriteIdsProvider.notifier).toggle(item.id);
    if (!mounted) return;
    final isFav = ref.read(favouriteIdsProvider.notifier).isFavourite(item.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isFav
              ? '${item.name} pinned to quick-keys.'
              : '${item.name} removed from quick-keys.',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Horizontal strip of favourite (quick-key) items above the catalog.
  /// Long-press any product to pin/unpin it here.
  Widget _buildFavouritesStrip() {
    final pinned =
        ref.watch(favouriteItemsProvider).asData?.value ??
        const <InventoryCatalogItem>[];
    // Fall back to what the shop actually sells most, so the quick-add row is
    // useful before anyone discovers the long-press-to-pin gesture.
    final favourites = pinned.isNotEmpty
        ? pinned
        : (ref.watch(autoTopSellersProvider).asData?.value ??
              const <InventoryCatalogItem>[]);
    if (favourites.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: favourites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = favourites[index];
          return ActionChip(
            avatar: const Icon(
              Icons.bolt_rounded,
              size: 16,
              color: AppPalette.primary,
            ),
            label: Text(
              '${item.name}  ${formatCurrency(item.price)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () => _addToCart(item),
          );
        },
      ),
    );
  }

  /// Weight/volume units that mark an item as sold loose (by weight).
  static const Set<String> _looseUnits = <String>{
    'kg',
    'kgs',
    'g',
    'gm',
    'gms',
    'gram',
    'grams',
    'kilogram',
    'kilograms',
    'l',
    'ltr',
    'litre',
    'liter',
    'ml',
  };

  bool _isLooseItem(InventoryCatalogItem item) {
    final unit = (item.unit ?? '').trim().toLowerCase();
    if (_looseUnits.contains(unit)) return true;
    return item.name.toLowerCase().contains('loose');
  }

  /// Quick-key grid: visual tap-to-add tiles for loose/by-weight items so the
  /// operator can skip the search bar during rapid checkouts. The tile set is
  /// driven by which catalog items are marked as loose (a weight unit or a
  /// "loose" name), so owners customise it by tagging items.
  Widget _buildQuickWeighGrid(List<InventoryCatalogItem> items) {
    final loose = items.where(_isLooseItem).take(8).toList();
    if (loose.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: const <Widget>[
              Icon(Icons.scale_rounded, size: 15, color: AppPalette.primary),
              SizedBox(width: 6),
              Text(
                'Quick weigh',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: loose.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = loose[index];
                return _QuickWeighTile(
                  item: item,
                  onTap: () => _tapQuickWeigh(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Merchant UPI ID for QR collection. Seeded from --dart-define
  /// BUSINESS_HUB_UPI_VPA, editable in the dialog, remembered for the session.
  static String _merchantVpa = const String.fromEnvironment(
    'BUSINESS_HUB_UPI_VPA',
  );

  /// Show a dynamic UPI QR for [amount] so the customer scans and pays the exact
  /// total — no "did you pay?" guesswork. Prompts for the merchant VPA if unset.
  Future<void> _showUpiQr(double amount) async {
    if (amount <= 0) return;
    final shop = ref.read(shopInfoProvider).asData?.value;
    final shopName = shop?.name ?? 'Merchant';
    // Prefer the UPI ID the owner saved in Business settings (synced to every
    // cashier); fall back to the build-time default / last session value.
    final savedVpa = shop?.upiVpa.trim() ?? '';
    if (savedVpa.isNotEmpty) {
      _merchantVpa = savedVpa;
    }
    final vpaController = TextEditingController(text: _merchantVpa);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            String? uri;
            String? error;
            try {
              if (_merchantVpa.trim().isNotEmpty) {
                uri = buildUpiUri(
                  payeeVpa: _merchantVpa,
                  payeeName: shopName,
                  amount: amount,
                  note: 'Bill $shopName',
                );
              }
            } on UpiRequestError catch (e) {
              error = e.message;
            }
            return AlertDialog(
              title: Text('Collect ${formatCurrency(amount)}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (uri != null) ...<Widget>[
                    UpiQrView(data: uri),
                    const SizedBox(height: 8),
                    Text(
                      _merchantVpa,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Scan with any UPI app',
                      style: TextStyle(fontSize: 12),
                    ),
                  ] else ...<Widget>[
                    const Text('Enter your UPI ID to generate the QR.'),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          error,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    textCapitalization: TextCapitalization.sentences,
                    controller: vpaController,
                    decoration: const InputDecoration(
                      labelText: 'Merchant UPI ID',
                      hintText: 'name@bank',
                    ),
                    onChanged: (v) =>
                        setDialogState(() => _merchantVpa = v.trim()),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _tapQuickWeigh(InventoryCatalogItem item) async {
    final weight = await _promptWeight(item);
    if (weight == null || weight <= 0 || !mounted) return;
    _addLooseItem(item, weight);
  }

  /// Ask for a weight (kg) with quick presets; returns null on cancel.
  Future<double?> _promptWeight(InventoryCatalogItem item) {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (dialogContext) {
        double? parse() => double.tryParse(controller.text.trim());
        void submit(double value) => Navigator.pop(dialogContext, value);
        return AlertDialog(
          title: Text('Weigh ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${formatCurrency(item.price)} / ${(item.unit ?? 'kg')}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Weight',
                  hintText: 'e.g. 1.5',
                  suffixText: 'kg',
                ),
                onSubmitted: (_) {
                  final v = parse();
                  if (v != null && v > 0) submit(v);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: <double>[0.25, 0.5, 1, 2]
                    .map(
                      (w) => ActionChip(
                        label: Text('${formatQty(w)} kg'),
                        onPressed: () => submit(w),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = parse();
                if (v != null && v > 0) submit(v);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  /// Add (or top up) a loose line priced rate x weight. Uses the item's real id
  /// so stock still decrements on sale; quantity is the fractional weight.
  void _addLooseItem(InventoryCatalogItem item, double weight) {
    setState(() {
      final index = _cart.indexWhere((c) => c.id == item.id);
      if (index >= 0) {
        _cart[index] = _cart[index].copyWith(
          quantity: _cart[index].quantity + weight,
        );
      } else {
        _cart.add(
          PosCartItem(
            id: item.id,
            name: item.name,
            price: item.price,
            quantity: weight,
            stock: item.stock,
            category: item.category,
            size: item.size,
            sku: item.sku,
            costPrice: item.costPrice,
            hsnCode: item.hsnCode,
            gstRate: item.gstRate,
            priceIncludesTax: item.priceIncludesTax,
          ),
        );
      }
    });
    HapticFeedback.selectionClick();
  }

  Widget _buildCategoryFilters(List<InventoryCategorySummary> categories) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CategoryChip(
              label: 'All',
              selected: _selectedCategory == null,
              onTap: () => setState(() => _selectedCategory = null),
            );
          }
          final category = categories[index - 1].category;
          return _CategoryChip(
            label: category,
            selected: _selectedCategory == category,
            onTap: () => setState(() => _selectedCategory = category),
          );
        },
      ),
    );
  }
}

// ---- product row ------------------------------------------------------------

/// Premium product card for the 2-column POS grid: photo on top (or a gradient
/// initial), then name, category, price and a full-width add / quantity control.
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.qtyInCart,
    required this.onAdd,
    required this.onInc,
    required this.onDec,
    this.onLongPress,
  });

  final InventoryCatalogItem item;
  final double qtyInCart;
  final VoidCallback onAdd;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final selected = qtyInCart > 0;
    final category = item.category.trim();

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppPalette.primary.withValues(alpha: 0.6)
                : colors.borderSoft,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _CardImage(name: item.name, imagePath: item.imagePath),
                  if (item.isLowStock)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: _MiniBadge(
                        label: 'Low',
                        color: AppPalette.warning,
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _MiniBadge(
                        label: '×${formatQuantity(qtyInCart)}',
                        color: AppPalette.primary,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.isNotEmpty
                        ? category
                        : '${formatQuantity(item.stock)} in stock',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatCurrency(item.price),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppPalette.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  selected
                      ? _CardStepper(
                          quantity: qtyInCart,
                          onInc: onInc,
                          onDec: onDec,
                        )
                      : _CardAddButton(onTap: onAdd),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Variant-group card (same shape as [_ProductCard]) — tapping opens the
/// variant picker instead of adding directly.
class _VariantGroupCard extends StatelessWidget {
  const _VariantGroupCard({
    required this.group,
    required this.qtyInCart,
    required this.onTap,
  });

  final VariantGroup group;
  final double qtyInCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final selected = qtyInCart > 0;
    final firstImage = group.variants
        .map((v) => v.imagePath)
        .firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? AppPalette.primary.withValues(alpha: 0.6)
              : colors.borderSoft,
          width: selected ? 1.5 : 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _CardImage(name: group.baseName, imagePath: firstImage),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _MiniBadge(
                    label: '${group.variants.length} options',
                    color: AppPalette.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.baseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatQuantity(group.totalStock)} in stock',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'from ${formatCurrency(group.minPrice)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppPalette.primary,
                  ),
                ),
                const SizedBox(height: 8),
                _CardAddButton(
                  onTap: onTap,
                  label: 'Choose',
                  icon: Icons.tune_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width product image for a grid card, or a gradient initial fallback.
class _CardImage extends StatelessWidget {
  const _CardImage({required this.name, this.imagePath});

  final String name;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppPalette.primary.withValues(alpha: 0.16),
            AppPalette.primary.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: AppPalette.primary,
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

/// Full-width "Add" (or custom-labelled) button used at the foot of a card.
class _CardAddButton extends StatelessWidget {
  const _CardAddButton({
    required this.onTap,
    this.label = 'Add',
    this.icon = Icons.add_rounded,
  });

  final VoidCallback onTap;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 38,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width − / qty / + control used at the foot of a card when in cart.
class _CardStepper extends StatelessWidget {
  const _CardStepper({
    required this.quantity,
    required this.onInc,
    required this.onDec,
  });

  final double quantity;
  final VoidCallback onInc;
  final VoidCallback onDec;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppPalette.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: onDec,
              child: const Icon(
                Icons.remove_rounded,
                size: 20,
                color: AppPalette.primary,
              ),
            ),
          ),
          Text(
            formatQuantity(quantity),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppPalette.primary,
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onInc,
              child: const Icon(
                Icons.add_rounded,
                size: 20,
                color: AppPalette.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.name});

  final String name;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    return _letterTile();
  }

  Widget _letterTile() {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppPalette.primary.withValues(alpha: 0.18),
            AppPalette.primary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppPalette.primary,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.primary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const SizedBox(
          width: 46,
          height: 46,
          child: Icon(Icons.add_rounded, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

/// Show a quantity without a trailing ".0" (e.g. 2, not 2.0; 1.5 stays 1.5).
class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.primary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: const SizedBox(
          width: 54,
          height: 54,
          child: Icon(
            Icons.qr_code_scanner_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: selected ? AppPalette.primary : colors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? AppPalette.primary : colors.borderSoft,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A visual tap-to-add tile for a loose / by-weight item in the quick-key grid.
class _QuickWeighTile extends StatelessWidget {
  const _QuickWeighTile({required this.item, required this.onTap});

  final InventoryCatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 132,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderSoft),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatCurrency(item.price)} / ${(item.unit ?? 'kg')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- docked cart bar --------------------------------------------------------

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.count,
    required this.total,
    required this.saving,
    required this.onTap,
  });

  final int count;
  final double total;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: AppPalette.primary,
        borderRadius: BorderRadius.circular(20),
        elevation: 8,
        shadowColor: AppPalette.primary.withValues(alpha: 0.4),
        child: InkWell(
          onTap: saving ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$count item${count == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                if (saving)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                else ...<Widget>[
                  Text(
                    formatCurrency(total),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- order summary sheet ----------------------------------------------------

class _CartSheet extends StatefulWidget {
  const _CartSheet({
    required this.cart,
    required this.onChangeQty,
    required this.onSetQty,
    required this.onSetLineDiscount,
    required this.gstSummary,
    required this.grossTotal,
    required this.discountAmount,
    required this.netTotal,
    required this.discountController,
    required this.isPercent,
    required this.onToggleType,
    required this.customerNameController,
    required this.customerPhoneController,
    required this.saleDate,
    required this.onPickDate,
    required this.onPickCustomer,
    this.onCheckout,
    this.inline = false,
  });

  final VoidCallback? onCheckout;
  final bool inline;

  final List<PosCartItem> cart;
  final void Function(String id, int delta) onChangeQty;
  final void Function(String id, double qty) onSetQty;
  final void Function(String id, double discount) onSetLineDiscount;
  final GstCartSummary Function() gstSummary;
  final double Function() grossTotal;
  final double Function() discountAmount;
  final double Function() netTotal;
  final TextEditingController discountController;
  final bool Function() isPercent;
  final VoidCallback onToggleType;
  final TextEditingController customerNameController;
  final TextEditingController customerPhoneController;
  final DateTime? Function() saleDate;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickCustomer;

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  /// Ask for an exact quantity (supports decimals, e.g. 1.5 kg).
  Future<double?> _promptQuantity(
    BuildContext context,
    PosCartItem line,
  ) async {
    final controller = TextEditingController(
      text: formatQuantity(line.quantity),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Quantity · ${line.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Quantity',
            hintText: 'e.g. 1.5',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim()),
            ),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<double?> _promptLineDiscount(
    BuildContext context,
    PosCartItem line,
  ) async {
    final controller = TextEditingController(
      text: line.effectiveDiscount > 0
          ? line.effectiveDiscount.toStringAsFixed(2)
          : '',
    );
    // Cashiers think in both "Rs.50 off" and "10% off", so support each and
    // resolve the percent to rupees against this line's gross before applying.
    var isPercent = false;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final entered = double.tryParse(controller.text.trim()) ?? 0;
          final resolved = isPercent
              ? line.grossLineTotal * (entered.clamp(0, 100) / 100)
              : entered;
          final capped = resolved > line.grossLineTotal
              ? line.grossLineTotal
              : resolved;
          return AlertDialog(
            title: Text('Discount / ${line.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Line total ${formatCurrency(line.grossLineTotal)}'),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(value: false, label: Text('₹')),
                    ButtonSegment<bool>(value: true, label: Text('%')),
                  ],
                  selected: <bool>{isPercent},
                  onSelectionChanged: (selection) =>
                      setDialogState(() => isPercent = selection.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: isPercent
                        ? 'Discount %'
                        : 'Discount on this item',
                    prefixText: isPercent ? null : '₹ ',
                    suffixText: isPercent ? '%' : null,
                    hintText: isPercent ? 'e.g. 10' : 'e.g. 50',
                  ),
                ),
                if (capped > 0) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '-${formatCurrency(capped)}  ->  pays '
                    '${formatCurrency(line.grossLineTotal - capped)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 0.0),
                child: const Text('Clear'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, capped),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final gst = widget.gstSummary();

    Widget buildContent(ScrollController? scrollController) {
      return Container(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: widget.inline
              ? BorderRadius.zero
              : const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: <Widget>[
            if (!widget.inline) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    'Order summary',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.cart.length} line${widget.cart.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.cart.isEmpty
                  ? Center(
                      child: Text(
                        'Cart is empty',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    )
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: <Widget>[
                        for (final line in widget.cart) ...<Widget>[
                          _CartLine(
                            line: line,
                            onInc: () {
                              widget.onChangeQty(line.id, 1);
                              setState(() {});
                            },
                            onDec: () {
                              widget.onChangeQty(line.id, -1);
                              setState(() {});
                            },
                            onEditQty: () async {
                              final qty = await _promptQuantity(context, line);
                              if (qty != null) {
                                widget.onSetQty(line.id, qty);
                                setState(() {});
                              }
                            },
                            onEditDiscount: () async {
                              final value = await _promptLineDiscount(
                                context,
                                line,
                              );
                              if (value != null) {
                                widget.onSetLineDiscount(line.id, value);
                                setState(() {});
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                        ],
                        _DiscountCard(
                          controller: widget.discountController,
                          isPercent: widget.isPercent(),
                          onToggle: () {
                            widget.onToggleType();
                            setState(() {});
                          },
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        _CustomerCard(
                          nameController: widget.customerNameController,
                          phoneController: widget.customerPhoneController,
                          onPick: () async {
                            await widget.onPickCustomer();
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 10),
                        _DateCard(
                          date: widget.saleDate(),
                          onTap: () async {
                            await widget.onPickDate();
                            if (context.mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
            ),
            _CartFooter(
              gst: gst,
              discount: widget.discountAmount(),
              total: widget.netTotal(),
              onPay: widget.cart.isEmpty
                  ? null
                  : () {
                      if (widget.inline) {
                        if (widget.onCheckout != null) widget.onCheckout!();
                      } else {
                        Navigator.of(context).pop('checkout');
                      }
                    },
            ),
          ],
        ),
      );
    }

    if (widget.inline) return buildContent(null);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => buildContent(scrollController),
    );
  }
}

class _DiscountCard extends StatelessWidget {
  const _DiscountCard({
    required this.controller,
    required this.isPercent,
    required this.onToggle,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isPercent;
  final VoidCallback onToggle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSoft),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Icon(Icons.local_offer_rounded, size: 20, color: colors.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Discount',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _MiniToggle(
            leftLabel: '₹',
            rightLabel: '%',
            rightSelected: isPercent,
            onTap: onToggle,
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.leftLabel,
    required this.rightLabel,
    required this.rightSelected,
    required this.onTap,
  });

  final String leftLabel;
  final String rightLabel;
  final bool rightSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: <Widget>[
            _MiniToggleChip(label: leftLabel, selected: !rightSelected),
            _MiniToggleChip(label: rightLabel, selected: rightSelected),
          ],
        ),
      ),
    );
  }
}

class _MiniToggleChip extends StatelessWidget {
  const _MiniToggleChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppPalette.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: selected ? Colors.white : AppPalette.primary,
        ),
      ),
    );
  }
}

class _DateCard extends StatelessWidget {
  const _DateCard({required this.date, required this.onTap});

  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.borderSoft),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.event_rounded, size: 20, color: colors.textTertiary),
              const SizedBox(width: 12),
              Text(
                'Sale date',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              Text(
                date == null ? 'Today' : formatCompactDate(date!),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.edit_calendar_rounded,
                size: 18,
                color: AppPalette.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.nameController,
    required this.phoneController,
    required this.onPick,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final Future<void> Function() onPick;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSoft),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.person_rounded, size: 20, color: colors.textTertiary),
              const SizedBox(width: 8),
              Text(
                'Customer (optional)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.people_alt_rounded, size: 16),
                label: const Text('Choose'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Name',
              border: InputBorder.none,
            ),
          ),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Phone',
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.line,
    required this.onInc,
    required this.onDec,
    this.onEditQty,
    this.onEditDiscount,
  });

  final PosCartItem line;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback? onEditQty;
  final VoidCallback? onEditDiscount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSoft),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          _ProductTile(name: line.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatCurrency(line.price)} each',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    if (line.effectiveDiscount > 0) ...<Widget>[
                      Text(
                        formatCurrency(line.grossLineTotal),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      formatCurrency(line.lineTotal),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppPalette.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: onEditDiscount,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.local_offer_outlined,
                          size: 14,
                          color: line.effectiveDiscount > 0
                              ? AppPalette.success
                              : colors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          line.effectiveDiscount > 0
                              ? '-${formatCurrency(line.effectiveDiscount)} off'
                              : 'Add discount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: line.effectiveDiscount > 0
                                ? AppPalette.success
                                : colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          QuantityStepper(
            quantity: line.quantity,
            onIncrement: onInc,
            onDecrement: onDec,
            onTapQuantity: onEditQty,
          ),
        ],
      ),
    );
  }
}

class _CartFooter extends StatelessWidget {
  const _CartFooter({
    required this.gst,
    required this.discount,
    required this.total,
    required this.onPay,
  });

  final GstCartSummary gst;
  final double discount;
  final double total;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: colors.borderSoft)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SummaryRow(
            label: 'Subtotal',
            value: formatCurrency(gst.taxableAmount),
          ),
          if (gst.hasTax) ...<Widget>[
            const SizedBox(height: 6),
            _SummaryRow(label: 'Tax', value: formatCurrency(gst.taxAmount)),
          ],
          if (discount > 0) ...<Widget>[
            const SizedBox(height: 6),
            _SummaryRow(
              label: 'Discount',
              value: '- ${formatCurrency(discount)}',
              valueColor: AppPalette.success,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text(
                'Total',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                formatCurrency(total),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppPalette.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: onPay,
              icon: const Icon(Icons.point_of_sale_rounded),
              label: const Text(
                'Process payment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppPalette.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : Icons.inventory_2_rounded,
                size: 40,
                color: AppPalette.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              searching ? 'No products found' : 'No products yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'Try a different name, SKU or barcode.'
                  : 'Add products in Inventory to start selling.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
