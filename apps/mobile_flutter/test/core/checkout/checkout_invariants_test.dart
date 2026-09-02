import 'package:flutter_test/flutter_test.dart';
import 'package:business_hub_mobile/core/checkout/checkout_policy.dart';

void main() {
  group('Checkout Financial Invariants', () {
    test(
      'Invariant: totalCollected + due == total for all positive tenders',
      () {
        final billTotals = [100.0, 250.0, 499.0, 1000.0, 15750.0];
        final tenderedAmounts = [
          0.0,
          50.0,
          100.0,
          250.0,
          500.0,
          1000.0,
          20000.0,
        ];

        for (final total in billTotals) {
          for (final tender in tenderedAmounts) {
            final result = resolveCashierTender(
              total: total,
              lines: [CheckoutPaymentEntry(mode: 'CASH', amount: tender)],
            );

            // Invariant 1: Total collected + amount due must equal bill total
            expect(
              result.totalCollected + result.dueFor(total),
              equals(total),
              reason: 'Failed for bill=$total, tender=$tender',
            );

            // Invariant 2: Total collected never exceeds bill total
            expect(
              result.totalCollected,
              lessThanOrEqualTo(total),
              reason:
                  'totalCollected exceeded bill for bill=$total, tender=$tender',
            );

            // Invariant 3: Change returned must equal surplus cash
            if (tender > total) {
              expect(result.change, equals(tender - total));
            } else {
              expect(result.change, equals(0.0));
            }
          }
        }
      },
    );

    test('Invariant: Multi-mode tender split conservation', () {
      const total = 1000.0;
      final upiAmounts = [0.0, 200.0, 500.0, 800.0, 1000.0];
      final cashAmounts = [0.0, 200.0, 500.0, 800.0, 1000.0];

      for (final upi in upiAmounts) {
        for (final cash in cashAmounts) {
          final lines = <CheckoutPaymentEntry>[];
          if (upi > 0) {
            lines.add(CheckoutPaymentEntry(mode: 'UPI', amount: upi));
          }
          if (cash > 0) {
            lines.add(CheckoutPaymentEntry(mode: 'CASH', amount: cash));
          }

          final result = resolveCashierTender(total: total, lines: lines);

          expect(
            result.totalCollected + result.dueFor(total),
            equals(total),
            reason: 'Split invariant failed for upi=$upi, cash=$cash',
          );
        }
      }
    });

    test('Invariant: Payment mode categorization is consistent', () {
      final resCredit = resolveCashierTender(total: 100.0, lines: const []);
      expect(paymentModeFor(resCredit.payments), equals('CREDIT'));

      final resCash = resolveCashierTender(
        total: 100.0,
        lines: const [CheckoutPaymentEntry(mode: 'CASH', amount: 100.0)],
      );
      expect(paymentModeFor(resCash.payments), equals('CASH'));

      final resUpi = resolveCashierTender(
        total: 100.0,
        lines: const [CheckoutPaymentEntry(mode: 'UPI', amount: 100.0)],
      );
      expect(paymentModeFor(resUpi.payments), equals('UPI'));

      final resSplit = resolveCashierTender(
        total: 100.0,
        lines: const [
          CheckoutPaymentEntry(mode: 'CASH', amount: 50.0),
          CheckoutPaymentEntry(mode: 'UPI', amount: 50.0),
        ],
      );
      expect(paymentModeFor(resSplit.payments), equals('SPLIT'));
    });
  });
}
