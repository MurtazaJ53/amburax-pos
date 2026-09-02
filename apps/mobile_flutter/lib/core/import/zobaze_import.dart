import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/mobile_repository.dart';
import 'date_parse.dart';
import 'xlsx_reader.dart';

final zobazeImportServiceProvider = Provider<ZobazeImportService>((ref) {
  return ZobazeImportService(
    ref.watch(inventoryRepositoryProvider),
    ref.watch(customerRepositoryProvider),
    ref.watch(salesRepositoryProvider),
  );
});

class ZobazeImportResult {
  const ZobazeImportResult({
    required this.inventory,
    required this.customers,
    required this.sales,
    required this.warnings,
  });

  final int inventory;
  final int customers;
  final int sales;
  final List<String> warnings;
}

class _ZobazeReceipt {
  _ZobazeReceipt(this.id);
  final String id;
  double total = 0;
  double discount = 0;
  String paymentMode = 'CASH';
  String customerName = '';
  String customerPhone = '';
  String dateRaw = '';
  String footerNote = '';
  final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
}

/// Import Zobaze `.xlsx` export files (inventory + customers) into the local
/// store. Sheet formats decoded from the legacy migrationEngine:
///   inventory : CATEGORY, ITEM_TYPE, ITEM_NAME, VARIANT_NAME, PRICE,
///               COST_PRICE, STOCK, SKU, BARCODE
///   customers : Name, Phone, Email, AmountDue, AmountHeld (Advance)
class ZobazeImportService {
  ZobazeImportService(this._inventory, this._customers, this._sales);

  final InventoryRepository _inventory;
  final CustomerRepository _customers;
  final SalesRepository _sales;

  static final RegExp _itemNamePattern = RegExp(
    r'^(.*?)\s*\((\d+(?:\.\d+)?)\s*[xX]\s*([0-9.]+)\)\s*$',
  );

