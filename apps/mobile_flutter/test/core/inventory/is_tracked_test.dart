import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// `has_stock_history` arrives from the backend as a nullable bool, and the
/// null is the interesting case: it means "this server did not say", which is
/// not the same as "never stocked".
///
/// The web already made the mistake this guards against and left a comment
/// about it — defaulting the missing field to false made every row on an
/// older server read "Stock not tracked", including one holding 462 units.
/// The mobile rule has to match the web's, because both read one backend and
/// a shopkeeper checking the same item on a phone and a laptop must not be
/// told two different things.
InventoryCatalogItem _item({required double stock, bool? hasStockHistory}) {
  return InventoryCatalogItem(
    id: 'sku-1',
    name: 'A Gents Socks',
    price: 80,
    category: 'Socks',
    stock: stock,
    createdAt: DateTime(2026, 1, 1),
    hasStockHistory: hasStockHistory,
  );
}

void main() {
  group('when the server has spoken, believe it', () {
    test('true is tracked, whatever the count says', () {
      expect(_item(stock: 0, hasStockHistory: true).isTracked, isTrue);
      expect(_item(stock: -4, hasStockHistory: true).isTracked, isTrue);
      expect(_item(stock: 462, hasStockHistory: true).isTracked, isTrue);
    });

    test('false is untracked even when a count is sitting there', () {
      // An imported row can carry an opening figure nobody ever booked in.
      // The server knows that and we do not second-guess it.
      expect(_item(stock: 100, hasStockHistory: false).isTracked, isFalse);
      expect(_item(stock: 0, hasStockHistory: false).isTracked, isFalse);
    });
  });

  group('when the server is silent, infer from the count', () {
    test('a non-zero balance is proof of history', () {
      // A balance cannot exist without a stock movement behind it. This is
      // the case the web got wrong by defaulting to false: 462 units on the
      // shelf, labelled "Stock not tracked".
      expect(_item(stock: 462).isTracked, isTrue);
      expect(_item(stock: 1.5).isTracked, isTrue);
    });

    test('a negative balance is also proof of history', () {
      // Something was sold that was never booked in. Movement happened.
      expect(_item(stock: -3).isTracked, isTrue);
    });

    test('only a zero stays genuinely unknown', () {
      // Nobody has told us anything and nothing can be inferred, so the
      // honest answer is that the figure means nothing.
      expect(_item(stock: 0).isTracked, isFalse);
    });
  });

  test('null is not false', () {
    // The whole point of the nullable column. If these two ever agree, the
    // ambiguity the field exists to remove has been collapsed again.
    expect(
      _item(stock: 462).isTracked,
      isNot(_item(stock: 462, hasStockHistory: false).isTracked),
    );
  });
}
