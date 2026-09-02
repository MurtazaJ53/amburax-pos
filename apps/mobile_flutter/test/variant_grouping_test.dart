import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/features/pos/presentation/pos_catalog_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryCatalogItem _item(
  String id,
  String name, {
  double price = 100,
  double stock = 5,
  String? groupId,
  String? label,
}) {
  return InventoryCatalogItem(
    id: id,
    name: name,
    price: price,
    category: 'General',
    stock: stock,
    createdAt: DateTime(2026, 1, 1),
    variantGroupId: groupId,
    variantLabel: label,
  );
}

void main() {
  group('groupCatalog', () {
    test('plain items pass through unchanged', () {
      final entries = groupCatalog(<InventoryCatalogItem>[
        _item('1', 'Pen'),
        _item('2', 'Notebook'),
      ]);
      expect(entries.length, 2);
      expect(entries.every((e) => e is InventoryCatalogItem), isTrue);
    });

    test('sibling variants collapse into one group', () {
      final entries = groupCatalog(<InventoryCatalogItem>[
        _item(
          'a',
          'T-Shirt (S)',
          price: 499,
          stock: 12,
          groupId: 'g1',
          label: 'S',
        ),
        _item(
          'b',
          'T-Shirt (M)',
          price: 499,
          stock: 8,
          groupId: 'g1',
          label: 'M',
        ),
        _item(
          'c',
          'T-Shirt (L)',
          price: 549,
          stock: 3,
          groupId: 'g1',
          label: 'L',
        ),
      ]);
      expect(entries.length, 1);
      final grp = entries.single as VariantGroup;
      expect(grp.baseName, 'T-Shirt');
      expect(grp.variants.length, 3);
      expect(grp.minPrice, 499);
      expect(grp.totalStock, 23);
    });

    test('group keeps the position of its first variant, order preserved', () {
      final entries = groupCatalog(<InventoryCatalogItem>[
        _item('p', 'Apple'),
        _item('a', 'Shoe (7)', groupId: 'g2', label: '7'),
        _item('q', 'Banana'),
        _item('b', 'Shoe (8)', groupId: 'g2', label: '8'),
      ]);
      // Apple, Shoe-group (at first variant position), Banana
      expect(entries.length, 3);
      expect((entries[0] as InventoryCatalogItem).name, 'Apple');
      expect(entries[1], isA<VariantGroup>());
      expect((entries[1] as VariantGroup).variants.length, 2);
      expect((entries[2] as InventoryCatalogItem).name, 'Banana');
    });

    test('two different groups stay separate', () {
      final entries = groupCatalog(<InventoryCatalogItem>[
        _item('a', 'Cap (Red)', groupId: 'g1', label: 'Red'),
        _item('b', 'Mug (Blue)', groupId: 'g2', label: 'Blue'),
      ]);
      expect(entries.length, 2);
      expect(entries.every((e) => e is VariantGroup), isTrue);
    });
  });

  group('variantBaseName', () {
    test('strips the trailing variant label', () {
      final item = _item(
        'a',
        'T-Shirt (S / Red)',
        groupId: 'g',
        label: 'S / Red',
      );
      expect(variantBaseName(item), 'T-Shirt');
    });

    test('returns the full name when no label suffix matches', () {
      final item = _item('a', 'Plain Item', groupId: 'g', label: 'X');
      expect(variantBaseName(item), 'Plain Item');
    });
  });
}
