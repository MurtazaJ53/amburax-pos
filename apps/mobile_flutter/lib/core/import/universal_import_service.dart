import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/mobile_repository.dart';
import 'date_parse.dart';
import 'universal_import.dart';

final universalImportServiceProvider = Provider<UniversalImportService>((ref) {
  return UniversalImportService(
    ref.watch(inventoryRepositoryProvider),
    ref.watch(customerRepositoryProvider),
    ref.watch(salesRepositoryProvider),
    ref.watch(expenseRepositoryProvider),
  );
});

class ImportOutcome {
  const ImportOutcome({
    required this.imported,
    required this.skipped,
    this.undatedRows = 0,
    this.replacedRows = 0,
  });
  final int imported;
  final int skipped;

  /// Rows whose date cell could not be read, so they fell back to today.
  /// Surfaced to the user - silently re-dating a shop's history is the kind
  /// of damage they should hear about rather than discover months later.
  final int undatedRows;

  /// Rows that matched something already stored and overwrote it. Non-zero
  /// almost always means "this file was imported before" - worth saying out
  /// loud, because the alternative reading is that nothing happened.
  final int replacedRows;
}

/// Writes canonical rows produced by [mapRows] into the local store. Products
/// and customers are supported (both have repository merge methods); an entry
/// with the same key is updated, not duplicated.
class UniversalImportService {
  UniversalImportService(
    this._inventory,
    this._customers,
    this._sales,
    this._expenses,
  );

  final InventoryRepository _inventory;
  final CustomerRepository _customers;
  final SalesRepository _sales;
  final ExpenseRepository _expenses;

