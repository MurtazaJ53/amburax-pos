import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/tax/gst.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splits inclusive intra-state GST into CGST and SGST', () {
    final gst = computeLineGst(
      lineTotal: 118,
      gstRate: 18,
      priceIncludesTax: true,
      intraState: true,
    );

    expect(gst.taxableAmount, 100);
    expect(gst.taxAmount, 18);
    expect(gst.cgstAmount, 9);
    expect(gst.sgstAmount, 9);
    expect(gst.igstAmount, 0);
    expect(gst.grossAmount, 118);
  });

  test('uses IGST for exclusive inter-state GST', () {
    final gst = computeLineGst(
      lineTotal: 100,
      gstRate: 18,
      priceIncludesTax: false,
      intraState: false,
    );

    expect(gst.taxableAmount, 100);
    expect(gst.taxAmount, 18);
    expect(gst.cgstAmount, 0);
    expect(gst.sgstAmount, 0);
    expect(gst.igstAmount, 18);
    expect(gst.grossAmount, 118);
  });

  test('passes through zero rated lines', () {
    final gst = computeLineGst(
      lineTotal: 250,
      gstRate: 0,
      priceIncludesTax: true,
      intraState: true,
    );

    expect(gst.taxableAmount, 250);
    expect(gst.taxAmount, 0);
    expect(gst.grossAmount, 250);
  });

  test('rounds inclusive decimal tax consistently', () {
    final gst = computeLineGst(
      lineTotal: 99,
      gstRate: 5,
      priceIncludesTax: true,
      intraState: true,
    );

    expect(gst.taxableAmount, 94.29);
    expect(gst.taxAmount, 4.71);
    expect(gst.cgstAmount, 2.36);
    expect(gst.sgstAmount, 2.35);
  });

  test('summarizes cart tax from POS items', () {
    final summary = computeCartGst(const <PosCartItem>[
      PosCartItem(
        id: 'a',
        name: 'Taxed inclusive',
        price: 118,
        quantity: 1,
        stock: 10,
        category: 'General',
        gstRate: 18,
      ),
      PosCartItem(
        id: 'b',
        name: 'Zero rated',
        price: 50,
        quantity: 2,
        stock: 10,
        category: 'General',
      ),
    ]);

    expect(summary.taxableAmount, 200);
    expect(summary.taxAmount, 18);
    expect(summary.grossAmount, 218);
    expect(summary.hasTax, isTrue);
  });
}
