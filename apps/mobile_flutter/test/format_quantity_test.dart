import 'package:business_hub_mobile/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

// Lifted out of pos_screen_v3.dart, where it lived as a private `_fmtQty` with
// no test. Quantity is what the till multiplies a price by, so it earns one.
void main() {
  group('formatQuantity', () {
    test('a counted item loses the decimal', () {
      expect(formatQuantity(3), '3');
      expect(formatQuantity(3.0), '3');
      expect(formatQuantity(1), '1');
    });

    test('a weighed item keeps its fraction', () {
      expect(formatQuantity(1.5), '1.5');
      expect(formatQuantity(0.25), '0.25');
    });

    test('zero is zero, not an empty string', () {
      expect(formatQuantity(0), '0');
    });

    test('a dozen is twelve, not twelve point zero', () {
      // The till once billed three dozen as three. Whatever the pack maths
      // resolves to, the number shown next to it must read as a whole count.
      expect(formatQuantity(36), '36');
    });

    test('a returned line can be negative', () {
      expect(formatQuantity(-2), '-2');
      expect(formatQuantity(-0.5), '-0.5');
    });
  });
}
