import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'local_database.g.dart';

final localDatabaseProvider = Provider<BusinessHubDatabase>((ref) {
  return LocalDatabaseController.instance.database;
});

class ShopSettingsEntries extends Table {
  @override
  String get tableName => 'shop_settings';

  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>>? get primaryKey => {key};
}

@TableIndex(name: 'inventory_name_idx', columns: {#name})
@TableIndex(name: 'inventory_sku_idx', columns: {#sku})
@TableIndex(name: 'inventory_category_idx', columns: {#category})
@TableIndex(name: 'inventory_tombstone_idx', columns: {#tombstone})
class InventoryEntries extends Table {
  @override
  String get tableName => 'inventory';

  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get price => real()();
  TextColumn get sku => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('General'))();
  TextColumn get subcategory => text().nullable()();
  TextColumn get size => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get hsnCode => text().named('hsn_code').nullable()();
  RealColumn get gstRate =>
      real().named('gst_rate').withDefault(const Constant(0))();
  BoolColumn get priceIncludesTax =>
      boolean().named('price_includes_tax').withDefault(const Constant(true))();
  // Real-valued so loose goods (e.g. 1.5 kg) can be stocked and sold; whole
  // units stay exact.
  RealColumn get stock => real().withDefault(const Constant(0))();
  TextColumn get sourceMeta => text().named('source_meta').nullable()();
  TextColumn get imagePath => text().named('image_path').nullable()();
  TextColumn get unit => text().nullable()();
  IntColumn get reorderLevel => integer().named('reorder_level').nullable()();

  /// Whether this item has ever been given stock, from the backend's
  /// `has_stock_history`. Null means the server did not say — an older
  /// deployment, or a row written before this column existed. Null is not
  /// false: treating "unknown" as "never stocked" would label a shelf holding
  /// 462 units as untracked, which is the mistake the web already made and
  /// wrote a comment about.
  BoolColumn get hasStockHistory =>
      boolean().named('has_stock_history').nullable()();
  TextColumn get variantGroupId =>
      text().named('variant_group_id').nullable()();
  TextColumn get variantLabel => text().named('variant_label').nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt =>
      integer().named('updated_at').withDefault(const Constant(0))();
  BoolColumn get tombstone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class InventoryPrivateEntries extends Table {
  @override
  String get tableName => 'inventory_private';

  TextColumn get id => text()();
  RealColumn get costPrice =>
      real().named('cost_price').withDefault(const Constant(0))();
  TextColumn get supplierId => text().named('supplier_id').nullable()();
  TextColumn get lastPurchaseDate =>
      text().named('last_purchase_date').nullable()();
  IntColumn get updatedAt =>
      integer().named('updated_at').withDefault(const Constant(0))();
  BoolColumn get tombstone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@TableIndex(name: 'sales_created_at_idx', columns: {#createdAt})
@TableIndex(name: 'sales_tombstone_idx', columns: {#tombstone})
@TableIndex(name: 'sales_sync_status_idx', columns: {#syncStatus})
class SalesEntries extends Table {
  @override
  String get tableName => 'sales';

  TextColumn get id => text()();
  RealColumn get total => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  TextColumn get discountType =>
      text().named('discount_type').withDefault(const Constant('fixed'))();
  TextColumn get paymentMode =>
      text().named('payment_mode').withDefault(const Constant('CASH'))();
  TextColumn get date => text()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt =>
      integer().named('updated_at').withDefault(const Constant(0))();
  TextColumn get customerName => text().named('customer_name').nullable()();
  TextColumn get customerPhone => text().named('customer_phone').nullable()();
  TextColumn get customerId => text().named('customer_id').nullable()();
  TextColumn get footerNote => text().named('footer_note').nullable()();
  TextColumn get itemsJson => text().named('items_json')();
  TextColumn get paymentsJson => text().named('payments_json')();
  TextColumn get commandId => text().named('command_id').nullable()();
  TextColumn get syncStatus =>
      text().named('sync_status').withDefault(const Constant('local_only'))();
  TextColumn get backendReceiptId =>
      text().named('backend_receipt_id').nullable()();
  TextColumn get backendSaleId => text().named('backend_sale_id').nullable()();
  TextColumn get lastSyncError => text().named('last_sync_error').nullable()();
  IntColumn get lastSyncedAt => integer().named('last_synced_at').nullable()();
  BoolColumn get tombstone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@TableIndex(name: 'customers_name_idx', columns: {#name})
@TableIndex(name: 'customers_phone_idx', columns: {#phone})
@TableIndex(name: 'customers_tombstone_idx', columns: {#tombstone})
class CustomerEntries extends Table {
  @override
  String get tableName => 'customers';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  RealColumn get totalSpent =>
      real().named('total_spent').withDefault(const Constant(0))();
  RealColumn get balance => real().withDefault(const Constant(0))();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt =>
      integer().named('updated_at').withDefault(const Constant(0))();
  IntColumn get lastSeenAt => integer().named('last_seen_at').nullable()();

  /// When a khata reminder was last sent to this customer, so the collection
  /// list can skip anyone already chased today and show who is overdue.
  IntColumn get lastRemindedAt =>
      integer().named('last_reminded_at').nullable()();
  BoolColumn get tombstone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class CommerceOutboxEntries extends Table {
  @override
  String get tableName => 'commerce_outbox';

  TextColumn get commandId => text().named('command_id')();
  TextColumn get shopId => text().named('shop_id')();
  TextColumn get commandType => text().named('command_type')();
  TextColumn get domain => text()();
  IntColumn get baseDomainEpoch =>
      integer().named('base_domain_epoch').withDefault(const Constant(1))();
  TextColumn get payloadJson => text().named('payload_json')();
  TextColumn get syncStatus =>
      text().named('sync_status').withDefault(const Constant('pending'))();
  IntColumn get attemptCount =>
      integer().named('attempt_count').withDefault(const Constant(0))();
  TextColumn get lastError => text().named('last_error').nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt =>
      integer().named('updated_at').withDefault(const Constant(0))();
  IntColumn get lastAttemptAt =>
      integer().named('last_attempt_at').nullable()();
  IntColumn get completedAt => integer().named('completed_at').nullable()();
  // Dead-letter: a terminal state for commands the server permanently rejected
  // (4xx validation), so they stop retrying and surface for a human to resolve.
  BoolColumn get isDeadLetter =>
      boolean().named('is_dead_letter').withDefault(const Constant(false))();
  TextColumn get deadLetterReason =>
      text().named('dead_letter_reason').nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {commandId};
}

class ExpenseEntries extends Table {
  @override
  String get tableName => 'expenses';

  TextColumn get id => text()();
  TextColumn get category => text().withDefault(const Constant('General'))();
  RealColumn get amount => real().withDefault(const Constant(0))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get paymentMethod =>
      text().named('payment_method').withDefault(const Constant('CASH'))();
  TextColumn get paymentReference =>
      text().named('payment_reference').withDefault(const Constant(''))();
  TextColumn get expenseDate => text().named('expense_date')();
  TextColumn get actorName => text().named('actor_name').nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt =>
      integer().named('updated_at').withDefault(const Constant(0))();
  BoolColumn get tombstone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

/// Stock buying (money-out to suppliers). A purchase carries what was bought,
/// what was paid now, and leaves the rest as a payable. Supplier dues are
/// derived by grouping non-tombstoned purchases by supplier.
class PurchaseEntries extends Table {
  @override
  String get tableName => 'purchases';

  TextColumn get id => text()();
  TextColumn get supplierName => text().named('supplier_name')();
  TextColumn get supplierPhone =>
      text().named('supplier_phone').withDefault(const Constant(''))();
  TextColumn get reference => text().withDefault(const Constant(''))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid =>
      real().named('amount_paid').withDefault(const Constant(0))();
  TextColumn get paymentMethod =>
      text().named('payment_method').withDefault(const Constant('CASH'))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get purchaseDate => text().named('purchase_date')();
  TextColumn get actorName => text().named('actor_name').nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt =>
      integer().named('updated_at').withDefault(const Constant(0))();
  BoolColumn get tombstone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

/// Append-only audit trail of every stock change: sold in POS, received from a
/// purchase, returned, or manually adjusted. `delta` is signed (+in / -out).
class StockMovementEntries extends Table {
  @override
  String get tableName => 'stock_movements';

  TextColumn get id => text()();
  TextColumn get itemId => text().named('item_id')();
  TextColumn get itemName => text().named('item_name')();
  RealColumn get delta => real()();
  RealColumn get balanceAfter => real().named('balance_after').nullable()();

  /// SALE | PURCHASE | RETURN | ADJUST | OPENING
  TextColumn get reason => text()();
  TextColumn get refId => text().named('ref_id').nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get actorName => text().named('actor_name').nullable()();
  IntColumn get createdAt => integer().named('created_at')();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

/// Customer khata: every credit sale and payment as a running timeline.
/// `amount` is signed — a credit sale adds to the due (+), a payment reduces
/// it (−). `balanceAfter` is the customer's due immediately after the entry.
class CustomerLedgerEntries extends Table {
  @override
  String get tableName => 'customer_ledger';

  TextColumn get id => text()();
  TextColumn get customerId => text().named('customer_id')();
  TextColumn get type => text()(); // SALE_CREDIT | PAYMENT | ADJUST
  RealColumn get amount => real()();
  RealColumn get balanceAfter => real().named('balance_after')();
  TextColumn get refId => text().named('ref_id').nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get actorName => text().named('actor_name').nullable()();
  IntColumn get createdAt => integer().named('created_at')();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    ShopSettingsEntries,
    InventoryEntries,
    InventoryPrivateEntries,
    SalesEntries,
    CustomerEntries,
    CommerceOutboxEntries,
    ExpenseEntries,
    PurchaseEntries,
    StockMovementEntries,
    CustomerLedgerEntries,
  ],
)
class BusinessHubDatabase extends _$BusinessHubDatabase {
  BusinessHubDatabase()
    : super(
        driftDatabase(
          name: 'business_hub_mobile',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  /// Backs the database with a caller-supplied executor (an in-memory one in
  /// tests), so raw-SQL work can be exercised against real SQLite rather than
  /// mocked away - which is the only way to prove a destructive statement.
  BusinessHubDatabase.forTesting(super.executor) : super();

  @override
  int get schemaVersion => 17;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 17) {
        await m.addColumn(inventoryEntries, inventoryEntries.hasStockHistory);
      }
      if (from < 16) {
        await m.addColumn(customerEntries, customerEntries.lastRemindedAt);
      }
      if (from < 15) {
        await m.addColumn(
          commerceOutboxEntries,
          commerceOutboxEntries.isDeadLetter,
        );
        await m.addColumn(
          commerceOutboxEntries,
          commerceOutboxEntries.deadLetterReason,
        );
      }
      if (from < 2) {
        await m.addColumn(salesEntries, salesEntries.commandId);
        await m.addColumn(salesEntries, salesEntries.syncStatus);
        await m.addColumn(salesEntries, salesEntries.backendReceiptId);
        await m.addColumn(salesEntries, salesEntries.lastSyncError);
        await m.addColumn(salesEntries, salesEntries.lastSyncedAt);
        await m.createTable(commerceOutboxEntries);
      }
      if (from < 3) {
        await m.addColumn(salesEntries, salesEntries.backendSaleId);
      }
      if (from < 4) {
        await m.createTable(customerEntries);
      }
      if (from < 5) {
        await m.addColumn(inventoryEntries, inventoryEntries.hsnCode);
        await m.addColumn(inventoryEntries, inventoryEntries.gstRate);
        await m.addColumn(inventoryEntries, inventoryEntries.priceIncludesTax);
      }
      if (from < 6) {
        // Indexes are automatically handled by Drift on upgrade if we don't drop the table.
        // We just need to bump the schema version.
      }
      if (from < 7) {
        await m.createTable(expenseEntries);
      }
      if (from < 8) {
        await m.addColumn(inventoryEntries, inventoryEntries.imagePath);
      }
      if (from < 9) {
        await m.createTable(purchaseEntries);
      }
      if (from < 10) {
        await m.addColumn(inventoryEntries, inventoryEntries.unit);
        await m.addColumn(inventoryEntries, inventoryEntries.reorderLevel);
      }
      if (from < 11) {
        await m.addColumn(inventoryEntries, inventoryEntries.variantGroupId);
        await m.addColumn(inventoryEntries, inventoryEntries.variantLabel);
      }
      if (from < 12) {
        await m.createTable(stockMovementEntries);
      }
      if (from < 13) {
        await m.createTable(customerLedgerEntries);
      }
      if (from < 14) {
        // inventory.stock and stock_movements.delta/balance_after became REAL
        // (fractional). SQLite numeric affinity already stores fractional
        // values losslessly and existing whole numbers read back as doubles,
        // so no data rewrite is required — the type change is transparent.
      }
    },
  );
}

final class LocalDatabaseController {
  LocalDatabaseController._();

  static final LocalDatabaseController instance = LocalDatabaseController._();
  final BusinessHubDatabase database = BusinessHubDatabase();

  Future<void> initialize() async {
    await database.customSelect('SELECT 1;').get();
  }
}
