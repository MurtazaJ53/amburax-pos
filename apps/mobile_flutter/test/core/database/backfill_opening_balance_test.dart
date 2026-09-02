import 'package:business_hub_mobile/core/database/local_database.dart';
import 'package:business_hub_mobile/core/database/mobile_repository.dart';
import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Raw SQL against real SQLite - the backfill writes financial rows, so mocking
/// it out would prove nothing.
void main() {
  late BusinessHubDatabase db;
  late CustomerRepository customers;

  setUp(() {
    db = BusinessHubDatabase.forTesting(NativeDatabase.memory());
    customers = CustomerRepository(db);
  });

  tearDown(() async => db.close());

  Future<void> addCustomer({
    required String id,
    double balance = 500,
    int createdAt = 1710460800000,
    bool tombstone = false,
  }) async {
    await db
        .into(db.customerEntries)
        .insert(
          CustomerEntriesCompanion.insert(
            id: id,
            name: 'Customer $id',
            balance: Value(balance),
            createdAt: createdAt,
            tombstone: Value(tombstone),
          ),
        );
  }

  Future<List<CustomerLedgerRecord>> ledgerOf(String id) =>
      customers.watchLedger(id).first;

  test('gives an unexplained balance an opening row', () async {
    await addCustomer(id: 'c1', balance: 5000);

    expect(await customers.countUnexplainedBalances(), 1);
    expect(await customers.backfillOpeningBalances(), 1);

    final ledger = await ledgerOf('c1');
    expect(ledger.length, 1);
    expect(ledger.first.type, 'OPENING');
    expect(ledger.first.amount, 5000);
    expect(ledger.first.balanceAfter, 5000);
    // Dated to when the customer was added, not to the repair.
    expect(ledger.first.createdAt.millisecondsSinceEpoch, 1710460800000);
  });

  test('leaves customers who already have history alone', () async {
    await addCustomer(id: 'c1', balance: 900);
    await customers.recordOpeningBalance(customerId: 'c1', balance: 900);

    expect(await customers.countUnexplainedBalances(), 0);
    expect(await customers.backfillOpeningBalances(), 0);
    expect((await ledgerOf('c1')).length, 1, reason: 'must not double-count');
  });

  test('ignores customers who owe nothing', () async {
    await addCustomer(id: 'c1', balance: 0);

    expect(await customers.countUnexplainedBalances(), 0);
    expect(await customers.backfillOpeningBalances(), 0);
    expect(await ledgerOf('c1'), isEmpty);
  });

  test('handles advances (negative balances) too', () async {
    await addCustomer(id: 'c1', balance: -250);

    expect(await customers.backfillOpeningBalances(), 1);
    expect((await ledgerOf('c1')).first.amount, -250);
  });

  test('skips deleted customers', () async {
    await addCustomer(id: 'c1', balance: 700, tombstone: true);

    expect(await customers.countUnexplainedBalances(), 0);
    expect(await customers.backfillOpeningBalances(), 0);
  });

  test('is idempotent - a second run writes nothing', () async {
    await addCustomer(id: 'c1', balance: 300);
    await addCustomer(id: 'c2', balance: 400);

    expect(await customers.backfillOpeningBalances(), 2);
    expect(await customers.backfillOpeningBalances(), 0);
    expect((await ledgerOf('c1')).length, 1);
    expect((await ledgerOf('c2')).length, 1);
  });

  test('falls back to now when the customer has no created date', () async {
    await addCustomer(id: 'c1', balance: 100, createdAt: 0);
    final before = DateTime.now().millisecondsSinceEpoch;

    expect(await customers.backfillOpeningBalances(), 1);

    final entry = (await ledgerOf('c1')).first;
    expect(
      entry.createdAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(before),
    );
  });
}
