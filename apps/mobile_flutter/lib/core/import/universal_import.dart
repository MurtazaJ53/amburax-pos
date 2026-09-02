import 'package:excel/excel.dart';

import 'xlsx_reader.dart';

/// A format-agnostic import engine: read CSV or XLSX from *any* layout, then
/// auto-map its columns onto our canonical fields by fuzzy header matching, so
/// a shop can import a products/customers file exported from almost anywhere.
///
/// Pure + UI-free so it can be unit-tested; the UI adds file picking, a mapping
/// preview the user can override, and writing rows via the repositories.

enum ImportKind { products, customers, suppliers, sales, expenses }

enum FieldType { text, number }

class ImportField {
  const ImportField(
    this.key,
    this.label, {
    this.synonyms = const <String>[],
    this.required = false,
    this.type = FieldType.text,
  });

  final String key;
  final String label;
  final List<String> synonyms;
  final bool required;
  final FieldType type;

  /// All header spellings this field will match, normalized.
  Iterable<String> get _needles =>
      <String>[key, label, ...synonyms].map(normalizeHeader);
}

/// Canonical field definitions per data type. Order matters: earlier fields win
/// a contested column.
const Map<ImportKind, List<ImportField>>
importSchemas = <ImportKind, List<ImportField>>{
  ImportKind.products: <ImportField>[
    ImportField(
      'name',
      'Item name',
      required: true,
      synonyms: <String>[
        'item',
        'product',
        'product name',
        'title',
        'description',
        'particulars',
      ],
    ),
    ImportField(
      'price',
      'Price',
      type: FieldType.number,
      synonyms: <String>[
        'mrp',
        'rate',
        'selling price',
        'sale price',
        'sell price',
        'unit price',
        'amount',
      ],
    ),
    ImportField(
      'costPrice',
      'Cost price',
      type: FieldType.number,
      synonyms: <String>[
        'cost',
        'purchase price',
        'buy price',
        'cp',
        'purchase rate',
      ],
    ),
    ImportField(
      'stock',
      'Stock',
      type: FieldType.number,
      synonyms: <String>[
        'qty',
        'quantity',
        'on hand',
        'available',
        'stock on hand',
        'opening stock',
        'inventory',
        'in stock',
      ],
    ),
    ImportField(
      'sku',
      'SKU',
      synonyms: <String>['code', 'item code', 'product code'],
    ),
    ImportField('barcode', 'Barcode', synonyms: <String>['ean', 'upc', 'qr']),
    ImportField(
      'category',
      'Category',
      synonyms: <String>['cat', 'group', 'department', 'type'],
    ),
    ImportField(
      'hsnCode',
      'HSN',
      synonyms: <String>['hsn code', 'hsn/sac', 'sac'],
    ),
    ImportField(
      'gstRate',
      'GST rate',
      type: FieldType.number,
      synonyms: <String>['gst', 'tax', 'tax rate', 'gst %', 'gst percent'],
    ),
  ],
  ImportKind.customers: <ImportField>[
    ImportField(
      'name',
      'Name',
      required: true,
      synonyms: <String>[
        'customer',
        'customer name',
        'client',
        'client name',
        'party',
        'party name',
      ],
    ),
    ImportField(
      'phone',
      'Phone',
      synonyms: <String>[
        'mobile',
        'contact',
        'number',
        'phone number',
        'mobile number',
        'whatsapp',
        'contact number',
      ],
    ),
    ImportField(
      'email',
      'Email',
      synonyms: <String>['email id', 'e-mail', 'mail'],
    ),
    ImportField(
      'amountDue',
      'Amount due',
      type: FieldType.number,
      synonyms: <String>[
        'balance',
        'due',
        'outstanding',
        'credit',
        'pending',
        'closing balance',
      ],
    ),
    ImportField(
      'advance',
      'Advance',
      type: FieldType.number,
      synonyms: <String>['amount held', 'deposit', 'prepaid', 'advance paid'],
    ),
    ImportField(
      'date',
      'Added on',
      synonyms: <String>[
        'created',
        'created at',
        'created on',
        'date added',
        'added date',
        'joined',
        'joined on',
        'registration date',
        'since',
        'first visit',
      ],
    ),
  ],
  ImportKind.suppliers: <ImportField>[
    ImportField(
      'name',
      'Name',
      required: true,
      synonyms: <String>[
        'supplier',
        'supplier name',
        'vendor',
        'vendor name',
        'party',
      ],
    ),
    ImportField(
      'phone',
      'Phone',
      synonyms: <String>['mobile', 'contact', 'number', 'phone number'],
    ),
    ImportField('email', 'Email', synonyms: <String>['mail', 'email id']),
    ImportField(
      'gstin',
      'GSTIN',
      synonyms: <String>['gst', 'gst no', 'gst number', 'tax id'],
    ),
    ImportField(
      'amountDue',
      'Payable',
      type: FieldType.number,
      synonyms: <String>['balance', 'payable', 'due', 'outstanding'],
    ),
  ],
  ImportKind.sales: <ImportField>[
    ImportField(
      'total',
      'Total',
      required: true,
      type: FieldType.number,
      synonyms: <String>[
        'amount',
        'grand total',
        'net amount',
        'bill amount',
        'invoice value',
        'paid',
      ],
    ),
    ImportField(
      'date',
      'Date',
      synonyms: <String>[
        'sale date',
        'invoice date',
        'bill date',
        'txn date',
        'order date',
      ],
    ),
    ImportField(
      'discount',
      'Discount',
      type: FieldType.number,
      synonyms: <String>['disc'],
    ),
    ImportField(
      'payment',
      'Payment mode',
      synonyms: <String>[
        'payment',
        'mode',
        'method',
        'paid via',
        'tender',
        'payment type',
      ],
    ),
    ImportField(
      'customerName',
      'Customer',
      synonyms: <String>['customer name', 'client', 'party', 'name'],
    ),
    ImportField(
      'customerPhone',
      'Customer phone',
      synonyms: <String>['phone', 'mobile', 'contact', 'number'],
    ),
    ImportField(
      'reference',
      'Invoice no',
      synonyms: <String>[
        'invoice',
        'invoice number',
        'bill no',
        'bill number',
        'receipt no',
        'receipt number',
        'receipt id',
        'order no',
        'order id',
        'txn id',
        'transaction id',
        'voucher no',
        'ref',
        'reference',
      ],
    ),
  ],
  ImportKind.expenses: <ImportField>[
    ImportField(
      'amount',
      'Amount',
      required: true,
      type: FieldType.number,
      synonyms: <String>[
        'spent',
        'expense amount',
        'value',
        'debit',
        'total',
        'paid',
      ],
    ),
    ImportField(
      'category',
      'Category',
      synonyms: <String>['head', 'expense head', 'type', 'account', 'group'],
    ),
    ImportField(
      'date',
      'Date',
      synonyms: <String>['expense date', 'spent on', 'txn date', 'paid on'],
    ),
    ImportField(
      'description',
      'Description',
      synonyms: <String>[
        'note',
        'particulars',
        'details',
        'narration',
        'remark',
        'remarks',
      ],
    ),
    ImportField(
      'payment',
      'Payment mode',
      synonyms: <String>['mode', 'paid via', 'method', 'payment type'],
    ),
  ],
};

