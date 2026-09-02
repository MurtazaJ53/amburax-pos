import 'package:business_hub_mobile/core/import/universal_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeHeader', () {
    test('collapses case, spaces, underscores, dashes', () {
      expect(normalizeHeader('Item Name'), 'itemname');
      expect(normalizeHeader('item_name'), 'itemname');
      expect(normalizeHeader('ITEM-NAME'), 'itemname');
    });
  });

  group('parseCsv', () {
    test('parses headers + rows', () {
      final t = parseCsv('name,price\nPen,10\nBook,50\n');
      expect(t.headers, ['name', 'price']);
      expect(t.rows.length, 2);
      expect(t.rows[1], ['Book', '50']);
    });

    test('handles quoted fields with commas and escaped quotes', () {
      final t = parseCsv('name,note\n"Sharma, R","he said ""hi"""\n');
      expect(t.rows.single, ['Sharma, R', 'he said "hi"']);
    });

    test('skips blank lines', () {
      final t = parseCsv('a,b\n\n1,2\n\n');
      expect(t.rows.length, 1);
    });
  });

  group('autoMap products (any layout)', () {
    test('maps MRP->price, Qty->stock, Item Name->name, Cost->costPrice', () {
      final m = autoMap([
        'Item Name',
        'MRP',
        'Qty',
        'Cost',
        'HSN',
      ], ImportKind.products);
      expect(m.columnFor('name'), 0);
      expect(m.columnFor('price'), 1);
      expect(m.columnFor('stock'), 2);
      expect(m.columnFor('costPrice'), 3);
      expect(m.columnFor('hsnCode'), 4);
    });

    test('never assigns one column to two fields', () {
      final m = autoMap(['Product', 'Rate'], ImportKind.products);
      final used = m.fieldToColumn.values.toList();
      expect(used.toSet().length, used.length);
    });
  });

  group('autoMap customers', () {
    test('maps Customer Name->name, Mobile->phone, Balance->amountDue', () {
      final m = autoMap([
        'Customer Name',
        'Mobile',
        'Balance',
        'E-mail',
      ], ImportKind.customers);
      expect(m.columnFor('name'), 0);
      expect(m.columnFor('phone'), 1);
      expect(m.columnFor('amountDue'), 2);
      expect(m.columnFor('email'), 3);
    });
  });

  group('mapRows', () {
    test(
      'produces canonical rows and drops rows missing the required name',
      () {
        final table = parseCsv(
          'Product,Rate,Qty\nPen,10,5\n,20,3\nBook,50,2\n',
        );
        final mapped = mapRows(table, ImportKind.products);
        expect(mapped.ok, isTrue);
        expect(mapped.missingRequired, isEmpty);
        // The nameless middle row is dropped.
        expect(mapped.rows.length, 2);
        expect(mapped.rows.first['name'], 'Pen');
        expect(mapped.rows.first['price'], '10');
        expect(mapped.rows.first['stock'], '5');
      },
    );

    test('flags missing required field when no name column exists', () {
      final table = parseCsv('Rate,Qty\n10,5\n');
      final mapped = mapRows(table, ImportKind.products);
      expect(mapped.missingRequired, contains('name'));
      expect(mapped.ok, isFalse);
    });
  });

  group('autoMap sales', () {
    test('maps Amount->total, Bill Date->date, Mode->payment', () {
      final m = autoMap([
        'Bill Date',
        'Amount',
        'Mode',
        'Customer',
      ], ImportKind.sales);
      expect(m.columnFor('total'), 1);
      expect(m.columnFor('date'), 0);
      expect(m.columnFor('payment'), 2);
      expect(m.columnFor('customerName'), 3);
    });
  });

  group('detectKind (smart import routing)', () {
    test('detects products from Item Name/MRP/Qty', () {
      expect(
        detectKind(['Item Name', 'MRP', 'Qty', 'SKU']),
        ImportKind.products,
      );
    });
    test('detects customers from Customer Name/Mobile/Balance', () {
      expect(
        detectKind(['Customer Name', 'Mobile', 'Balance']),
        ImportKind.customers,
      );
    });
    test('detects sales from Amount/Bill Date/Mode', () {
      expect(
        detectKind(['Amount', 'Bill Date', 'Mode', 'Customer']),
        ImportKind.sales,
      );
    });
    test('returns null when no required column maps', () {
      expect(detectKind(['Foo', 'Bar', 'Baz']), isNull);
    });
  });

  group('known-app header presets (fuzzy)', () {
    test('Vyapar-style product headers map correctly', () {
      final m = autoMap([
        'Item Name',
        'Sale Price',
        'Purchase Price',
        'Closing Stock',
        'Item Code',
      ], ImportKind.products);
      expect(m.columnFor('name'), 0);
      expect(m.columnFor('price'), 1);
      expect(m.columnFor('costPrice'), 2);
      expect(m.columnFor('stock'), 3);
      expect(m.columnFor('sku'), 4);
    });

    test('Khatabook-style customer headers map correctly', () {
      final m = autoMap([
        'Party Name',
        'Mobile Number',
        'Closing Balance',
      ], ImportKind.customers);
      expect(m.columnFor('name'), 0);
      expect(m.columnFor('phone'), 1);
      expect(m.columnFor('amountDue'), 2);
    });
  });

  group('expenses import', () {
    test('maps Amount/Category/Date and requires amount', () {
      final table = parseCsv(
        'Category,Amount,Date,Note\nRent,1200,2026-07-01,Shop\n',
      );
      final mapped = mapRows(table, ImportKind.expenses);
      expect(mapped.ok, isTrue);
      expect(mapped.rows.single['amount'], '1200');
      expect(mapped.rows.single['category'], 'Rent');
    });

    test('expenses is NOT auto-detected (avoids sales ambiguity)', () {
      // A bare amount+date file routes to sales, not expenses.
      expect(detectKind(['Amount', 'Date']), isNot(ImportKind.expenses));
    });
  });

  group('CSV writing', () {
    test('toCsv quotes fields with commas/quotes/newlines', () {
      final csv = toCsv([
        ['a', 'b'],
        ['x,y', 'he "said"'],
      ]);
      expect(csv, 'a,b\n"x,y","he ""said"""');
    });

    test('templateCsvFor(products) has our labels + sample rows', () {
      final csv = templateCsvFor(ImportKind.products);
      final table = parseCsv(csv);
      expect(table.headers, contains('Item name'));
      expect(table.headers, contains('Stock'));
      expect(table.rows, isNotEmpty);
    });

    test('exportCsvFor round-trips back through the importer', () {
      final rows = <Map<String, String>>[
        <String, String>{'name': 'Pen', 'price': '10', 'stock': '5'},
      ];
      final csv = exportCsvFor(ImportKind.products, rows);
      final reimported = mapRows(parseCsv(csv), ImportKind.products);
      expect(reimported.rows.single['name'], 'Pen');
      expect(reimported.rows.single['price'], '10');
      expect(reimported.rows.single['stock'], '5');
    });
  });

  group('parseNum', () {
    test('strips currency symbols, commas and spaces', () {
      expect(parseNum(r'₹ 1,250.50'), closeTo(1250.50, 0.001));
      expect(parseNum('-40'), -40);
      expect(parseNum('abc'), 0);
      expect(parseNum(null), 0);
    });
  });
}
