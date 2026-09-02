import 'package:business_hub_mobile/core/import/universal_import.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _sale({
  String date = '2024-03-15',
  String total = '500',
  String discount = '0',
  String payment = 'CASH',
  String customerName = 'Asha',
  String customerPhone = '9876543210',
  String? reference,
}) {
  return <String, String>{
    'date': date,
    'total': total,
    'discount': discount,
    'payment': payment,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'reference': ?reference,
  };
}

const List<String> _keys = <String>[
  'date',
  'total',
  'discount',
  'payment',
  'customerName',
  'customerPhone',
];

String _id(Map<String, String> row, Map<String, int> occ) => importRowId(
  'import-sale',
  row,
  _keys,
  occurrences: occ,
  reference: row['reference'],
);

void main() {
  group('stableRowKey', () {
    test('is content-based, unlike Map.hashCode', () {
      // The original bug: two maps with identical content hashed differently,
      // so every re-import created new sales instead of updating them.
      final a = <String, String>{'x': '1'};
      final b = <String, String>{'x': '1'};
      expect(
        a.hashCode == b.hashCode,
        isFalse,
        reason: 'Map.hashCode is identity-based',
      );
      expect(stableRowKey(<String>['1']), stableRowKey(<String>['1']));
    });

    test('separates fields so concatenation cannot collide', () {
      expect(
        stableRowKey(<String>['ab', 'c']) == stableRowKey(<String>['a', 'bc']),
        isFalse,
      );
    });

    test('ignores surrounding whitespace and case', () {
      expect(stableRowKey(<String>[' Asha ']), stableRowKey(<String>['asha']));
    });
  });

  group('importRowId', () {
    test('same file imported twice yields the same ids', () {
      final rows = <Map<String, String>>[_sale(), _sale(total: '250')];
      final first = <String, int>{};
      final second = <String, int>{};
      final idsA = rows.map((r) => _id(r, first)).toList();
      final idsB = rows.map((r) => _id(r, second)).toList();
      expect(idsA, idsB);
    });

    test('different content yields different ids', () {
      final occ = <String, int>{};
      expect(_id(_sale(), occ), isNot(_id(_sale(total: '900'), occ)));
    });

    test('genuinely repeated rows in one file stay distinct', () {
      // A shop really can ring up two identical Rs.500 cash sales in a day;
      // collapsing them into one would lose real revenue.
      final occ = <String, int>{};
      final a = _id(_sale(), occ);
      final b = _id(_sale(), occ);
      expect(a, isNot(b));
    });

    test('repeated rows keep their ids on re-import', () {
      final rows = <Map<String, String>>[_sale(), _sale(), _sale()];
      final idsA = () {
        final occ = <String, int>{};
        return rows.map((r) => _id(r, occ)).toList();
      }();
      final idsB = () {
        final occ = <String, int>{};
        return rows.map((r) => _id(r, occ)).toList();
      }();
      expect(idsA, idsB);
      expect(idsA.toSet().length, 3);
    });

    test('adding a new row does not renumber existing ones', () {
      // Occurrence counting (not row position) is what makes this hold - an
      // appended or prepended row must not duplicate everything else.
      final occA = <String, int>{};
      final original = _id(_sale(total: '500'), occA);

      final occB = <String, int>{};
      _id(_sale(total: '111'), occB); // a brand new row, imported first
      final afterInsert = _id(_sale(total: '500'), occB);

      expect(afterInsert, original);
    });

    test('an invoice number wins over content hashing', () {
      final occ = <String, int>{};
      // Same invoice, corrected amount: still the same receipt, so the import
      // must update it rather than add a second copy.
      final before = _id(_sale(total: '500', reference: 'INV-1001'), occ);
      final after = _id(_sale(total: '550', reference: 'INV-1001'), occ);
      expect(before, after);
      expect(before, contains('-ref-'));
    });

    test('different invoice numbers stay separate', () {
      final occ = <String, int>{};
      expect(
        _id(_sale(reference: 'INV-1'), occ),
        isNot(_id(_sale(reference: 'INV-2'), occ)),
      );
    });

    test('blank reference falls back to content hashing', () {
      final occ = <String, int>{};
      final id = _id(_sale(reference: '   '), occ);
      expect(id, isNot(contains('-ref-')));
    });
  });
}
