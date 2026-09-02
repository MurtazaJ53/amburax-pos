import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryCatalogItem _item({required double stock, int? reorderLevel}) {
  return InventoryCatalogItem(
    id: 'i1',
    name: 'Widget',
    price: 100,
    category: 'General',
    stock: stock,
    createdAt: DateTime(2026, 1, 1),
    reorderLevel: reorderLevel,
  );
}

void main() {
  group('InventoryCatalogItem reorder / low-stock', () {
    test('falls back to the default threshold when none is set', () {
      final item = _item(stock: 5);
      expect(
        item.effectiveReorderLevel,
        InventoryCatalogItem.defaultReorderLevel,
      );
      expect(item.isLowStock, isTrue); // 5 <= 5
    });

    test('above the default threshold is not low', () {
      expect(_item(stock: 6).isLowStock, isFalse);
    });

    test('honours a custom per-item reorder level', () {
      final item = _item(stock: 12, reorderLevel: 20);
      expect(item.effectiveReorderLevel, 20);
      expect(item.isLowStock, isTrue); // 12 <= 20
    });

    test('custom level below stock is not low', () {
      expect(_item(stock: 30, reorderLevel: 20).isLowStock, isFalse);
    });

    test('a zero reorder level only flags when out of stock', () {
      expect(_item(stock: 0, reorderLevel: 0).isLowStock, isTrue);
      expect(_item(stock: 1, reorderLevel: 0).isLowStock, isFalse);
    });
  });
}