/// Lowercase + strip everything but a-z0-9, so "Item Name", "item_name" and
/// "ITEM-NAME" all collapse to "itemname".
String normalizeHeader(String h) =>
    h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

class ParsedTable {
  const ParsedTable(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows; // data rows only (no header)
}

/// Kinds we can auto-detect + execute today (suppliers has no local store yet).
const List<ImportKind> detectableKinds = <ImportKind>[
  ImportKind.products,
  ImportKind.customers,
  ImportKind.sales,
];

/// Score how well [headers] fit a [kind]: required fields count 3, others 1.
/// Returns 0 if a required field can't be mapped (that kind is impossible).
int scoreKind(List<String> headers, ImportKind kind) {
  final map = autoMap(headers, kind);
  final fields = importSchemas[kind]!;
  final requiredOk = fields
      .where((f) => f.required)
      .every((f) => map.columnFor(f.key) != null);
  if (!requiredOk) return 0;
  var score = 0;
  for (final f in fields) {
    if (map.columnFor(f.key) != null) score += f.required ? 3 : 1;
  }
  return score;
}

/// Auto-detect which data type a file is, purely from its header row — so
/// "smart import" can route any exported file (Zobaze, Vyapar, Khatabook,
/// Excel, …) to the right importer without the user choosing. Returns null if
/// nothing fits (e.g. no required column maps).
ImportKind? detectKind(List<String> headers) {
  ImportKind? best;
  var bestScore = 0;
  for (final kind in detectableKinds) {
    final s = scoreKind(headers, kind);
    if (s > bestScore) {
      bestScore = s;
      best = kind;
    }
  }
  return best;
}

/// Minimal RFC-4180 CSV parser: handles quoted fields, escaped quotes (""),
/// commas and newlines inside quotes. Returns headers + data rows.
ParsedTable parseCsv(String content) {
  final rows = <List<String>>[];
  var field = StringBuffer();
  var record = <String>[];
  var inQuotes = false;
  final s = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  void endField() {
    record.add(field.toString());
    field = StringBuffer();
  }

  void endRecord() {
    endField();
    // Skip fully-empty lines.
    if (record.any((c) => c.trim().isNotEmpty)) rows.add(record);
    record = <String>[];
  }

  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else {
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\n') {
        endRecord();
      } else {
        field.write(ch);
      }
    }
  }
  if (field.isNotEmpty || record.isNotEmpty) endRecord();

  if (rows.isEmpty) return const ParsedTable(<String>[], <List<String>>[]);
  final headers = rows.first.map((c) => c.trim()).toList();
  return ParsedTable(headers, rows.skip(1).toList());
}

