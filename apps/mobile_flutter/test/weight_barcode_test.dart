import 'package:business_hub_mobile/core/pos/weight_barcode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWeightBarcode (standard config)', () {
    test('decodes a price-embedded scale barcode', () {
      // 2 | 12345 | 001250 | 8  -> PLU 12345, price 12.50
      final b = parseWeightBarcode('2123450012508');
      expect(b, isNotNull);
      expect(b!.itemCode, '12345');
      expect(b.embeddedValue, closeTo(12.50, 0.001));
    });

    test('returns null for a normal (non-prefixed) barcode', () {
      expect(parseWeightBarcode('8901234567890'), isNull);
    });

    test('returns null for the wrong length', () {
      expect(parseWeightBarcode('212345001250'), isNull); // 12 digits
    });

    test('returns null for non-numeric input', () {
      expect(parseWeightBarcode('2ABCDE0012508'), isNull);
    });

    test('respects a custom config (rupees, not paise)', () {
      const config = WeightBarcodeConfig(valueDivisor: 1);
      final b = parseWeightBarcode('2123450012508', config: config);
      expect(b!.embeddedValue, closeTo(1250, 0.001));
    });
  });

  group('parseWeightBarcode (weight config)', () {
    test('decodes a weight-embedded scale barcode (grams -> kg)', () {
      // 2 | 12345 | 001500 | c  -> PLU 12345, weight 1.500 kg
      final b = parseWeightBarcode(
        '2123450015000',
        config: WeightBarcodeConfig.weightStandard,
      );
      expect(b, isNotNull);
      expect(b!.itemCode, '12345');
      expect(b.isWeight, isTrue);
      expect(b.embeddedValue, closeTo(1.5, 0.001));
    });

    test('resolveLinePrice charges rate x weight for a weight barcode', () {
      final b = parseWeightBarcode(
        '2123450015000',
        config: WeightBarcodeConfig.weightStandard,
      );
      // 1.5 kg at Rs.40/kg = Rs.60.
      expect(b!.resolveLinePrice(40), closeTo(60, 0.001));
    });

    test(
      'resolveLinePrice charges the embedded amount for a price barcode',
      () {
        final b = parseWeightBarcode('2123450012508');
        // Price barcode ignores the item rate and charges the embedded value.
        expect(b!.isWeight, isFalse);
        expect(b.resolveLinePrice(999), closeTo(12.50, 0.001));
      },
    );
  });

  group('weighedLinePrice', () {
    test('1.5 kg at Rs.60/kg = Rs.90', () {
      expect(weighedLinePrice(rate: 60, weight: 1.5), 90);
    });

    test('rounds to paise', () {
      expect(weighedLinePrice(rate: 33.33, weight: 0.25), closeTo(8.33, 0.001));
    });

    test('non-positive inputs yield zero', () {
      expect(weighedLinePrice(rate: 0, weight: 2), 0);
      expect(weighedLinePrice(rate: 60, weight: 0), 0);
    });
  });
}
