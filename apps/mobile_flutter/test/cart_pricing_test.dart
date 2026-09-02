import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/pos/cart_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

PosCartItem _item({double price = 100, double qty = 1}) => PosCartItem(
  id: 'i',
  name: 'x',
  price: price,
  quantity: qty,
  stock: 100,
  category: 'c',
);

void _originalTests() {
  group('subtotal', () {
    test('sums line totals', () {
      expect(
        CartPricing.subtotal([_item(price: 100, qty: 2), _item(price: 50)]),
        250,
      );
    });
    test('empty cart is zero', () {
      expect(CartPricing.subtotal(const <PosCartItem>[]), 0);
    });
  });

  group('discountAmount', () {
    test('fixed rupees', () {
      expect(
        CartPricing.discountAmount(subtotal: 200, value: 50, isPercent: false),
        50,
      );
    });
    test('percent', () {
      expect(
        CartPricing.discountAmount(subtotal: 200, value: 10, isPercent: true),
        20,
      );
    });
    test('never exceeds subtotal', () {
      expect(
        CartPricing.discountAmount(subtotal: 100, value: 500, isPercent: false),
        100,
      );
    });
    test('negative is ignored', () {
      expect(
        CartPricing.discountAmount(subtotal: 100, value: -5, isPercent: false),
        0,
      );
    });
    test('zero subtotal yields zero', () {
      expect(
        CartPricing.discountAmount(subtotal: 0, value: 10, isPercent: true),
        0,
      );
    });
  });

  group('net', () {
    test('subtracts discount', () {
      expect(CartPricing.net(subtotal: 200, discount: 50), 150);
    });
    test('never negative', () {
      expect(CartPricing.net(subtotal: 50, discount: 100), 0);
    });
  });

  group('paid / due / change', () {
    test('paid sums payment lines', () {
      expect(
        CartPricing.paid(const [
          PosPayment(mode: 'CASH', amount: 40),
          PosPayment(mode: 'UPI', amount: 60),
        ]),
        100,
      );
    });
    test('due when underpaid (credit)', () {
      expect(CartPricing.due(net: 100, paid: 60), 40);
    });
    test('no due when paid in full', () {
      expect(CartPricing.due(net: 100, paid: 100), 0);
    });
    test('change when overpaid', () {
      expect(CartPricing.change(net: 100, paid: 130), 30);
    });
    test('no change on exact payment', () {
      expect(CartPricing.change(net: 100, paid: 100), 0);
    });
  });

  test('end-to-end: split payment with discount leaves correct due', () {
    final cart = [_item(price: 500, qty: 2)]; // 1000
    final subtotal = CartPricing.subtotal(cart);
    final discount = CartPricing.discountAmount(
      subtotal: subtotal,
      value: 10,
      isPercent: true,
    ); // 100
    final net = CartPricing.net(subtotal: subtotal, discount: discount); // 900
    final paid = CartPricing.paid(const [
      PosPayment(mode: 'CASH', amount: 400),
      PosPayment(mode: 'CARD', amount: 300),
    ]); // 700
    expect(net, 900);
    expect(CartPricing.due(net: net, paid: paid), 200);
    expect(CartPricing.change(net: net, paid: paid), 0);
  });
}

/// Regression for the reported bug: 3 x Rs.100 with Rs.100 off one line showed
/// Rs.200 at checkout, but the sale recorded total Rs.300 with a Rs.100 "due".
/// The cart must net the per-item discount out of the subtotal so the phone and
/// the server agree on what the customer owes.
void _perItemDiscountTests() {
  group('per-item discount', () {
    PosCartItem line({double discount = 0}) => PosCartItem(
      id: 'w',
      name: 'Woolen Caps Kids',
      price: 100,
      quantity: 1,
      stock: 100,
      category: 'c',
      discount: discount,
    );

    test('reduces the cart subtotal', () {
      expect(CartPricing.subtotal([line(discount: 100), line(), line()]), 200);
    });

    test('is capped at the line total and never goes negative', () {
      final capped = line(discount: 500);
      expect(capped.effectiveDiscount, 100);
      expect(capped.lineTotal, 0);
      expect(CartPricing.subtotal([capped]), 0);
    });

    test('a negative discount is ignored', () {
      expect(line(discount: -50).lineTotal, 100);
    });

    test(
      'travels to the backend payload so the server nets the same total',
      () {
        final json = line(discount: 100).toSaleJson();
        expect(json['discount'], 100);
        expect(json['price'], 100);
      },
    );
  });
}

void main() {
  _originalTests();
  _perItemDiscountTests();
}