/// Parse the first non-empty sheet of an XLSX file. Returns null if the `excel`
/// package fails to decode the file (it is fragile with some exporters) so the
/// caller can show a clean "save as CSV" message instead of crashing.
ParsedTable? parseXlsxBytes(List<int> bytes) {
  // 1) Our own reader first — it handles far more real-world exports than the
  //    `excel` package, which throws on many valid files.
  try {
    for (final sheet in readXlsx(bytes)) {
      if (sheet.rows.isEmpty) continue;
      final headers = sheet.rows.first
          .map((c) => c.trim())
          .toList(growable: false);
      if (headers.every((h) => h.isEmpty)) continue;
      final rows = sheet.rows
          .skip(1)
          .where((r) => r.any((c) => c.trim().isNotEmpty))
          .toList();
      return ParsedTable(headers, rows);
    }
  } catch (_) {
    // fall through to the package reader
  }

  // 2) Fallback: the `excel` package (kept so nothing regresses).
  try {
    final excel = Excel.decodeBytes(bytes);
    for (final name in excel.tables.keys) {
      final table = excel.tables[name];
      if (table == null || table.rows.isEmpty) continue;
      final headers = table.rows.first
          .map((c) => _xlsxCell(c).trim())
          .toList(growable: false);
      if (headers.every((h) => h.isEmpty)) continue;
      final rows = table.rows
          .skip(1)
          .map((r) => r.map(_xlsxCell).toList())
          .where((r) => r.any((c) => c.trim().isNotEmpty))
          .toList();
      return ParsedTable(headers, rows);
    }
    return const ParsedTable(<String>[], <List<String>>[]);
  } catch (_) {
    return null;
  }
}

String _xlsxCell(Data? cell) {
  final value = cell?.value;
  if (value == null) return '';
  if (value is TextCellValue) return value.value.toString().trim();
  if (value is IntCellValue) return value.value.toString();
  if (value is DoubleCellValue) return value.value.toString();
  return value.toString().trim();
}

