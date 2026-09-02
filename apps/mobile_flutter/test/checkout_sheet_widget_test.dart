import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/tax/gst.dart';
import 'package:business_hub_mobile/core/theme/app_colors.dart';
import 'package:business_hub_mobile/features/pos/presentation/checkout_payment_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _gst = GstCartSummary(
  taxableAmount: 300,
  taxAmount: 0,
  cgstAmount: 0,
  sgstAmount: 0,
  igstAmount: 0,
  grossAmount: 300,
);

void main() {
  testWidgets(
    'GOLDEN: Rs.500 cash on a Rs.300 bill records Rs.300 (not Rs.500)',
    (tester) async {
      Map<String, dynamic>? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showModalBottomSheet<Map<String, dynamic>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const CheckoutPaymentSheet(
                        cartTotal: 300,
                        gstSummary: _gst,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Cashier tenders Rs.500 in the (first) cash amount field.
      await tester.enterText(find.byType(TextField).first, '500');
      await tester.pumpAndSettle();

      // Change of Rs.200 must be shown to the cashier...
      expect(find.text('Change'), findsOneWidget);

      // ...and the button still completes the sale (no due).
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      final payments = (captured!['payments'] as List).cast<PosPayment>();
      final recorded = payments.fold<double>(0, (s, p) => s + p.amount);
      expect(recorded, 300); // NOT 500 — the change is not collected money
      expect(captured!['paymentMode'], 'CASH');
    },
  );
}
