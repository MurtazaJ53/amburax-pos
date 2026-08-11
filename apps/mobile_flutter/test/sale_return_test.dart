import 'package:business_hub_mobile/features/history/presentation/sale_return_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules that decide what a return is worth and whether it may be sent.
///
/// These matter more than most UI logic because the counter acts on them in
/// front of a customer: a wrong refund total is money handed over, and a
/// missing guard is stock created out of nothing.
ReturnableLine _line({
  String id = 'a',
  double sold = 4,
  double returned = 0,
  double price = 100,
}) =>
    ReturnableLine(
      saleItemId: id,
      name: 'Cotton Shirt',
      size: 'M',
      sold: sold,
      returned: returned,
      returnable: sold - returned,
      unitPrice: price,
    );

void main() {
  group('parseAmount', () {
    test('reads the JSON strings DRF sends for decimals', () {
      // DecimalField serialises as a string. Treating "2.500" as zero would
      // silently refund nothing.
      expect(parseAmount('2.500'), 2.5);
      expect(parseAmount(3), 3.0);
      expect(parseAmount(null), 0);
      expect(parseAmount('not a number'), 0);
    });
  });

  group('refundTotal', () {
    test('charges the price recorded on the bill, per unit returned', () {
      final lines = <ReturnableLine>[
        _line(id: 'a', price: 100),
        _line(id: 'b', price: 250),
      ];
      expect(refundTotal(lines, <String, double>{'a': 2, 'b': 1}, 'CASH'), 450);
    });

    test('an exchange refunds nothing', () {
      // The value carries into the replacement bill. Paying it out as well
      // would give the goods away, so this is worth pinning.
      final lines = <ReturnableLine>[_line(price: 100)];
      expect(refundTotal(lines, <String, double>{'a': 2}, 'EXCHANGE'), 0);
    });

    test('ignores lines nothing was chosen from', () {
      final lines = <ReturnableLine>[_line(id: 'a'), _line(id: 'b')];
      expect(refundTotal(lines, <String, double>{'a': 1}, 'CASH'), 100);
    });
  });

  group('returnBlocker', () {
    test('nothing chosen cannot be sent', () {
      expect(
        returnBlocker(
          lines: <ReturnableLine>[_line()],
          quantities: const <String, double>{},
          refundMode: 'CASH',
          hasCustomer: true,
        ),
        isNotNull,
      );
    });

    test('a valid selection is allowed', () {
      expect(
        returnBlocker(
          lines: <ReturnableLine>[_line(sold: 4)],
          quantities: const <String, double>{'a': 4},
          refundMode: 'CASH',
          hasCustomer: false,
        ),
        isNull,
      );
    });

    test('refuses more than is left after an earlier return', () {
      // Sold 4, two already came back. Allowing 3 would put stock on the
      // shelf that was never sold and refund money twice for one shirt.
      final blocker = returnBlocker(
        lines: <ReturnableLine>[_line(sold: 4, returned: 2)],
        quantities: const <String, double>{'a': 3},
        refundMode: 'CASH',
        hasCustomer: true,
      );
      expect(blocker, isNotNull);
      expect(blocker, contains('only 2 left'));
    });

    test('refuses khata on a bill with no customer', () {
      expect(
        returnBlocker(
          lines: <ReturnableLine>[_line()],
          quantities: const <String, double>{'a': 1},
          refundMode: 'KHATA',
          hasCustomer: false,
        ),
        contains('no khata'),
      );
    });

    test('allows khata when the bill has a customer', () {
      expect(
        returnBlocker(
          lines: <ReturnableLine>[_line()],
          quantities: const <String, double>{'a': 1},
          refundMode: 'KHATA',
          hasCustomer: true,
        ),
        isNull,
      );
    });
  });

  group('refund modes', () {
    test('every offered mode is one the server accepts', () {
      // The server rejects an unknown refund_mode outright, so a chip the
      // backend has never heard of fails only after the customer is told yes.
      const serverModes = <String>{
        'CASH',
        'UPI',
        'BANK',
        'CARD',
        'KHATA',
        'EXCHANGE',
      };
      for (final mode in kRefundModes) {
        expect(serverModes, contains(mode.value));
      }
    });
  });
}