/// The result of matching a file's headers to a kind's canonical fields.
class ColumnMapping {
  ColumnMapping(this.headers, this.fieldToColumn);
  final List<String> headers;
  final Map<String, int> fieldToColumn; // canonical field key -> header index

  int? columnFor(String fieldKey) => fieldToColumn[fieldKey];
}

/// Auto-map the file's [headers] to the canonical fields of [kind]. Two passes:
/// exact normalized match first, then a looser contains-match, never reusing a
/// column.
ColumnMapping autoMap(List<String> headers, ImportKind kind) {
  final fields = importSchemas[kind]!;
  final normHeaders = headers.map(normalizeHeader).toList();
  final used = <int>{};
  final mapping = <String, int>{};

  int? findExact(ImportField f) {
    for (final needle in f._needles) {
      final idx = normHeaders.indexOf(needle);
      if (idx >= 0 && !used.contains(idx)) return idx;
    }
    return null;
  }

  int? findFuzzy(ImportField f) {
    for (var idx = 0; idx < normHeaders.length; idx++) {
      if (used.contains(idx)) continue;
      final h = normHeaders[idx];
      if (h.isEmpty) continue;
      for (final needle in f._needles) {
        if (needle.length < 3) continue;
        if (h.contains(needle) || needle.contains(h)) return idx;
      }
    }
    return null;
  }

  for (final f in fields) {
    final idx = findExact(f);
    if (idx != null) {
      mapping[f.key] = idx;
      used.add(idx);
    }
  }
  for (final f in fields) {
    if (mapping.containsKey(f.key)) continue;
    final idx = findFuzzy(f);
    if (idx != null) {
      mapping[f.key] = idx;
      used.add(idx);
    }
  }
  return ColumnMapping(headers, mapping);
}

class MappedImport {
  const MappedImport(this.rows, this.missingRequired, this.mapping);
  final List<Map<String, String>> rows; // canonical field -> value
  final List<String> missingRequired; // required field keys with no column
  final ColumnMapping mapping;

  bool get ok => missingRequired.isEmpty && rows.isNotEmpty;
}

/// Apply a [mapping] (auto or user-edited) to produce canonical rows. Rows whose
/// required fields are all blank are dropped.
MappedImport mapRows(
  ParsedTable table,
  ImportKind kind, {
  ColumnMapping? mapping,
}) {
  final fields = importSchemas[kind]!;
  final map = mapping ?? autoMap(table.headers, kind);
  final missing = fields
      .where((f) => f.required && map.columnFor(f.key) == null)
      .map((f) => f.key)
      .toList();

  final out = <Map<String, String>>[];
  for (final row in table.rows) {
    final record = <String, String>{};
    for (final f in fields) {
      final col = map.columnFor(f.key);
      if (col == null || col >= row.length) continue;
      final raw = row[col].trim();
      if (raw.isEmpty) continue;
      record[f.key] = raw;
    }
    // Require a non-empty value for every required field.
    final hasRequired = fields
        .where((f) => f.required)
        .every((f) => (record[f.key] ?? '').isNotEmpty);
    if (hasRequired) out.add(record);
  }
  return MappedImport(out, missing, map);
}

/// Parse a numeric string tolerantly (strips currency symbols, commas, spaces).
double parseNum(String? s) {
  if (s == null) return 0;
  final cleaned = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
  return double.tryParse(cleaned) ?? 0;
}

// --------------------------------------------------------------------------- //
// CSV writing (templates + export round-trip)
// --------------------------------------------------------------------------- //

