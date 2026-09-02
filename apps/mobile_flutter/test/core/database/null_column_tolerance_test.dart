import 'package:business_hub_mobile/core/database/local_database.dart';
import 'package:business_hub_mobile/core/database/mobile_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drift's `row.read<T>()` null-asserts internally, so a single NULL in one
/// column throws "Null check operator used on a null value" and takes down the
/// entire stream — not just that row.
///
/// That is what broke restocking: logStockAdjustment wrote a movement, the
/// stock-movement stream woke up, its mapper hit a NULL `note`, and the crash
/// surfaced in the code awaiting the save — pointing at innocent code and
/// hiding the real cause.
///
/// These tests write NULLs directly with raw SQL (the generated companions
/// would fill in defaults and prove nothing) and assert the mappers survive.
void main() {
  late BusinessHubDatabase db;

  setUp(() async {
    db = BusinessHubDatabase.forTesting(NativeDatabase.memory());
    // A freshly created schema declares these columns NOT NULL, but a device
    // that upgraded through migrations does not: a column added later with
    // addColumn is nullable, and rows written before it existed hold NULL.
    // Recreate the tables permissively so the test reproduces the state a real
    // shop's database is actually in.
    await db.customStatement('DROP TABLE stock_movements');
    await db.customStatement(
      'CREATE TABLE stock_movements ('
      'id TEXT NOT NULL PRIMARY KEY, item_id TEXT, item_name TEXT, '
      'delta REAL, balance_after REAL, reason TEXT, ref_id TEXT, '
      'note TEXT, actor_name TEXT, created_at INTEGER)',
    );
    await db.customStatement('DROP TABLE inventory');
    await db.customStatement(
      'CREATE TABLE inventory ('
      'id TEXT NOT NULL PRIMARY KEY, name TEXT, sku TEXT, barcode TEXT, '
      'category TEXT, subcategory TEXT, size TEXT, description TEXT, '
      'price REAL, hsn_code TEXT, gst_rate REAL, price_includes_tax INTEGER, '
      'stock REAL, source_meta TEXT, image_path TEXT, unit TEXT, '
      'reorder_level INTEGER, variant_group_id TEXT, variant_label TEXT, '
      'created_at INTEGER, updated_at INTEGER, tombstone INTEGER DEFAULT 0)',
    );
  });
  tearDown(() async => db.close());

  group('stock movements', () {
    test('a NULL note does not take down the stream', () async {
      await db.customStatement(
        "INSERT INTO stock_movements "
        "(id, item_id, item_name, delta, reason, note, created_at) "
        "VALUES ('mv-1', 'i-1', 'Woolen Caps', -2, 'SALE', NULL, 1000)",
      );

      final movements = await InventoryRepository(
        db,
      ).watchStockMovements().first;

      expect(movements, hasLength(1));
      expect(movements.first.note, '');
      expect(movements.first.itemName, 'Woolen Caps');
    });

    test('NULLs across every optional column still map', () async {
      await db.customStatement(
        "INSERT INTO stock_movements "
        "(id, item_id, item_name, delta, reason, note, actor_name, ref_id, "
        " balance_after, created_at) "
        "VALUES ('mv-2', 'i-1', 'Cap', -1, 'ADJUST', NULL, NULL, NULL, NULL, 2000)",
      );

      final movements = await InventoryRepository(
        db,
      ).watchStockMovements().first;
      expect(movements, hasLength(1));
      expect(movements.first.actorName, equals(null));
      expect(movements.first.balanceAfter, equals(null));
    });

    test('one bad row does not hide the good ones', () async {
      // The real damage: a single NULL used to kill the whole query, so a
      // shopkeeper lost the entire history, not one line of it.
      await db.customStatement(
        "INSERT INTO stock_movements "
        "(id, item_id, item_name, delta, reason, note, created_at) "
        "VALUES ('mv-good', 'i-1', 'Good', -1, 'SALE', 'fine', 3000)",
      );
      await db.customStatement(
        "INSERT INTO stock_movements "
        "(id, item_id, item_name, delta, reason, note, created_at) "
        "VALUES ('mv-null', 'i-1', 'Null note', -1, 'SALE', NULL, 4000)",
      );

      final movements = await InventoryRepository(
        db,
      ).watchStockMovements().first;
      expect(movements, hasLength(2));
    });
  });

  group('the exact flow that crashed', () {
    test(
      'logStockAdjustment completes while the stream is being watched',
      () async {
        final inventory = InventoryRepository(db);

        // A movement with a NULL note already in the table — exactly the state a
        // shop reaches through older rows.
        await db.customStatement(
          "INSERT INTO stock_movements "
          "(id, item_id, item_name, delta, reason, note, created_at) "
          "VALUES ('mv-old', 'i-1', 'Woolen Caps', -1, 'SALE', NULL, 1000)",
        );

        // Watch it, the way the stock-history screen does.
        final seen = <int>[];
        final sub = inventory.watchStockMovements().listen(
          (rows) => seen.add(rows.length),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Restock: this is the call that used to blow up via the stream it wakes.
        await inventory.logStockAdjustment(
          itemId: 'i-1',
          itemName: 'Woolen Caps',
          oldStock: 10,
          newStock: 25,
          note: 'Restocked +15',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();

        expect(seen.last, 2, reason: 'the new movement should be visible');
      },
    );
  });

  group('inventory catalog', () {
    test('an item row full of NULLs still lists', () async {
      await db.customStatement(
        "INSERT INTO inventory "
        "(id, name, price, category, gst_rate, price_includes_tax, stock, "
        " created_at, updated_at, tombstone) "
        "VALUES ('i-9', 'Bare Item', 0, NULL, NULL, NULL, NULL, 1000, 1000, 0)",
      );

      final items = await InventoryRepository(
        db,
      ).watchCatalogPage(page: 1, pageSize: 50).first;

      expect(items, hasLength(1));
      expect(items.first.name, 'Bare Item');
      expect(items.first.category, 'General');
      expect(items.first.stock, 0);
    });
  });
}
