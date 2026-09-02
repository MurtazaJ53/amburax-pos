import 'package:business_hub_mobile/core/database/local_database.dart';
import 'package:business_hub_mobile/core/database/mobile_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client-side tenant isolation: switching shops must wipe the previous
/// tenant's cached data from every local table. Runs against real SQLite.
void main() {
  late BusinessHubDatabase db;
  late ShopRepository shop;
  late InventoryRepository inventory;
  late CustomerRepository customers;
  late SalesRepository sales;

  setUp(() {
    db = BusinessHubDatabase.forTesting(NativeDatabase.memory());
    shop = ShopRepository(db);
    inventory = InventoryRepository(db);
    customers = CustomerRepository(db);
    sales = SalesRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> count(String table) async {
    final rows = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table;')
        .get();
    return rows.first.read<int>('c');
  }

  Future<void> seedSomeData() async {
    await inventory.mergeInventoryDocument('i1', <String, dynamic>{
      'name': 'Widget',
      'price': 10.0,
      'stock': 5.0,
      'status': 'active',
      'tombstone': false,
    }, updatedAt: 1);
    await customers.mergeRemoteCustomerDocument('c1', <String, dynamic>{
      'name': 'Asha',
      'phone': '9876543210',
      'status': 'active',
      'balance': 100.0,
      'tombstone': false,
    }, updatedAt: 1);
    await sales.importHistoricalSale(
      id: 's1',
      date: '2024-03-15',
      createdAtMillis: 1,
      total: 100,
      discount: 0,
      paymentMode: 'CASH',
      customerName: null,
      customerPhone: null,
      footerNote: '',
      items: const <Map<String, dynamic>>[],
      payments: const <Map<String, dynamic>>[],
    );
  }

  test('clearAllWorkspaceData empties every shop-scoped table', () async {
    await seedSomeData();
    expect(await count('inventory'), 1);
    expect(await count('customers'), 1);
    expect(await count('sales'), 1);

    await shop.clearAllWorkspaceData();

    // Every data table is empty - no previous-tenant records survive.
    expect(await count('inventory'), 0);
    expect(await count('customers'), 0);
    expect(await count('sales'), 0);
    expect(await count('customer_ledger'), 0);
    expect(await count('stock_movements'), 0);
    expect(await count('commerce_outbox'), 0);
    expect(await count('expenses'), 0);
    expect(await count('purchases'), 0);
  });

  test('app-instance id survives a workspace wipe', () async {
    await shop.ensureAppInstanceId();
    final before = await shop.readSetting('app_instance_id');
    expect(before, isNotNull);
    await shop.clearAllWorkspaceData();
    // clearAllWorkspaceData does not touch shop settings (tokens/app id).
    expect(await shop.readSetting('app_instance_id'), before);
  });
}