String _csvField(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// Serialize [rows] (each a list of cells) to CSV text.
String toCsv(List<List<String>> rows) =>
    rows.map((r) => r.map(_csvField).join(',')).join('\n');

/// A sample CSV for [kind] — a header row of our canonical labels plus a couple
/// of example rows, so a shop can see the exact expected shape.
String templateCsvFor(ImportKind kind) {
  final fields = importSchemas[kind]!;
  final header = fields.map((f) => f.label).toList();
  const samples = <ImportKind, List<List<String>>>{
    ImportKind.products: <List<String>>[
      <String>[
        'Parle-G Biscuits',
        '10',
        '7.5',
        '120',
        'BISC-001',
        '',
        'Snacks',
        '',
        '18',
      ],
      <String>[
        'Tomatoes (loose)',
        '40',
        '24',
        '35.5',
        '12345',
        '',
        'Vegetables',
        '',
        '0',
      ],
    ],
    ImportKind.customers: <List<String>>[
      <String>['Rahul Sharma', '9876543210', 'rahul@example.com', '250', '0'],
      <String>['Priya Patel', '9823001122', '', '0', '100'],
    ],
    ImportKind.suppliers: <List<String>>[
      <String>['Metro Wholesale', '9820011111', '', '27AAACM1234A1Z1', '0'],
    ],
    ImportKind.sales: <List<String>>[
      <String>['118', '2026-07-10', '0', 'Cash', 'Rahul Sharma', '9876543210'],
      <String>['540', '2026-07-12', '15', 'UPI', 'Sneha Iyer', '9900112233'],
    ],
    ImportKind.expenses: <List<String>>[
      <String>['1200', 'Rent', '2026-07-01', 'Shop rent', 'Cash'],
      <String>['350', 'Electricity', '2026-07-05', 'June bill', 'UPI'],
    ],
  };
  return toCsv(<List<String>>[header, ...samples[kind]!]);
}

/// Export canonical [rows] for [kind] to CSV (header of labels + one row per
/// record). Round-trips with the importer.
String exportCsvFor(ImportKind kind, List<Map<String, String>> rows) {
  final fields = importSchemas[kind]!;
  final out = <List<String>>[fields.map((f) => f.label).toList()];
  for (final row in rows) {
    out.add(fields.map((f) => row[f.key] ?? '').toList());
  }
  return toCsv(out);
}

/// Deterministic 64-bit FNV-1a hash of [parts], as 16 hex chars.
///
/// Import ids must survive across app runs and SDK upgrades, which rules out
/// Object.hashCode: `Map.hashCode` is identity-based, so the same spreadsheet
/// row hashed differently on every import and sales were re-inserted as new
/// records instead of updating. String.hashCode is content-based but Dart
/// gives no cross-version stability guarantee, so we pin our own.
String stableRowKey(Iterable<String> parts) {
  const int offsetBasis = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  var hash = offsetBasis;
  for (final part in parts) {
    for (final unit in part.trim().toLowerCase().codeUnits) {
      hash = ((hash ^ unit) * prime).toUnsigned(64);
    }
    // Field separator, so ['ab','c'] cannot collide with ['a','bc'].
    hash = ((hash ^ 0x7c) * prime).toUnsigned(64);
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Stable identity for an imported row.
///
/// A reference number (invoice/bill no) is the row's real primary key, so it
/// wins when present. Otherwise we hash the content, and disambiguate rows
/// that are legitimately identical - a shop really can ring up two Rs.50 cash
/// sales on the same day - with an occurrence counter. Counting occurrences
/// rather than using the row's position means adding rows elsewhere in the
/// file does not renumber, and therefore does not duplicate, the existing ones.
String importRowId(
  String prefix,
  Map<String, String> row,
  List<String> keys, {
  required Map<String, int> occurrences,
  String? reference,
}) {
  final ref = (reference ?? '').trim();
  if (ref.isNotEmpty) return '$prefix-ref-${stableRowKey(<String>[ref])}';
  final key = stableRowKey(keys.map((k) => row[k] ?? ''));
  final seen = occurrences[key] ?? 0;
  occurrences[key] = seen + 1;
  return seen == 0 ? '$prefix-$key' : '$prefix-$key-$seen';
}
