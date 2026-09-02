import 'package:business_hub_mobile/core/health/data_health.dart';
import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wrongly merging two real products destroys stock data, so the matching
/// rules here have to be conservative and provable.
InventoryCatalogItem _item({
  required String id,
  String name = 'Woolen Caps Kids',
  String? sku,
  String? size,
  double stock = 10,
  double price = 80,
  int createdDaysAgo = 0,
}) => InventoryCatalogItem(
  id: id,
  name: name,
  price: price,
  sku: sku,
  category: 'Winter',
  size: size,
  gstRate: 0,
  priceIncludesTax: true,
  stock: stock,
  createdAt: DateTime.now().subtract(Duration(days: createdDaysAgo)),
);

BackendCustomerSummary _customer({
  String id = 'c1',
  String name = 'Ayaan',
  String? phone,
  double balance = 0,
}) => BackendCustomerSummary(
  id: id,
  name: name,
  phone: phone,
  email: null,
  notes: null,
  status: 'active',
  balance: balance,
  totalSpent: 0,
);

void main() {
  group('duplicate detection', () {
    test('matches on SKU', () {
      final groups = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: '1', sku: 'CAP-1'),
        _item(id: '2', sku: 'CAP-1'),
        _item(id: '3', sku: 'OTHER'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.first.copies, 2);
    });

    test('SKU matching ignores case and whitespace', () {
      final groups = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: '1', sku: 'cap-1'),
        _item(id: '2', sku: ' CAP-1 '),
      ]);
      expect(groups, hasLength(1));
    });

    test('falls back to name and size when there is no SKU', () {
      final groups = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: '1', name: 'Loose Rice', size: '1kg'),
        _item(id: '2', name: 'loose rice', size: '1kg'),
      ]);
      expect(groups, hasLength(1));
    });

    test('same name in a different size is NOT a duplicate', () {
      // A garment shop's S and XL are genuinely different products; merging
      // them would destroy both stock counts.
      final groups = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: '1', name: 'Cotton Vest', size: 'S'),
        _item(id: '2', name: 'Cotton Vest', size: 'XL'),
      ]);
      expect(groups, isEmpty);
    });

    test('items with different SKUs are never merged on name', () {
      final groups = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: '1', name: 'Cap', sku: 'A'),
        _item(id: '2', name: 'Cap', sku: 'B'),
      ]);
      expect(groups, isEmpty);
    });

    test('unnamed rows without a SKU are left alone', () {
      final groups = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: '1', name: ''),
        _item(id: '2', name: ''),
      ]);
      expect(groups, isEmpty);
    });

    test('a single item is never a duplicate', () {
      expect(
        findDuplicateItems(<InventoryCatalogItem>[_item(id: '1')]),
        isEmpty,
      );
      expect(findDuplicateItems(const <InventoryCatalogItem>[]), isEmpty);
    });
  });

  group('choosing which copy to keep', () {
    test('keeps the copy holding the most stock', () {
      final group = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: 'empty', sku: 'CAP-1', stock: 0),
        _item(id: 'real', sku: 'CAP-1', stock: 120),
      ]).single;
      expect(group.keeper.id, 'real');
      expect(group.duplicates.map((i) => i.id), <String>['empty']);
    });

    test('breaks a stock tie with the oldest row', () {
      final group = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: 'new', sku: 'CAP-1', stock: 5, createdDaysAgo: 1),
        _item(id: 'old', sku: 'CAP-1', stock: 5, createdDaysAgo: 30),
      ]).single;
      expect(group.keeper.id, 'old');
    });

    test('combined stock adds every copy, including negatives', () {
      final group = findDuplicateItems(<InventoryCatalogItem>[
        _item(id: '1', sku: 'CAP-1', stock: 100),
        _item(id: '2', sku: 'CAP-1', stock: -24),
      ]).single;
      expect(group.combinedStock, 76);
    });
  });

  group('report', () {
    test('counts extra rows, not groups', () {
      // Three copies of one product is two rows too many.
      final report = buildDataHealthReport(
        items: <InventoryCatalogItem>[
          _item(id: '1', sku: 'A'),
          _item(id: '2', sku: 'A'),
          _item(id: '3', sku: 'A'),
        ],
        customers: const <BackendCustomerSummary>[],
      );
      expect(report.duplicateGroups, hasLength(1));
      expect(report.duplicateRowCount, 2);
    });

    test('flags negative stock and missing prices', () {
      final report = buildDataHealthReport(
        items: <InventoryCatalogItem>[
          _item(id: '1', sku: 'A', stock: -24),
          _item(id: '2', sku: 'B', price: 0),
          _item(id: '3', sku: 'C'),
        ],
        customers: const <BackendCustomerSummary>[],
      );
      expect(report.negativeStock.map((i) => i.id), <String>['1']);
      expect(report.missingPrice.map((i) => i.id), <String>['2']);
    });

    test('only flags a missing mobile when the customer owes money', () {
      final report = buildDataHealthReport(
        items: const <InventoryCatalogItem>[],
        customers: <BackendCustomerSummary>[
          _customer(id: 'debt', phone: '', balance: 500),
          // A settled walk-in with no number is not a problem.
          _customer(id: 'settled', phone: '', balance: 0),
          _customer(id: 'reachable', phone: '9876543210', balance: 900),
        ],
      );
      expect(report.customersWithoutPhone.map((c) => c.id), <String>['debt']);
    });

    test('a clean shop reports healthy', () {
      final report = buildDataHealthReport(
        items: <InventoryCatalogItem>[_item(id: '1', sku: 'A')],
        customers: <BackendCustomerSummary>[
          _customer(phone: '9876543210', balance: 100),
        ],
      );
      expect(report.isHealthy, isTrue);
      expect(report.totalIssues, 0);
    });
  });
}
