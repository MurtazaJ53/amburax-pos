import 'package:flutter_test/flutter_test.dart';

import 'package:business_hub_mobile/core/checkout/checkout_policy.dart';

void main() {
  group('resolveCheckoutPayments', () {
    test('accepts a standard single payment within total', () {
      final result = resolveCheckoutPayments(
        paymentMode: 'CASH',
        total: 1200,
        collectedAmount: 1200,
        splitPayments: const <CheckoutPaymentEntry>[],
      );

      expect(result, isNotNull);
      expect(result!.payments.length, 1);
      expect(result.payments.first.mode, 'CASH');
      expect(result.payments.first.amount, 1200);
      expect(result.totalCollected, 1200);
      expect(result.amountDueFor(1200), 0);
    });

    test('rejects single payment above total', () {
      final result = resolveCheckoutPayments(
        paymentMode: 'UPI',
        total: 900,
        collectedAmount: 950,
        splitPayments: const <CheckoutPaymentEntry>[],
      );

      expect(result, isNull);
    });

    test('accepts valid split payments and preserves due', () {
      final result = resolveCheckoutPayments(
        paymentMode: 'SPLIT',
        total: 1500,
        collectedAmount: 0,
        splitPayments: const <CheckoutPaymentEntry>[
          CheckoutPaymentEntry(mode: 'CASH', amount: 600),
          CheckoutPaymentEntry(mode: 'UPI', amount: 500),
        ],
      );

      expect(result, isNotNull);
      expect(result!.payments.length, 2);
      expect(result.totalCollected, 1100);
      expect(result.amountDueFor(1500), 400);
    });

    test('rejects split payments with non-positive line', () {
      final result = resolveCheckoutPayments(
        paymentMode: 'SPLIT',
        total: 1500,
        collectedAmount: 0,
        splitPayments: const <CheckoutPaymentEntry>[
          CheckoutPaymentEntry(mode: 'CASH', amount: 0),
          CheckoutPaymentEntry(mode: 'UPI', amount: 500),
        ],
      );

      expect(result, isNull);
    });

    test('rejects split payments above total', () {
      final result = resolveCheckoutPayments(
        paymentMode: 'SPLIT',
        total: 1500,
        collectedAmount: 0,
        splitPayments: const <CheckoutPaymentEntry>[
          CheckoutPaymentEntry(mode: 'CASH', amount: 900),
          CheckoutPaymentEntry(mode: 'UPI', amount: 700),
        ],
      );

      expect(result, isNull);
    });
  });

  group('shouldConfirmCreditExposure', () {
    test(
      'requires confirmation only when existing due and new due both exist',
      () {
        expect(
          shouldConfirmCreditExposure(currentBalance: 500, additionalDue: 200),
          isTrue,
        );
        expect(
          shouldConfirmCreditExposure(currentBalance: 0, additionalDue: 200),
          isFalse,
        );
        expect(
          shouldConfirmCreditExposure(currentBalance: 500, additionalDue: 0),
          isFalse,
        );
      },
    );
  });

  group('resolveCashierTender (cash change must not inflate collections)', () {
    test(
      'GOLDEN: Rs.500 cash on a Rs.300 bill records Rs.300, change Rs.200',
      () {
        final r = resolveCashierTender(
          total: 300,
          lines: const [CheckoutPaymentEntry(mode: 'CASH', amount: 500)],
        );
        expect(r.payments.length, 1);
        expect(r.payments.first.mode, 'CASH');
        expect(r.payments.first.amount, 300); // capped at the bill
        expect(r.change, 200); // handed back, never recorded
        expect(r.totalCollected, 300); // <= total, backend-safe
        expect(r.overcharged, isFalse);
        expect(r.dueFor(300), 0);
        expect(paymentModeFor(r.payments), 'CASH');
      },
    );

    test('exact cash: no change, no due', () {
      final r = resolveCashierTender(
        total: 300,
        lines: const [CheckoutPaymentEntry(mode: 'CASH', amount: 300)],
      );
      expect(r.totalCollected, 300);
      expect(r.change, 0);
      expect(r.dueFor(300), 0);
    });

    test('cash underpayment leaves a due (khata), no change', () {
      final r = resolveCashierTender(
        total: 300,
        lines: const [CheckoutPaymentEntry(mode: 'CASH', amount: 200)],
      );
      expect(r.totalCollected, 200);
      expect(r.dueFor(300), 100);
      expect(r.change, 0);
    });

    test('split CARD + CASH exactly covering the bill', () {
      final r = resolveCashierTender(
        total: 300,
        lines: const [
          CheckoutPaymentEntry(mode: 'CARD', amount: 100),
          CheckoutPaymentEntry(mode: 'CASH', amount: 200),
        ],
      );
      expect(r.totalCollected, 300);
      expect(r.change, 0);
      expect(paymentModeFor(r.payments), 'SPLIT');
    });

    test('card over the bill is flagged and capped (no change on card)', () {
      final r = resolveCashierTender(
        total: 300,
        lines: const [CheckoutPaymentEntry(mode: 'CARD', amount: 500)],
      );
      expect(r.overcharged, isTrue);
      expect(r.totalCollected, 300); // capped, never > total
      expect(r.change, 0);
    });

    test(
      'card partial + excess cash gives change only on the cash surplus',
      () {
        final r = resolveCashierTender(
          total: 300,
          lines: const [
            CheckoutPaymentEntry(mode: 'CARD', amount: 200),
            CheckoutPaymentEntry(mode: 'CASH', amount: 200),
          ],
        );
        expect(r.totalCollected, 300); // 200 card + 100 cash
        expect(r.change, 100); // cash surplus
        expect(r.overcharged, isFalse);
      },
    );

    test('no tender at all resolves to a full-credit sale', () {
      final r = resolveCashierTender(total: 300, lines: const []);
      expect(r.payments, isEmpty);
      expect(r.dueFor(300), 300);
      expect(paymentModeFor(r.payments), 'CREDIT');
    });
  });
}
