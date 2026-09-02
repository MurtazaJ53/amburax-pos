import 'package:business_hub_mobile/features/inventory/presentation/stocktake_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picking the right item from a scan, and reading the server's payload.
///
/// A counter working a shelf does not look up between scans. A wrong pick
/// records a count against the wrong item, and the variance that produces is
/// indistinguishable from real shrinkage — so the selection rule is worth
/// pinning rather than trusting.
const _items = <CountableItem>[
  CountableItem(
    id: '1',
    name: 'Cotton Shirt',
    sku: 'SH-01',
    barcode: '8901234567890',
  ),
  CountableItem(
    id: '2',
    name: 'Cotton Trouser',
    sku: 'TR-01',
    barcode: '8901234567891',
  ),
  // A name that literally contains another item's barcode. Rare, but a shop
  // that puts codes in item names hits it, and it must not beat the scan.
  CountableItem(
    id: '3',
    name: 'Bundle 8901234567890',
    sku: 'BN-01',
    barcode: '8909999999999',
  ),
];

void main() {
  group('searchCountable', () {
    test('matches name, sku or barcode, case-insensitively', () {
      expect(searchCountable(_items, 'cotton').map((i) => i.id), <String>[
        '1',
        '2',
      ]);
      expect(searchCountable(_items, 'tr-01').map((i) => i.id), <String>['2']);
      expect(
        searchCountable(_items, '8901234567891').map((i) => i.id),
        <String>['2'],
      );
    });

    test('a blank query matches nothing', () {
      // Otherwise clearing the field dumps a slice of the whole catalogue
      // under the search box.
      expect(searchCountable(_items, ''), isEmpty);
      expect(searchCountable(_items, '   '), isEmpty);
    });

    test('caps how many suggestions come back', () {
      final many = <CountableItem>[
        for (var n = 0; n < 30; n++)
          CountableItem(id: '$n', name: 'Cotton $n', sku: '', barcode: ''),
      ];
      expect(searchCountable(many, 'cotton'), hasLength(8));
    });
  });

  group('resolveCountScan', () {
    test('an exact barcode beats another item whose name contains it', () {
      // Two items match the substring search, so without the exact-barcode
      // rule the scan would be ambiguous and do nothing.
      expect(searchCountable(_items, '8901234567890'), hasLength(2));
      expect(resolveCountScan(_items, '8901234567890')?.id, '1');
    });

    test('an exact SKU is taken', () {
      expect(resolveCountScan(_items, 'TR-01')?.id, '2');
    });

    test('a single fuzzy match is taken', () {
      expect(resolveCountScan(_items, 'trouser')?.id, '2');
    });

    test('several matches select nothing rather than guess', () {
      expect(resolveCountScan(_items, 'cotton'), isNull);
    });

    test('no match, or a blank query, selects nothing', () {
      expect(resolveCountScan(_items, 'saree'), isNull);
      expect(resolveCountScan(_items, '  '), isNull);
    });
  });

  group('openStocktake', () {
    test('finds the open count among finished ones', () {
      final all = <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a', 'status': 'applied'},
        <String, dynamic>{'id': 'b', 'status': 'open'},
        <String, dynamic>{'id': 'c', 'status': 'cancelled'},
      ];
      expect(openStocktake(all)?['id'], 'b');
    });

    test('returns null when every count is finished', () {
      // The screen shows the start card in this case. Treating a cancelled
      // count as open would offer counting into a stocktake that can never
      // be applied.
      final all = <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a', 'status': 'cancelled'},
      ];
      expect(openStocktake(all), isNull);
    });
  });

  group('parseQuantity', () {
    test('reads the JSON strings DRF sends for decimals', () {
      expect(parseQuantity('12.000'), 12.0);
      expect(parseQuantity('-2.500'), -2.5);
      expect(parseQuantity(null), 0);
    });

    test('showCount drops the trailing zeros on whole numbers', () {
      expect(showCount(parseQuantity('12.000')), '12');
      expect(showCount(parseQuantity('2.500')), '2.5');
    });
  });
}