  Future<ImportOutcome> importProducts(MappedImport mapped) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final iso = DateTime.now().toIso8601String();
    var imported = 0;
    await _inventory.runInTransaction(() async {
      for (final row in mapped.rows) {
        final name = row['name'] ?? '';
        if (name.isEmpty) continue;
        final sku = row['sku'] ?? row['barcode'] ?? '';
        final id = 'import-inv-${name.hashCode}-${sku.hashCode}';
        await _inventory.mergeInventoryDocument(id, <String, dynamic>{
          'name': name,
          'price': parseNum(row['price']),
          'sku': sku,
          'category': (row['category'] ?? '').isEmpty
              ? 'General'
              : row['category'],
          'stock': parseNum(row['stock']),
          'hsnCode': row['hsnCode'] ?? '',
          'gstRate': parseNum(row['gstRate']),
          'status': 'active',
          'tombstone': false,
          'createdAt': iso,
          'updatedAt': iso,
        }, updatedAt: now);
        final cost = parseNum(row['costPrice']);
        if (cost > 0) {
          await _inventory.mergeInventoryPrivateDocument(id, <String, dynamic>{
            'costPrice': cost,
            'updatedAt': iso,
            'tombstone': false,
          }, updatedAt: now);
        }
        imported++;
      }
    });
    return ImportOutcome(
      imported: imported,
      skipped: mapped.rows.length - imported,
    );
  }

  /// Import flat sales rows (one row per bill) as historical sales — they show
  /// in History/Reports but do not change current stock or balances.
  Future<ImportOutcome> importSales(MappedImport mapped) async {
    var imported = 0;
    var undated = 0;
    var replaced = 0;
    // Tracks rows that are legitimately identical within one file so they get
    // distinct - but still reproducible - ids.
    final occurrences = <String, int>{};
    final existing = await _sales.existingSaleIds();
    await _inventory.runInTransaction(() async {
      for (final row in mapped.rows) {
        final total = parseNum(row['total']);
        if (total <= 0) continue;
        final parsed = parseImportDate(row['date']);
        if (parsed == null) undated++;
        final dt = parsed ?? DateTime.now();
        final date = dt.toIso8601String().split('T').first;
        final pay = _normalizePayment(row['payment'] ?? 'CASH');
        // Content-derived, NOT row.hashCode: Map.hashCode is identity-based, so
        // the same receipt hashed differently on every import and re-importing a
        // file silently duplicated every sale in it, inflating revenue.
        final id = importRowId(
          'import-sale',
          row,
          const <String>[
            'date',
            'total',
            'discount',
            'payment',
            'customerName',
            'customerPhone',
          ],
          occurrences: occurrences,
          reference: row['reference'],
        );
        if (existing.contains(id)) replaced++;
        await _sales.importHistoricalSale(
          id: id,
          date: date,
          createdAtMillis: dt.millisecondsSinceEpoch,
          total: total,
          discount: parseNum(row['discount']),
          paymentMode: pay,
          customerName: (row['customerName'] ?? '').isEmpty
              ? null
              : row['customerName'],
          customerPhone: (row['customerPhone'] ?? '').isEmpty
              ? null
              : row['customerPhone'],
          footerNote: 'Imported sale',
          items: const <Map<String, dynamic>>[],
          payments: <Map<String, dynamic>>[
            <String, dynamic>{'mode': pay, 'amount': total},
          ],
        );
        imported++;
      }
    });
    return ImportOutcome(
      imported: imported,
      skipped: mapped.rows.length - imported,
      undatedRows: undated,
      replacedRows: replaced,
    );
  }

  /// Import expenses (money-out). Category defaults to General; date defaults to
  /// today; payment mode normalized.
  Future<ImportOutcome> importExpenses(MappedImport mapped) async {
    var imported = 0;
    var undated = 0;
    await _inventory.runInTransaction(() async {
      for (final row in mapped.rows) {
        final amount = parseNum(row['amount']);
        if (amount <= 0) continue;
        final parsed = parseImportDate(row['date']);
        if (parsed == null) undated++;
        final dt = parsed ?? DateTime.now();
        await _expenses.recordExpense(
          category: (row['category'] ?? '').trim().isEmpty
              ? 'General'
              : row['category']!.trim(),
          amount: amount,
          expenseDate: dt,
          description: row['description'] ?? '',
          paymentMethod: _normalizePayment(row['payment'] ?? 'CASH'),
        );
        imported++;
      }
    });
    return ImportOutcome(
      imported: imported,
      skipped: mapped.rows.length - imported,
      undatedRows: undated,
    );
  }

  /// Export all products as CSV (round-trips with the products importer).
  Future<String> exportProductsCsv() async {
    final items = await _inventory
        .watchCatalogPage(pageSize: 100000, includeCost: true)
        .first;
    final rows = items
        .map(
          (i) => <String, String>{
            'name': i.name,
            'price': _n(i.price),
            'costPrice': i.costPrice == null ? '' : _n(i.costPrice!),
            'stock': _n(i.stock),
            'sku': i.sku ?? '',
            'category': i.category,
            'hsnCode': i.hsnCode ?? '',
            'gstRate': _n(i.gstRate),
          },
        )
        .toList();
    return exportCsvFor(ImportKind.products, rows);
  }

  /// Export all customers as CSV (round-trips with the customers importer).
  Future<String> exportCustomersCsv() async {
    final custs = await _customers.watchLegacyCustomers().first;
    final rows = custs
        .map(
          (c) => <String, String>{
            'name': c.name,
            'phone': c.phone ?? '',
            'email': c.email ?? '',
            'amountDue': c.balance > 0 ? _n(c.balance) : '0',
            'advance': c.balance < 0 ? _n(-c.balance) : '0',
          },
        )
        .toList();
    return exportCsvFor(ImportKind.customers, rows);
  }

  static String _n(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static String _normalizePayment(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('upi')) return 'UPI';
    if (v.contains('card')) return 'CARD';
    if (v.contains('credit') || v.contains('due')) return 'CREDIT';
    if (v.contains('bank') || v.contains('online')) return 'BANK';
    if (v.contains('cash')) return 'CASH';
    return raw.trim().isEmpty ? 'CASH' : raw.trim().toUpperCase();
  }

  Future<ImportOutcome> importCustomers(MappedImport mapped) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final iso = DateTime.now().toIso8601String();
    var imported = 0;
    var undated = 0;
    await _inventory.runInTransaction(() async {
      for (final row in mapped.rows) {
        final name = row['name'] ?? '';
        if (name.isEmpty) continue;
        final phone = row['phone'] ?? '';
        final balance = parseNum(row['amountDue']) - parseNum(row['advance']);
        final id = 'import-cust-${phone.hashCode}-${name.hashCode}';
        // Keep the date the customer was actually acquired. Without this every
        // imported client looked like it was added today, which wrecks "new
        // customers this month" and any ageing view built on created_at.
        final addedOn = parseImportDate(row['date']);
        if (addedOn == null) undated++;
        await _customers.mergeRemoteCustomerDocument(id, <String, dynamic>{
          'name': name,
          'phone': phone,
          'email': row['email'] ?? '',
          'status': 'active',
          'balance': balance,
          'total_spent': 0,
          'tombstone': false,
          'createdAt': (addedOn ?? DateTime.now()).millisecondsSinceEpoch,
          'updatedAt': iso,
        }, updatedAt: now);
        // Give the imported due a visible origin, otherwise the customer shows
        // a balance with an empty khata and nobody can say what it is for.
        await _customers.recordOpeningBalance(
          customerId: id,
          balance: balance,
          occurredAt: addedOn,
        );
        imported++;
      }
    });
    return ImportOutcome(
      imported: imported,
      skipped: mapped.rows.length - imported,
      undatedRows: undated,
    );
  }
}
