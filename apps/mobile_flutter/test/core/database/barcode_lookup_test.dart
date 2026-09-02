import 'package:business_hub_mobile/core/database/local_database.dart';
import 'package:business_hub_mobile/core/database/mobile_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scanning is the primary way a product reaches the cart, and it was broken
/// in two ways at once.
///
/// The till matched the scanned code against `items` — the list the grid had
/// already loaded, fifty rows in a shop of five thousand — so scanning
/// anything not already on screen silently found nothing. And it compared the
/// code to the SKU only, while `barcode` is a separate column on the backend
/// that the phone did not store at all, so a product whose printed barcode
/// differs from its shop code could never be scanned.
///
/// These tests go through the real repository against a real database,
/// because the bug was in the query rather than in any logic above it.
void main() {
  late BusinessHubDatabase db;
  late InventoryRepository inventory;

  setUp(() {
    db = BusinessHubDatabase.forTesting(NativeDatabase.memory());
    inventory = InventoryRepository(db);
  });
  tearDown(() async => db.close());

  Future<void> addItem({
    required String id,
    required String name,
    String? sku,
    String? barcode,
  }) {
    return db.customStatement(
      'INSERT INTO inventory '
      '(id, name, price, sku, barcode, category, stock, created_at, '
      'updated_at, tombstone) '
      "VALUES (?, ?, 80.0, ?, ?, 'Socks', 12.0, 0, 0, 0)",
      <Object?>[id, name, sku, barcode],
    );
  }

  group('scanning finds the product', () {
    test('by the barcode printed on the packet', () async {
      await addItem(
        id: 'p1',
        name: 'A Gents Socks',
        sku: '1512',
        barcode: '8901234567890',
      );

      final found = await inventory.findByExactLookup(
        '8901234567890',
        includeCost: false,
      );

      expect(found, isNotNull);
      expect(found!.name, 'A Gents Socks');
      expect(found.barcode, '8901234567890');
      expect(
        found.sku,
        '1512',
        reason: 'The shop code and the printed code are different things.',
      );
    });

    test('by the shop own SKU, which still has to work', () async {
      await addItem(
        id: 'p1',
        name: 'A Gents Socks',
        sku: '1512',
        barcode: '8901234567890',
      );

      final found = await inventory.findByExactLookup(
        '1512',
        includeCost: false,
      );

      expect(found?.id, 'p1');
    });

    test('when it is nowhere near the loaded page', () async {
      // The original failure. Fifty tiles are on screen; the scanned item is
      // far past them. A lookup that searches the loaded list finds nothing;
      // one that asks the database finds it.
      for (var i = 0; i < 200; i++) {
        await addItem(
          id: 'p$i',
          name: 'Filler $i',
          sku: 'sku-$i',
          barcode: 'bar-$i',
        );
      }

      final found = await inventory.findByExactLookup(
        'bar-199',
        includeCost: false,
      );

      expect(found?.name, 'Filler 199');
    });

    test('is case insensitive, because scanners and typists differ', () async {
      await addItem(id: 'p1', name: 'Socks', barcode: 'AB-99x');

      expect(
        (await inventory.findByExactLookup('ab-99X', includeCost: false))?.id,
        'p1',
      );
    });

    test('an unknown code finds nothing rather than the wrong thing', () async {
      await addItem(id: 'p1', name: 'Socks', sku: '1512', barcode: '890');

      expect(
        await inventory.findByExactLookup('nope', includeCost: false),
        isNull,
      );
    });

    test('a partial code is not a match — exact means exact', () async {
      // The catalogue search does substring matching; a scan must not.
      // Charging a customer for a neighbouring product because its barcode
      // shares a prefix is worse than reporting no match.
      await addItem(id: 'p1', name: 'Socks', barcode: '8901234567890');

      expect(
        await inventory.findByExactLookup('890123', includeCost: false),
        isNull,
      );
    });
  });

  group('typing a code into the search box', () {
    test('matches the barcode as well as the name and SKU', () async {
      await addItem(
        id: 'p1',
        name: 'A Gents Socks',
        sku: '1512',
        barcode: '8901234567890',
      );
      await addItem(id: 'p2', name: 'A Kids Socks', sku: '1513');

      final byBarcode = await inventory
          .watchCatalogPage(search: '8901234567890')
          .first;

      expect(byBarcode, hasLength(1));
      expect(byBarcode.single.id, 'p1');
    });

    test('the barcode reaches the tile, not only the query', () async {
      // The column has to be selected, not merely stored: a mapper reading a
      // column the query never asked for returns null and loses it silently.
      await addItem(id: 'p1', name: 'Socks', barcode: '8901234567890');

      final page = await inventory.watchCatalogPage().first;

      expect(page.single.barcode, '8901234567890');
    });
  });
}
