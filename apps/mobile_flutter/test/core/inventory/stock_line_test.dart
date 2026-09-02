import 'package:business_hub_mobile/core/inventory/stock_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wording is the contract. A shopkeeper who checks the same item on the
/// web and on the phone must not be told two different things about it, so
/// these tests pin the exact strings the web renders, not merely the shape.
void main() {
  group('stockCaption', () {
    test('a counted item reads as a plain figure', () {
      expect(stockCaption(stock: 343), '343 in stock');
      expect(stockCaption(stock: 3041), '3041 in stock');
    });

    test('a unit replaces the words when the item has one', () {
      expect(stockCaption(stock: 1.5, unit: 'kg'), '1.5 kg');
      expect(stockCaption(stock: 12, unit: 'pcs'), '12 pcs');
    });

    test('an empty or blank unit falls back to the words', () {
      expect(stockCaption(stock: 4, unit: ''), '4 in stock');
      expect(stockCaption(stock: 4, unit: '   '), '4 in stock');
    });

    test('zero is sellable, not blocked', () {
      // The shelf count can drift below what is physically there. A shopkeeper
      // holding the item still has to be able to sell it.
      expect(stockCaption(stock: 0), 'Shelf empty — still sellable');
      expect(stockCaption(stock: 0, unit: 'kg'), 'Shelf empty — still sellable');
    });

    test('negative stock says where to fix it, not how many', () {
      // A negative count means the books and the shelf already disagree, and
      // the till is the wrong place to reconcile it.
      expect(stockCaption(stock: -3), 'Short by 3 — fix in Stock');
      expect(stockCaption(stock: -0.5), 'Short by 0.5 — fix in Stock');
    });

    test('a whole number never shows a decimal', () {
      expect(stockCaption(stock: 12.0), '12 in stock');
    });
  });

  group('stockBadge', () {
    test('a well-stocked item gets no badge at all', () {
      expect(stockBadge(stock: 343, reorderLevel: 10), isNull);
    });

    test('at or below the reorder level it says how many are left', () {
      expect(
        stockBadge(stock: 5, reorderLevel: 10),
        (label: '5 left', level: StockLevel.low),
      );
      // At the threshold, not merely under it — the reorder level is the
      // point at which the shopkeeper should already be acting.
      expect(
        stockBadge(stock: 10, reorderLevel: 10),
        (label: '10 left', level: StockLevel.low),
      );
    });

    test('the item respects its own threshold, not a global one', () {
      expect(stockBadge(stock: 20, reorderLevel: 50)?.level, StockLevel.low);
      expect(stockBadge(stock: 20, reorderLevel: 2), isNull);
    });

    test('empty and short are distinct states', () {
      expect(
        stockBadge(stock: 0, reorderLevel: 10),
        (label: 'Shelf empty', level: StockLevel.empty),
      );
      expect(
        stockBadge(stock: -4, reorderLevel: 10),
        (label: 'Short 4', level: StockLevel.short),
      );
    });

    test('short outranks the reorder level', () {
      // Negative stock is below any threshold, so order matters: it must not
      // be reported as merely low.
      expect(stockBadge(stock: -1, reorderLevel: 100)?.level, StockLevel.short);
    });
  });
}
