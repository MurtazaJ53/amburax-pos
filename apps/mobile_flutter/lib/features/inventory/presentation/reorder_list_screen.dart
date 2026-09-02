import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/whatsapp.dart';
import '../../../core/utils/formatters.dart';
import '../../../ui/ui.dart';

final reorderListProvider = StreamProvider.autoDispose<List<ReorderItem>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchReorderList(),
);

/// Build the purchase message a shopkeeper sends their supplier. Plain text on
/// purpose — it has to be readable in a WhatsApp bubble, not a spreadsheet.
String buildReorderMessage({
  required String shopName,
  required List<ReorderItem> items,
}) {
  final shop = shopName.trim().isEmpty ? 'our shop' : shopName.trim();
  if (items.isEmpty) return 'Nothing to reorder for $shop right now.';

  final buffer = StringBuffer()
    ..writeln('*$shop* - stock order')
    ..writeln();
  for (final item in items) {
    final unit = (item.unit ?? '').trim();
    final qty = formatQty(item.suggestedQty) + (unit.isEmpty ? '' : ' $unit');
    final sku = (item.sku ?? '').trim();
    buffer.writeln('- ${item.name}${sku.isEmpty ? '' : ' ($sku)'}: $qty');
  }
  buffer
    ..writeln()
    ..writeln('Please confirm availability and rate. Thank you.');
  return buffer.toString().trimRight();
}

/// The daily "what do I need to buy" list, and a one-tap order to the supplier.
class ReorderListScreen extends ConsumerStatefulWidget {
  const ReorderListScreen({super.key});

  @override
  ConsumerState<ReorderListScreen> createState() => _ReorderListScreenState();
}

class _ReorderListScreenState extends ConsumerState<ReorderListScreen> {
  final Set<String> _excluded = <String>{};
  final TextEditingController _supplierPhone = TextEditingController();

  @override
  void dispose() {
    _supplierPhone.dispose();
    super.dispose();
  }

  List<ReorderItem> _selected(List<ReorderItem> all) =>
      all.where((i) => !_excluded.contains(i.id)).toList();

  Future<void> _sendOrder(List<ReorderItem> items) async {
    final shop = ref.read(shopInfoProvider).asData?.value;
    final message = buildReorderMessage(
      shopName: shop?.name ?? '',
      items: items,
    );

    final phone = _supplierPhone.text.trim();
    if (phone.isEmpty) {
      // No number typed: open WhatsApp's own contact picker via a share, rather
      // than forcing the shopkeeper to store supplier numbers in this app.
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Supplier number needed'),
          content: const Text(
            'Type the supplier\'s mobile number above, then tap Send order. '
            'We will open WhatsApp with the list ready.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final opened = await openWhatsApp(phone: phone, message: message);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp for that number.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final async = ref.watch(reorderListProvider);
    final all = async.asData?.value ?? const <ReorderItem>[];
    final selected = _selected(all);
    final outOfStock = all.where((i) => i.isOutOfStock).length;
    final estimated = selected
        .map((i) => i.estimatedCost)
        .whereType<double>()
        .fold<double>(0, (sum, c) => sum + c);

    return AppScreen(
      scrollable: false,
      title: L.of(context).reorderTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: (outOfStock > 0 ? AppPalette.error : AppPalette.warning)
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: (outOfStock > 0 ? AppPalette.error : AppPalette.warning)
                    .withValues(alpha: 0.30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${all.length} item(s) need restocking',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  outOfStock > 0
                      ? '$outOfStock already out of stock - you are losing '
                            'sales on these today.'
                      : 'All still in stock, but running low.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                if (estimated > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'Estimated cost: ${formatCurrency(estimated)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (all.isNotEmpty) ...<Widget>[
            TextField(
              controller: _supplierPhone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: L.of(context).reorderSupplierPhone,
                prefixIcon: const Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: selected.isEmpty ? null : () => _sendOrder(selected),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.send_rounded),
              label: Text('Send order (${selected.length} items)'),
            ),
            const SizedBox(height: 16),
          ],
          if (async.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (all.isEmpty)
            const AppPanel(
              title: 'Stock is healthy',
              child: AppEmptyState(
                icon: Icons.check_circle_rounded,
                title: 'Nothing needs reordering',
                body:
                    'Items appear here automatically once they drop to their '
                    'reorder level. Set that level when editing an item.',
              ),
            )
          else
            for (final item in all)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReorderTile(
                  item: item,
                  included: !_excluded.contains(item.id),
                  onToggle: () => setState(() {
                    if (!_excluded.remove(item.id)) _excluded.add(item.id);
                  }),
                ),
              ),
        ],
      ),
    );
  }
}

class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    required this.item,
    required this.included,
    required this.onToggle,
  });

  final ReorderItem item;
  final bool included;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final unit = (item.unit ?? '').trim();
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: included ? colors.borderSoft : colors.border,
            ),
          ),
          child: Row(
            children: <Widget>[
              Checkbox(value: included, onChanged: (_) => onToggle()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: included ? null : colors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (item.isOutOfStock
                                        ? AppPalette.error
                                        : AppPalette.warning)
                                    .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.isOutOfStock
                                ? 'OUT OF STOCK'
                                : 'Left ${formatQty(item.stock)}'
                                      '${unit.isEmpty ? '' : ' $unit'}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: item.isOutOfStock
                                  ? AppPalette.error
                                  : AppPalette.warning,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Order ${formatQty(item.suggestedQty)}'
                          '${unit.isEmpty ? '' : ' $unit'}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
