import 'dart:io';

import 'package:business_hub_mobile/core/import/universal_import.dart';
import 'package:business_hub_mobile/core/import/xlsx_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('looksLikeXlsx', () {
    test('detects a zip (xlsx) vs a legacy .xls', () {
      expect(looksLikeXlsx(<int>[0x50, 0x4B, 0x03, 0x04]), isTrue); // "PK.."
      // Legacy .xls (BIFF) compound-file signature.
      expect(looksLikeXlsx(<int>[0xD0, 0xCF, 0x11, 0xE0]), isFalse);
      expect(looksLikeXlsx(<int>[]), isFalse);
    });
  });

  group('readXlsx (our own reader)', () {
    final file = File(r'D:/business-hub/demo_import.xlsx');

    test('parses every sheet with correct headers and row counts', () {
      if (!file.existsSync()) return; // fixture optional on CI
      final sheets = readXlsx(file.readAsBytesSync());
      final names = sheets.map((s) => s.name).toList();
      expect(
        names,
        containsAll(<String>['Items', 'Customers', 'receiptsWithItems']),
      );

      final items = sheets.firstWhere((s) => s.name == 'Items');
      expect(items.rows.first, contains('ITEM_NAME'));
      expect(items.rows.first, contains('STOCK'));
      // header + 11 product rows
      expect(items.rows.length, 12);
    });

    test('shared strings and numbers come through as text', () {
      if (!file.existsSync()) return;
      final sheets = readXlsx(file.readAsBytesSync());
      final items = sheets.firstWhere((s) => s.name == 'Items');
      final header = items.rows.first;
      final nameCol = header.indexOf('ITEM_NAME');
      final stockCol = header.indexOf('STOCK');
      final firstRow = items.rows[1];
      expect(firstRow[nameCol], isNotEmpty); // shared string
      expect(double.tryParse(firstRow[stockCol]), isNotNull); // numeric cell
    });

    test('feeds the universal importer end-to-end', () {
      if (!file.existsSync()) return;
      final table = parseXlsxBytes(file.readAsBytesSync());
      expect(table, isNotNull);
      expect(table!.headers, isNotEmpty);
      expect(table.rows, isNotEmpty);
    });
  });
}