  static String _normalizePayment(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('upi')) return 'UPI';
    if (v.contains('card')) return 'CARD';
    if (v.contains('credit') || v.contains('due')) return 'CREDIT';
    if (v.contains('online') || v.contains('bank')) return 'UPI';
    if (v.contains('cash')) return 'CASH';
    return raw.trim().isEmpty ? 'CASH' : raw.trim().toUpperCase();
  }

  Future<File?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['xlsx', 'xls'],
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  static double _num(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0;

  Future<ZobazeImportResult> importFile(File file) async {
    final bytes = await file.readAsBytes();
    if (!looksLikeXlsx(bytes)) {
      throw Exception(
        'This is an old .xls file. Open it in Excel/Google Sheets and save it '
        'as .xlsx (or .csv), then import again.',
      );
    }
    // Our own reader — the `excel` package throws on many real exports.
    final sheets = readXlsx(bytes);
    var inventoryCount = 0;
    var customerCount = 0;
    var salesCount = 0;
    final warnings = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final iso = DateTime.now().toIso8601String();

    for (final sheet in sheets) {
      final sheetName = sheet.name;
      final tableRows = sheet.rows;
      if (tableRows.length < 2) continue;

      final headers = tableRows.first;
      int col(String h) => headers.indexOf(h);
      String cell(List<String> row, String h) {
        final i = col(h);
        return (i < 0 || i >= row.length) ? '' : row[i].trim();
      }

      final isInventory = const <String>[
        'CATEGORY',
        'ITEM_NAME',
        'PRICE',
        'STOCK',
      ].every(headers.contains);
      final isCustomer =
          headers.contains('Name') && headers.contains('AmountDue');
      final isSales =
          headers.contains('ReceiptId') ||
          sheetName == 'receiptsWithItems' ||
          sheetName == 'receipts';

      if (isSales) {
        final receipts = <String, _ZobazeReceipt>{};
        for (final row in tableRows.skip(1)) {
          final receiptId = cell(row, 'ReceiptId');
          if (receiptId.isEmpty) continue;
          final r = receipts.putIfAbsent(
            receiptId,
            () => _ZobazeReceipt(receiptId),
          );
          final entryType = cell(row, 'EntryType').toLowerCase();
          if (entryType == 'item') {
            final entryName = cell(row, 'EntryName');
            final match = _itemNamePattern.firstMatch(entryName);
            final name = (match != null ? match.group(1)! : entryName).trim();
            if (name.isEmpty) continue;
            final qty = match != null
                ? (double.tryParse(match.group(2)!)?.round() ?? 1)
                : 1;
            final unit = match != null
                ? (double.tryParse(match.group(3)!) ?? 0)
                : 0.0;
            final lineAmount = _num(cell(row, 'EntryAmount'));
            final price = unit > 0
                ? unit
                : (qty > 0 ? lineAmount / qty : lineAmount);
            r.items.add(<String, dynamic>{
              'name': name,
              'quantity': qty,
              'price': double.parse(price.toStringAsFixed(2)),
              'gstRate': 0,
              'priceIncludesTax': true,
            });
          } else if (entryType.isEmpty) {
            r.total = _num(cell(row, 'Total'));
            r.discount = _num(cell(row, 'Discount'));
            r.paymentMode = _normalizePayment(cell(row, 'PaymentMode'));
            final cn = cell(row, 'CustomerName');
            if (cn.isNotEmpty) r.customerName = cn;
            final cp = cell(row, 'CustomerNumber').isNotEmpty
                ? cell(row, 'CustomerNumber')
                : cell(row, 'CustomerPhone');
            if (cp.isNotEmpty) r.customerPhone = cp;
            r.dateRaw = cell(row, 'Date');
            final cashier = cell(row, 'Cashier');
            r.footerNote =
                'Imported from Zobaze receipt $receiptId'
                '${cashier.isNotEmpty ? ' | Cashier: $cashier' : ''}';
          }
        }
        for (final r in receipts.values) {
          // Same trap as the universal importer: tryParse is ISO-only, so a
          // dd/MM/yyyy export silently became "today".
          final dt = parseImportDate(r.dateRaw) ?? DateTime.now();
          await _sales.importHistoricalSale(
            id: 'zobaze-${r.id}',
            date: dt.toIso8601String().split('T').first,
            createdAtMillis: dt.millisecondsSinceEpoch,
            total: r.total,
            discount: r.discount,
            paymentMode: r.paymentMode,
            customerName: r.customerName.isEmpty ? null : r.customerName,
            customerPhone: r.customerPhone.isEmpty ? null : r.customerPhone,
            footerNote: r.footerNote,
            items: r.items,
            payments: <Map<String, dynamic>>[
              <String, dynamic>{'mode': r.paymentMode, 'amount': r.total},
            ],
          );
          salesCount++;
        }
      } else if (isInventory) {
        for (final row in tableRows.skip(1)) {
          final name = cell(row, 'ITEM_NAME');
          if (name.isEmpty) continue;
          final variant = cell(row, 'VARIANT_NAME');
          final category = cell(row, 'CATEGORY');
          final sku = cell(row, 'SKU');
          final barcode = cell(row, 'BARCODE');
          final id =
              'zobaze-inv-${name.hashCode}-${variant.hashCode}-${category.hashCode}';
          await _inventory.mergeInventoryDocument(id, <String, dynamic>{
            'name': name,
            'price': _num(cell(row, 'PRICE')),
            'sku': sku.isNotEmpty ? sku : barcode,
            'category': category.isEmpty ? 'General' : category,
            'subcategory': cell(row, 'ITEM_TYPE'),
            'size': variant,
            'stock': _num(cell(row, 'STOCK')),
            'status': 'active',
            'tombstone': false,
            'createdAt': iso,
            'updatedAt': iso,
          }, updatedAt: now);
          final cost = _num(cell(row, 'COST_PRICE'));
          if (cost > 0) {
            await _inventory.mergeInventoryPrivateDocument(
              id,
              <String, dynamic>{
                'costPrice': cost,
                'updatedAt': iso,
                'tombstone': false,
              },
              updatedAt: now,
            );
          }
          inventoryCount++;
        }
      } else if (isCustomer) {
        for (final row in tableRows.skip(1)) {
          final name = cell(row, 'Name');
          if (name.isEmpty) continue;
          final phone = cell(row, 'Phone');
          final due = _num(cell(row, 'AmountDue'));
          final advance = _num(cell(row, 'AmountHeld (Advance)'));
          final id = 'zobaze-cust-${phone.hashCode}-${name.hashCode}';
          await _customers.mergeRemoteCustomerDocument(id, <String, dynamic>{
            'name': name,
            'phone': phone,
            'email': cell(row, 'Email'),
            'status': 'active',
            'balance': due - advance,
            'total_spent': 0,
            'tombstone': false,
            'updatedAt': iso,
          }, updatedAt: now);
          // Same reason as the universal importer: a due with no khata row is
          // a number the owner cannot explain to the customer.
          await _customers.recordOpeningBalance(
            customerId: id,
            balance: due - advance,
            note: 'Opening balance (imported from Zobaze)',
          );
          customerCount++;
        }
      }
    }

    if (inventoryCount == 0 && customerCount == 0 && salesCount == 0) {
      warnings.add(
        'No Zobaze inventory, customer, or receipts sheet was found. Export '
        'Items / Customers / Receipts from Zobaze as Excel and try again.',
      );
    } else {
      if (customerCount > 0) {
        warnings.add(
          'Customer lifetime spend is not in Zobaze exports, so it rebuilds '
          'from new sales.',
        );
      }
      if (salesCount > 0) {
        warnings.add(
          'Imported receipts are historical: they appear in History and '
          'Reports but do NOT change current stock or customer balances.',
        );
      }
    }
    return ZobazeImportResult(
      inventory: inventoryCount,
      customers: customerCount,
      sales: salesCount,
      warnings: warnings,
    );
  }
}
