import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

double _num(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

String _showQty(Object? value) {
  final n = _num(value);
  return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
}

final purchaseOrdersProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return const <String, dynamic>{};
    return ref
        .read(backendApiClientProvider)
        .fetchPurchaseOrders(user: session.user, shopId: session.shopId!);
  },
);

final orderSuppliersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final session = ref.watch(mobileSessionProvider).asData?.value;
      if (session == null || !session.hasShop) {
        return const <Map<String, dynamic>>[];
      }
      return ref
          .read(backendApiClientProvider)
          .fetchSuppliers(user: session.user, shopId: session.shopId!);
    });

final orderStockItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final session = ref.watch(mobileSessionProvider).asData?.value;
      if (session == null || !session.hasShop) {
        return const <Map<String, dynamic>>[];
      }
      return ref
          .read(backendApiClientProvider)
          .fetchInventoryItems(user: session.user, shopId: session.shopId!);
    });

/// What is on order, and booking in what actually turned up.
///
/// This belongs on the phone more than on the web: the person opening cartons
/// at the back door is the one who knows eight of the ten arrived.
class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() =>
      _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  bool _canOrder(MobileSession s) => s.isOwner || s.isAdmin || s.isManager;

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final async = ref.watch(purchaseOrdersProvider);
    final payload = async.asData?.value ?? const <String, dynamic>{};
    final orders = (payload['orders'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final open = (payload['open_count'] as num?)?.toInt() ?? 0;
    final overdue = (payload['overdue_count'] as num?)?.toInt() ?? 0;
    final canOrder = session != null && _canOrder(session);

    return MobileStandaloneScaffold(
      title: 'Purchase orders',
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(purchaseOrdersProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AppMetric(
                    label: 'On order',
                    value: Text('$open'),
                    icon: Icons.inventory_2_outlined,
                    tone: AppTone.info,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppMetric(
                    label: 'Overdue',
                    value: Text('$overdue'),
                    icon: Icons.schedule_rounded,
                    tone: overdue > 0 ? AppTone.danger : AppTone.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (canOrder)
              FilledButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _OrderComposerSheet(),
                ).then((_) => ref.invalidate(purchaseOrdersProvider)),
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: const Text('New purchase order'),
              ),
            const SizedBox(height: 16),

            if (async.isLoading && orders.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (async.hasError)
              AppPanel(
                title: 'Could not load orders',
                child: Text(
                  'Check your connection and pull down to try again.',
                  style: TextStyle(color: colors.textSecondary),
                ),
              )
            else if (orders.isEmpty)
              const AppPanel(
                title: 'Nothing on order',
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No purchase orders yet',
                  body:
                      'Raising an order changes no stock and owes the '
                      'supplier nothing. Both happen when you book in the '
                      'delivery.',
                ),
              )
            else
              ...orders.map(
                (order) => _OrderCard(
                  order: order,
                  canOrder: canOrder,
                  onReceive: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => _ReceiveSheet(order: order),
                  ).then((_) => ref.invalidate(purchaseOrdersProvider)),
                  onCancel: () async {
                    final s = ref.read(mobileSessionProvider).asData?.value;
                    if (s == null || !s.hasShop) return;
                    try {
                      await ref
                          .read(backendApiClientProvider)
                          .cancelPurchaseOrder(
                            user: s.user,
                            shopId: s.shopId!,
                            orderId: (order['id'] ?? '').toString(),
                          );
                      ref.invalidate(purchaseOrdersProvider);
                    } on BackendApiException catch (error) {
                      if (mounted) _toast(error.message);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.canOrder,
    required this.onReceive,
    required this.onCancel,
  });

  final Map<String, dynamic> order;
  final bool canOrder;
  final VoidCallback onReceive;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final status = (order['status'] ?? '').toString();
    final receivable = status == 'ordered' || status == 'partially_received';
    final overdue = order['is_overdue'] == true;
    final lines = (order['lines'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    final (String label, AppTone accent) = switch (status) {
      'draft' => ('DRAFT', AppTone.neutral),
      'ordered' => ('ON ORDER', AppTone.primary),
      'partially_received' => ('PART RECEIVED', AppTone.warning),
      'received' => ('RECEIVED', AppTone.success),
      // Cancelled was the same blue as draft, so a killed order and an
      // unsent one read identically in the list.
      _ => ('CANCELLED', AppTone.danger),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppPanel(
        title: (order['reference'] ?? '').toString(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                AppTag(label: label, tone: accent),
                if (overdue)
                  const AppTag(label: 'OVERDUE', tone: AppTone.danger),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              (order['supplier_name'] ?? 'No supplier').toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
            if ((order['expected_date'] ?? '').toString().isNotEmpty)
              Text(
                'Expected ${order['expected_date']}',
                style: TextStyle(fontSize: 11, color: colors.textTertiary),
              ),
            const SizedBox(height: 10),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        (line['name'] ?? '').toString(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${_showQty(line['quantity_received'])} of '
                      '${_showQty(line['quantity_ordered'])}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (receivable && canOrder) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onReceive,
                      icon: const Icon(Icons.inventory_rounded, size: 18),
                      label: const Text('Book in'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Enter what actually arrived, line by line.
class _ReceiveSheet extends ConsumerStatefulWidget {
  const _ReceiveSheet({required this.order});

  final Map<String, dynamic> order;

  @override
  ConsumerState<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends ConsumerState<_ReceiveSheet> {
  final Map<String, TextEditingController> _entered =
      <String, TextEditingController>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _entered.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit(List<Map<String, dynamic>> lines) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return;

    final payload = <Map<String, dynamic>>[];
    for (final line in lines) {
      final id = (line['id'] ?? '').toString();
      final raw = _entered[id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final quantity = double.tryParse(raw);
      if (quantity == null || quantity <= 0) continue;
      final outstanding = _num(line['quantity_outstanding']);
      // Over-receiving is nearly always a typo, and it inflates both stock and
      // the bill. Stop it before the request.
      if (quantity > outstanding) {
        _toast(
          '${line['name']}: only ${_showQty(outstanding)} still outstanding.',
        );
        return;
      }
      payload.add(<String, dynamic>{'line_id': id, 'quantity': raw});
    }

    if (payload.isEmpty) {
      _toast('Enter how much of each item arrived.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(backendApiClientProvider)
          .receivePurchaseOrder(
            user: session.user,
            shopId: session.shopId!,
            orderId: (widget.order['id'] ?? '').toString(),
            lines: payload,
          );
      if (mounted) Navigator.of(context).pop();
    } on BackendApiException catch (error) {
      if (mounted) _toast(error.message);
    } catch (_) {
      if (mounted) _toast('Could not book in this delivery.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final lines = (widget.order['lines'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((line) => _num(line['quantity_outstanding']) > 0)
        .toList(growable: false);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: <Widget>[
          AppSheetHeader(
            title: 'Book in ${widget.order['reference']}',
            subtitle:
                'Enter what actually arrived. A short delivery is normal '
                '— the rest stays outstanding.',
            icon: Icons.inventory_rounded,
          ),
          const SizedBox(height: 16),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          (line['name'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${_showQty(line['quantity_outstanding'])} still to come',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: _entered.putIfAbsent(
                        (line['id'] ?? '').toString(),
                        TextEditingController.new,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: _showQty(line['quantity_outstanding']),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : () => _submit(lines),
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Booking in…' : 'Book in what arrived'),
          ),
        ],
      ),
    );
  }
}

/// Raise a new order against a supplier.
class _OrderComposerSheet extends ConsumerStatefulWidget {
  const _OrderComposerSheet();

  @override
  ConsumerState<_OrderComposerSheet> createState() =>
      _OrderComposerSheetState();
}

class _OrderComposerSheetState extends ConsumerState<_OrderComposerSheet> {
  String? _supplierId;
  DateTime? _expected;
  final Map<String, TextEditingController> _quantities =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _costs =
      <String, TextEditingController>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    for (final controller in _costs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit(List<Map<String, dynamic>> items) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return;

    final lines = <Map<String, dynamic>>[];
    for (final item in items) {
      final id = (item['id'] ?? '').toString();
      final raw = _quantities[id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final quantity = double.tryParse(raw);
      if (quantity == null || quantity <= 0) continue;
      lines.add(<String, dynamic>{
        'item_id': id,
        'quantity': raw,
        'unit_cost': _costs[id]?.text.trim().isNotEmpty == true
            ? _costs[id]!.text.trim()
            : '0',
      });
    }

    if (lines.isEmpty) {
      _toast('Enter how much of at least one item to order.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(backendApiClientProvider)
          .createPurchaseOrder(
            user: session.user,
            shopId: session.shopId!,
            lines: lines,
            supplierId: _supplierId,
            expectedDate: _expected?.toIso8601String().split('T').first,
          );
      if (mounted) Navigator.of(context).pop();
    } on BackendApiException catch (error) {
      if (mounted) _toast(error.message);
    } catch (_) {
      if (mounted) _toast('Could not place the order.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final suppliers =
        ref.watch(orderSuppliersProvider).asData?.value ??
        const <Map<String, dynamic>>[];
    final items =
        ref.watch(orderStockItemsProvider).asData?.value ??
        const <Map<String, dynamic>>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: <Widget>[
          const AppSheetHeader(
            title: 'New purchase order',
            subtitle:
                'This moves no stock and owes nothing until you book in '
                'the delivery.',
            icon: Icons.add_shopping_cart_outlined,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _supplierId,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: suppliers
                .map(
                  (s) => DropdownMenuItem<String>(
                    value: (s['id'] ?? '').toString(),
                    child: Text((s['name'] ?? '').toString()),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _supplierId = value),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: now.add(const Duration(days: 7)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _expected = picked);
            },
            icon: const Icon(Icons.event_outlined),
            label: Text(
              _expected == null
                  ? 'Expected by (optional)'
                  : 'Expected ${_expected!.toIso8601String().split('T').first}',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'What to order',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      (item['name'] ?? '').toString(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _quantities.putIfAbsent(
                        (item['id'] ?? '').toString(),
                        TextEditingController.new,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(hintText: 'Qty'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _costs.putIfAbsent(
                        (item['id'] ?? '').toString(),
                        TextEditingController.new,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(hintText: 'Cost'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : () => _submit(items),
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Placing…' : 'Place order'),
          ),
        ],
      ),
    );
  }
}
