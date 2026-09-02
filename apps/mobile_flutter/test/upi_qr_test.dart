import 'package:business_hub_mobile/core/pos/upi_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildUpiUri', () {
    test('builds a upi://pay link with the exact amount and merchant VPA', () {
      final uri = buildUpiUri(
        payeeVpa: 'demomart@okhdfcbank',
        payeeName: 'Demo Mart',
        amount: 249.5,
        note: 'Bill S-1024',
        transactionRef: 'S1024',
      );
      final parsed = Uri.parse(uri);
      expect(parsed.scheme, 'upi');
      expect(parsed.host, 'pay');
      expect(parsed.queryParameters['pa'], 'demomart@okhdfcbank');
      expect(parsed.queryParameters['pn'], 'Demo Mart');
      expect(parsed.queryParameters['am'], '249.50');
      expect(parsed.queryParameters['cu'], 'INR');
      expect(parsed.queryParameters['tn'], 'Bill S-1024');
      expect(parsed.queryParameters['tr'], 'S1024');
    });

    test('formats amount to two decimals', () {
      expect(formatUpiAmount(90), '90.00');
      expect(formatUpiAmount(12.3), '12.30');
    });

    test('rejects an invalid VPA', () {
      expect(
        () => buildUpiUri(payeeVpa: 'not-a-vpa', payeeName: 'X', amount: 10),
        throwsA(isA<UpiRequestError>()),
      );
    });

    test('rejects a non-positive amount', () {
      expect(
        () => buildUpiUri(payeeVpa: 'a@bank', payeeName: 'X', amount: 0),
        throwsA(isA<UpiRequestError>()),
      );
    });

    test('receiptUpiUri builds a pay link for the balance due', () {
      final uri = receiptUpiUri(
        shopName: 'Demo Mart',
        amountDue: 340,
        vpa: 'demomart@okhdfcbank',
      );
      expect(uri, isNotNull);
      expect(Uri.parse(uri!).queryParameters['am'], '340.00');
      expect(Uri.parse(uri).queryParameters['pa'], 'demomart@okhdfcbank');
    });

    test('receiptUpiUri is null when nothing is due or no VPA configured', () {
      expect(receiptUpiUri(shopName: 'X', amountDue: 0, vpa: 'a@bank'), isNull);
      expect(receiptUpiUri(shopName: 'X', amountDue: 100, vpa: ''), isNull);
      // A misconfigured VPA must not break receipt printing.
      expect(
        receiptUpiUri(shopName: 'X', amountDue: 100, vpa: 'bad-vpa'),
        isNull,
      );
    });

    test('omits optional note/ref when empty', () {
      final uri = buildUpiUri(payeeVpa: 'a@bank', payeeName: 'X', amount: 5);
      final parsed = Uri.parse(uri);
      expect(parsed.queryParameters.containsKey('tn'), isFalse);
      expect(parsed.queryParameters.containsKey('tr'), isFalse);
    });
  });
}
