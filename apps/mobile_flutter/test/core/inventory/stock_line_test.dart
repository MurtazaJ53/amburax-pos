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
      expect(
        stockCaption(stock: 0, unit: 'kg'),
        'Shelf empty — still sellable',
      );
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

  group('an item that has never been stocked', () {
    test('says so rather than claiming the shelf is empty', () {
      // Zero here is an absence of information, not an empty shelf. The web
      // makes the same distinction; a shop viewed on both must not be told
      // two different things.
      expect(stockCaption(stock: 0, isTracked: false), 'Stock not tracked');
      expect(stockCaption(stock: 0), 'Shelf empty — still sellable');
    });

    test('the message holds whatever the meaningless count happens to be', () {
      expect(stockCaption(stock: 12, isTracked: false), 'Stock not tracked');
      expect(stockCaption(stock: -4, isTracked: false), 'Stock not tracked');
    });

    test('gets no badge, because there is nothing to be alarmed about', () {
      expect(stockBadge(stock: 0, reorderLevel: 10, isTracked: false), isNull);
      expect(stockBadge(stock: -4, reorderLevel: 10, isTracked: false), isNull);
    });
  });

  group('stockBadge', () {
    test('a well-stocked item gets no badge at all', () {
      expect(stockBadge(stock: 343, reorderLevel: 10), isNull);
    });

    test('at or below the reorder level it says how many are left', () {
      expect(stockBadge(stock: 5, reorderLevel: 10), (
        label: '5 left',
        level: StockLevel.low,
      ));
      // At the threshold, not merely under it — the reorder level is the
      // point at which the shopkeeper should already be acting.
      expect(stockBadge(stock: 10, reorderLevel: 10), (
        label: '10 left',
        level: StockLevel.low,
      ));
    });

    test('the item respects its own threshold, not a global one', () {
      expect(stockBadge(stock: 20, reorderLevel: 50)?.level, StockLevel.low);
      expect(stockBadge(stock: 20, reorderLevel: 2), isNull);
    });

    test('empty and short are distinct states', () {
      expect(stockBadge(stock: 0, reorderLevel: 10), (
        label: 'Shelf empty',
        level: StockLevel.empty,
      ));
      expect(stockBadge(stock: -4, reorderLevel: 10), (
        label: 'Short 4',
        level: StockLevel.short,
      ));
    });

    test('short outranks the reorder level', () {
      // Negative stock is below any threshold, so order matters: it must not
      // be reported as merely low.
      expect(stockBadge(stock: -1, reorderLevel: 100)?.level, StockLevel.short);
    });
  });

  group('catalogueScopeNotice', () {
    test('says nothing when the whole catalogue is on screen', () {
      expect(
        catalogueScopeNotice(shown: 50, total: 50, searching: false),
        isNull,
      );
      // Fewer rows than the page size is the ordinary small-shop case.
      expect(
        catalogueScopeNotice(shown: 50, total: 12, searching: false),
        isNull,
      );
    });

    test('browsing a large shop reports progress, not a wall', () {
      // The grid grows as the operator scrolls, so this says how big the shop
      // is and that more is coming. It must not imply the rest is
      // unreachable — that was true before paging and is not true now.
      expect(
        catalogueScopeNotice(shown: 50, total: 5000, searching: false),
        'Showing 50 of 5000 · keep scrolling, or search to jump straight to '
        'an item',
      );
    });

    test('the count follows the window as it grows', () {
      expect(
        catalogueScopeNotice(shown: 250, total: 5000, searching: false),
        startsWith('Showing 250 of 5000'),
      );
      // And goes away entirely once the window has caught up.
      expect(
        catalogueScopeNotice(shown: 5000, total: 5000, searching: false),
        isNull,
      );
    });

    test('searching gets different advice, because search sees everything', () {
      // The local catalogue is complete and search is a LIKE over every row,
      // so nothing is unreachable. The useful advice is to narrow the search,
      // and the web's warning that products may be unfindable would be untrue
      // on this device.
      final notice = catalogueScopeNotice(
        shown: 50,
        total: 300,
        searching: true,
      );
      expect(
        notice,
        'Showing 50 of 300 matches · keep scrolling, or narrow the search',
      );
      expect(notice, isNot(contains('scan')));
    });

    test('a search that fits needs no notice either', () {
      expect(
        catalogueScopeNotice(shown: 50, total: 8, searching: true),
        isNull,
      );
    });
  });

  group('shouldGrowWindow', () {
    bool grow({
      double pixels = 5000,
      double maxScrollExtent = 5000,
      int loaded = 50,
      int windowSize = 50,
      int total = 5000,
    }) {
      return shouldGrowWindow(
        pixels: pixels,
        maxScrollExtent: maxScrollExtent,
        loaded: loaded,
        windowSize: windowSize,
        total: total,
      );
    }

    test('grows when the operator nears the end of a full window', () {
      expect(grow(), isTrue);
      expect(grow(pixels: 4300), isTrue, reason: 'inside the 800px runway');
    });

    test('does not grow while the operator is still far up the list', () {
      expect(grow(pixels: 1000), isFalse);
      expect(grow(pixels: 4199), isFalse, reason: 'outside the runway');
    });

    test('does not grow while the previous fetch is still in flight', () {
      // The condition that stops runaway growth. Scroll notifications fire
      // many times a second and the query answering them is asynchronous, so
      // without this the limit walks up in leaps and asks for thousands of
      // rows to fill one screen.
      expect(grow(loaded: 30, windowSize: 50), isFalse);
      expect(grow(loaded: 49, windowSize: 50), isFalse);
      expect(grow(loaded: 50, windowSize: 50), isTrue);
    });

    test('stops once everything is loaded', () {
      expect(grow(loaded: 5000, windowSize: 5000, total: 5000), isFalse);
      // And never asks past the end even if the counts disagree briefly.
      expect(grow(loaded: 5010, windowSize: 5000, total: 5000), isFalse);
    });

    test('a shop that fits on one screen never grows', () {
      expect(
        grow(
          loaded: 12,
          windowSize: 50,
          total: 12,
          pixels: 0,
          maxScrollExtent: 0,
        ),
        isFalse,
      );
    });
  });
}
