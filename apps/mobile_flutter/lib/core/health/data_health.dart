import '../models/mobile_models.dart';

/// A group of inventory rows that are really the same product.
///
/// Duplicates arrive from repeated spreadsheet imports. They matter because the
/// copies split one product's stock across several rows, so counts, reorder
/// suggestions and stock value all go wrong — and one copy usually sits at zero
/// and goes negative as soon as it's sold.
class DuplicateGroup {
  const DuplicateGroup({required this.key, required this.items});

  /// What made them match — SKU, or name + size.
  final String key;
  final List<InventoryCatalogItem> items;

  int get copies => items.length;

  double get combinedStock =>
      items.fold<double>(0, (sum, item) => sum + item.stock);

  /// The copy worth keeping: the one with the most stock, then the oldest,
  /// because that's usually the original row with real history behind it.
  InventoryCatalogItem get keeper {
    final sorted = [...items]
      ..sort((a, b) {
        final byStock = b.stock.compareTo(a.stock);
        if (byStock != 0) return byStock;
        return a.createdAt.compareTo(b.createdAt);
      });
    return sorted.first;
  }

  List<InventoryCatalogItem> get duplicates =>
      items.where((i) => i.id != keeper.id).toList(growable: false);
}

/// Everything wrong with the shop's data that we can detect and offer to fix.
class DataHealthReport {
  const DataHealthReport({
    this.duplicateGroups = const <DuplicateGroup>[],
    this.negativeStock = const <InventoryCatalogItem>[],
    this.missingPrice = const <InventoryCatalogItem>[],
    this.customersWithoutPhone = const <BackendCustomerSummary>[],
  });

  final List<DuplicateGroup> duplicateGroups;
  final List<InventoryCatalogItem> negativeStock;
  final List<InventoryCatalogItem> missingPrice;
  final List<BackendCustomerSummary> customersWithoutPhone;

  /// Extra rows that shouldn't exist (a group of 3 copies is 2 too many).
  int get duplicateRowCount =>
      duplicateGroups.fold<int>(0, (sum, g) => sum + g.copies - 1);

  int get totalIssues =>
      duplicateRowCount +
      negativeStock.length +
      missingPrice.length +
      customersWithoutPhone.length;

  bool get isHealthy => totalIssues == 0;

  static const DataHealthReport empty = DataHealthReport();
}

String _normalise(String? value) => (value ?? '').trim().toLowerCase();

/// Find inventory rows that are really the same product.
///
/// Matches on SKU when there is one, otherwise on name + size — the same rule
/// the importer now uses, so what the scan reports and what a re-import merges
/// stay consistent. Size matters: a garment shop's S and XL are different
/// products, not duplicates.
List<DuplicateGroup> findDuplicateItems(List<InventoryCatalogItem> items) {
  final bySku = <String, List<InventoryCatalogItem>>{};
  final byName = <String, List<InventoryCatalogItem>>{};

  for (final item in items) {
    final sku = _normalise(item.sku);
    if (sku.isNotEmpty) {
      bySku.putIfAbsent(sku, () => <InventoryCatalogItem>[]).add(item);
    } else {
      final key = '${_normalise(item.name)}|${_normalise(item.size)}';
      if (_normalise(item.name).isEmpty) continue;
      byName.putIfAbsent(key, () => <InventoryCatalogItem>[]).add(item);
    }
  }

  final groups = <DuplicateGroup>[];
  bySku.forEach((key, group) {
    if (group.length > 1) {
      groups.add(DuplicateGroup(key: key, items: group));
    }
  });
  byName.forEach((key, group) {
    if (group.length > 1) {
      groups.add(DuplicateGroup(key: key, items: group));
    }
  });

  // Worst first: the most copies, then the most stock at stake.
  groups.sort((a, b) {
    final byCopies = b.copies.compareTo(a.copies);
    if (byCopies != 0) return byCopies;
    return b.combinedStock.compareTo(a.combinedStock);
  });
  return groups;
}

DataHealthReport buildDataHealthReport({
  required List<InventoryCatalogItem> items,
  required List<BackendCustomerSummary> customers,
}) {
  return DataHealthReport(
    duplicateGroups: findDuplicateItems(items),
    negativeStock: items.where((i) => i.stock < 0).toList(growable: false),
    // A zero price means the till will happily ring up a free sale.
    missingPrice: items.where((i) => i.price <= 0).toList(growable: false),
    // Only customers who owe money: a walk-in with no number isn't a problem,
    // but a debt you can't chase is.
    customersWithoutPhone: customers
        .where((c) => c.balance > 0.009 && (c.phone ?? '').trim().length < 10)
        .toList(growable: false),
  );
}
