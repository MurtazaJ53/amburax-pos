import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/features/inventory/presentation/reorder_list_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reorder quantities turn into real money spent with a supplier, so a wrong
/// suggestion either wastes cash or leaves the shop out of stock again.
ReorderItem _item({
  String name = 'Woolen Caps Kids',
  double stock = 2,
  int reorderLevel = 10,
  String? unit,
  String? sku,
  double? costPrice,
}) => ReorderItem(
  id: 'i1',
  name: name,
  category: 'Winter',
  stock: stock,
  reorderLevel: reorderLevel,
  unit: unit,
  sku: sku,
  costPrice: costPrice,
);

void main() {
  group('suggested quantity', () {
    test('buys up to twice the reorder level so it does not run low again', () {
      // Level 10, 2 left -> target 20 -> order 18.
      expect(_item(stock: 2, reorderLevel: 10).suggestedQty, 18);
    });

    test('an out-of-stock item orders the full target', () {
      expect(_item(stock: 0, reorderLevel: 10).suggestedQty, 20);
    });

    test('never suggests less than one unit', () {
      // Sitting exactly at twice the level would otherwise suggest zero.
      expect(_item(stock: 20, reorderLevel: 10).suggestedQty, 1);
      expect(_item(stock: 999, reorderLevel: 1).suggestedQty, 1);
    });

    test('rounds a fractional gap up, never down', () {
      // Weighed goods: 1.5kg left, level 3 -> target 6 -> gap 4.5 -> 5.
      expect(_item(stock: 1.5, reorderLevel: 3).suggestedQty, 5);
    });

    test('negative stock (oversold) is handled', () {
      expect(_item(stock: -3, reorderLevel: 5).suggestedQty, 13);
    });
  });

  group('out of stock flag', () {
    test('zero or below is out of stock', () {
      expect(_item(stock: 0).isOutOfStock, isTrue);
      expect(_item(stock: -1).isOutOfStock, isTrue);
      expect(_item(stock: 0.5).isOutOfStock, isFalse);
    });
  });

  group('estimated cost', () {
    test('multiplies the suggested quantity by cost price', () {
      final item = _item(stock: 2, reorderLevel: 10, costPrice: 50);
      expect(item.suggestedQty, 18);
      expect(item.estimatedCost, 900);
    });

    test('is null when no cost price is known, not zero', () {
      // Zero would silently understate a purchase budget.
      expect(_item().estimatedCost, isNull);
    });
  });

  group('supplier message', () {
    test('lists every item with quantity and unit', () {
      final message = buildReorderMessage(
        shopName: 'T. N',
        items: <ReorderItem>[
          _item(name: 'Woolen Caps', stock: 2, reorderLevel: 10, unit: 'pcs'),
          _item(name: 'Rice', stock: 1, reorderLevel: 5, unit: 'kg'),
        ],
      );
      expect(message, contains('T. N'));
      expect(message, contains('Woolen Caps'));
      expect(message, contains('18 pcs'));
      expect(message, contains('Rice'));
      expect(message, contains('9 kg'));
    });

    test('includes the SKU so the supplier picks the right variant', () {
      final message = buildReorderMessage(
        shopName: 'T. N',
        items: <ReorderItem>[_item(name: 'Cap', sku: 'CAP-100')],
      );
      expect(message, contains('CAP-100'));
    });

    test('omits empty SKU rather than printing brackets', () {
      final message = buildReorderMessage(
        shopName: 'T. N',
        items: <ReorderItem>[_item(name: 'Cap', sku: '')],
      );
      expect(message, isNot(contains('()')));
    });

    test('an empty list does not produce a blank order', () {
      final message = buildReorderMessage(
        shopName: 'T. N',
        items: <ReorderItem>[],
      );
      expect(message, contains('Nothing to reorder'));
    });

    test('an unnamed shop still reads sensibly', () {
      final message = buildReorderMessage(
        shopName: '  ',
        items: <ReorderItem>[_item()],
      );
      expect(message, contains('our shop'));
    });
  });
}
