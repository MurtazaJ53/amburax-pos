import 'package:business_hub_mobile/core/database/local_database.dart';
import 'package:business_hub_mobile/core/database/mobile_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the de-dupe against a real SQLite database, because the whole
/// thing is raw SQL - a unit test over Dart objects would prove nothing about
/// the statement that actually deletes a shop's receipts.
void main() {
  late BusinessHubDatabase db;
  late SalesRepository sales;

  setUp(() {
    db = BusinessHubDatabase.forTesting(NativeDatabase.memory());
    sales = SalesRepository(db);
  });

  tearDown(() async => db.close());

  Future<void> addSale({
    required String id,
    String date = '2024-03-15',
    double total = 500,
    double discount = 0,
    String payment = 'CASH',
    String? customer = 'Asha',
    bool tombstone = false,
  }) async {
    await db
        .into(db.salesEntries)
        .insert(
          SalesEntriesCompanion.insert(
            id: id,
            total: total,
            discount: Value(discount),
            paymentMode: Value(payment),
            date: date,
            createdAt: 1710460800000,
            customerName: Value(customer),
            itemsJson: '[]',
            paymentsJson: '[]',
            tombstone: Value(tombstone),
          ),
        );
  }

  Future<int> liveCount() async {
    final rows = await db
        .customSelect('SELECT COUNT(*) AS c FROM sales WHERE tombstone = 0;')
        .get();
    return rows.first.read<int>('c');
  }

  Future<bool> alive(String id) async {
    final rows = await db
        .customSelect(
          'SELECT tombstone FROM sales WHERE id = ?;',
          variables: [Variable<String>(id)],
        )
        .get();
    return rows.first.read<int>('tombstone') == 0;
  }

  test('collapses duplicate imported receipts to one copy', () async {
    await addSale(id: 'import-sale-aaa');
    await addSale(id: 'import-sale-bbb');
    await addSale(id: 'import-sale-ccc');

    final groups = await sales.findImportedSaleDuplicates();
    expect(groups.length, 1);
    expect(groups.first.copies, 3);
    expect(groups.first.extras, 2);

    final removed = await sales.removeImportedSaleDuplicates();
    expect(removed, 2);
    expect(await liveCount(), 1);
    // Deterministic survivor, so a second run cannot eat the last copy.
    expect(await alive('import-sale-aaa'), isTrue);
  });

  test('never touches real POS sales, even identical ones', () async {
    // The scope filter is the only thing standing between this cleanup and a
    // shop's actual takings.
    await addSale(id: 'sale-pos-1');
    await addSale(id: 'sale-pos-2');

    expect(await sales.findImportedSaleDuplicates(), isEmpty);
    expect(await sales.removeImportedSaleDuplicates(), 0);
    expect(await liveCount(), 2);
  });

  test('leaves genuinely different receipts alone', () async {
    await addSale(id: 'import-sale-a', total: 500);
    await addSale(id: 'import-sale-b', total: 250);
    await addSale(id: 'import-sale-c', date: '2024-03-16');
    await addSale(id: 'import-sale-d', payment: 'UPI');
    await addSale(id: 'import-sale-e', customer: 'Ravi');

    expect(await sales.findImportedSaleDuplicates(), isEmpty);
    expect(await sales.removeImportedSaleDuplicates(), 0);
    expect(await liveCount(), 5);
  });

  test('is idempotent - running twice removes nothing more', () async {
    await addSale(id: 'import-sale-a');
    await addSale(id: 'import-sale-b');

    expect(await sales.removeImportedSaleDuplicates(), 1);
    expect(await sales.removeImportedSaleDuplicates(), 0);
    expect(await liveCount(), 1);
  });

  test('retires rather than deletes, so nothing is unrecoverable', () async {
    await addSale(id: 'import-sale-a');
    await addSale(id: 'import-sale-b');
    await sales.removeImportedSaleDuplicates();

    final rows = await db
        .customSelect('SELECT COUNT(*) AS c FROM sales;')
        .get();
    expect(rows.first.read<int>('c'), 2, reason: 'row still present');
    expect(await alive('import-sale-b'), isFalse);
  });

  test('ignores already-retired rows when counting duplicates', () async {
    await addSale(id: 'import-sale-a');
    await addSale(id: 'import-sale-b', tombstone: true);

    expect(await sales.findImportedSaleDuplicates(), isEmpty);
    expect(await sales.removeImportedSaleDuplicates(), 0);
  });

  test(
    'groups customers separately even at the same amount and date',
    () async {
      await addSale(id: 'import-sale-a1', customer: 'Asha');
      await addSale(id: 'import-sale-a2', customer: 'Asha');
      await addSale(id: 'import-sale-r1', customer: 'Ravi');

      final removed = await sales.removeImportedSaleDuplicates();
      expect(removed, 1);
      expect(await alive('import-sale-r1'), isTrue);
      expect(await liveCount(), 2);
    },
  );
}
