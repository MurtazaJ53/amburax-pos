import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone and the website must value the same shelf the same way.
///
/// This report is computed twice — the website asks the server, the counter app
/// works it out from its own database — so the two implementations can drift
/// without anything failing. They did: the server treats a stored 0.00 cost as
/// "not recorded" and falls back to the sell price, and the phone took it
/// literally and valued the item at nothing.
///
/// That is not a rounding difference. It sorted the worst offenders to the
/// bottom of the list, hiding exactly what the report exists to surface.
DeadStockItem item({double stock = 10, double price = 500, double? cost}) =>
    DeadStockItem(
      id: 'i1',
      name: 'Cotton Shirt',
      category: 'General',
      stock: stock,
      price: price,
      costPrice: cost,
    );

void main() {
  group('tiedUpValue', () {
    test('uses the cost price when one is recorded', () {
      expect(item(stock: 10, price: 500, cost: 300).tiedUpValue, 3000);
    });

    test('falls back to the sell price when cost is missing', () {
      expect(item(stock: 10, price: 500, cost: null).tiedUpValue, 5000);
    });

    test('treats a stored zero as not recorded, not as free', () {
      // The case the two platforms disagreed on. Valuing this at 0 put the
      // item last in a list ordered by money at stake, so a shop whose cost
      // prices were imported as 0.00 saw an empty-looking report.
      expect(item(stock: 10, price: 500, cost: 0).tiedUpValue, 5000);
    });

    test('a negative cost is not recorded either', () {
      expect(item(stock: 10, price: 500, cost: -1).tiedUpValue, 5000);
    });

    test('nothing on the shelf is worth nothing, whatever it cost', () {
      expect(item(stock: 0, price: 500, cost: 300).tiedUpValue, 0);
    });
  });

  group('ordering', () {
    test('an item with a zero cost is not sorted below a cheaper one', () {
      // The visible symptom: a 500-rupee item with no usable cost price
      // ranking under a 50-rupee one, because 0 sorts last.
      final rows = <DeadStockItem>[
        item(stock: 10, price: 500, cost: 0),
        item(stock: 10, price: 50, cost: 50),
      ]..sort((a, b) => b.tiedUpValue.compareTo(a.tiedUpValue));

      expect(rows.first.tiedUpValue, 5000);
    });
  });
}
