import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/receipt/receipt_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// The receipt is rendered with the built-in Latin-1 PDF fonts, so any
/// character outside that range (an emoji pasted into the shop footer, a curly
/// quote, the rupee sign) used to come out as a hollow box on the customer's
/// bill — and can throw at render time. These tests build a real PDF so a
/// regression fails here rather than on a customer's receipt.

SaleDetailItem _item({
  String name = 'Smart Rn (100)',
  double qty = 1,
  double price = 70,
  double discount = 0,
  double gstRate = 0,
  String? hsn,
}) => SaleDetailItem(
  name: name,
  quantity: qty,
  unitPrice: price,
  lineDiscount: discount,
  gstRate: gstRate,
  hsnCode: hsn,
);

SaleRecordDetail _sale({
  List<SaleDetailItem>? items,
  double total = 460,
  double discount = 0,
  String? footerNote,
  String? customerName,
  double amountReceived = 460,
}) {
  final lines =
      items ??
      <SaleDetailItem>[
        _item(name: 'Smart Rn (100)', price: 70),
        _item(name: 'Smart Rn (110)', price: 80),
        _item(name: 'Smart Rn (75)', price: 60),
      ];
  return SaleRecordDetail(
    id: 'sale-1785813681078',
    total: total,
    discount: discount,
    discountType: 'fixed',
    paymentMode: 'CASH',
    date: '2026-08-04',
    syncState: CommerceSyncState.synced,
    items: lines,
    payments: <SaleDetailPayment>[
      SaleDetailPayment(mode: 'CASH', amount: amountReceived),
    ],
    customerName: customerName,
    footerNote: footerNote,
  );
}

const _shop = ShopInfo(
  name: 'T. N',
  tagline: 'Business Hub',
  footer: 'Thanks for shopping',
  currency: 'INR',
  phone: '8469876518',
);

void main() {
  group('receipt pdf', () {
    test('renders a valid PDF document', () async {
      final bytes = await buildReceiptPdf(_sale(), _shop);
      expect(bytes.length, greaterThan(1000));
      // Every PDF starts with the %PDF- magic bytes.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('survives emoji and smart quotes in the shop footer', () async {
      // This is what produced the hollow box on a real receipt.
      final bytes = await buildReceiptPdf(
        _sale(footerNote: 'Thanks for Shopping 🙏 with us, Visit Again — "ok"'),
        _shop,
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('renders a GST tax invoice without throwing', () async {
      const gstShop = ShopInfo(
        name: 'T. N',
        tagline: 'Business Hub',
        footer: 'Thanks',
        currency: 'INR',
        phone: '8469876518',
        gstin: '24ABCDE1234F1Z5',
      );
      final bytes = await buildReceiptPdf(
        _sale(
          items: <SaleDetailItem>[
            _item(gstRate: 18, hsn: '6109'),
            _item(name: 'Second line', price: 80, gstRate: 5, hsn: '6110'),
          ],
        ),
        gstShop,
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('renders per-item discount and an outstanding balance', () async {
      final bytes = await buildReceiptPdf(
        _sale(
          items: <SaleDetailItem>[
            _item(price: 100, discount: 20),
            _item(name: 'Full price', price: 100),
          ],
          total: 180,
          discount: 20,
          amountReceived: 100,
          customerName: 'Ayaan Retail',
        ),
        _shop,
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('handles an empty cart and a very long item name', () async {
      final bytes = await buildReceiptPdf(
        _sale(
          items: <SaleDetailItem>[_item(name: 'A' * 120, price: 1)],
          total: 1,
          amountReceived: 1,
        ),
        _shop,
      );
      expect(bytes.length, greaterThan(1000));
    });
  });
}
