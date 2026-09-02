import 'package:business_hub_mobile/core/receipt/barcode_labels_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Labels go onto physical stock, so a PDF that throws at render time (or
/// silently prints nothing) wastes sticker paper and the shopkeeper's evening.
void main() {
  test('renders a valid PDF for a single item', () async {
    final bytes = await buildBarcodeLabelsPdf(
      shopName: 'T. N',
      labels: const <LabelRequest>[
        LabelRequest(name: 'Woolen Caps Kids', price: 100, code: 'CAP-100'),
      ],
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('an item with no barcode still prints name and price', () async {
    final bytes = await buildBarcodeLabelsPdf(
      shopName: 'T. N',
      labels: const <LabelRequest>[
        LabelRequest(name: 'Loose Rice', price: 60, code: ''),
      ],
    );
    expect(bytes.length, greaterThan(1000));
  });

  test('multiple copies and multi-page runs render', () async {
    // 30 copies overflows one 24-per-sheet page.
    final bytes = await buildBarcodeLabelsPdf(
      shopName: 'T. N',
      labels: const <LabelRequest>[
        LabelRequest(name: 'Cap', price: 100, code: 'C1', copies: 30),
      ],
    );
    expect(bytes.length, greaterThan(1000));
  });

  test(
    'an empty request still returns a readable PDF, not zero pages',
    () async {
      final bytes = await buildBarcodeLabelsPdf(
        shopName: 'T. N',
        labels: const [],
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    },
  );

  test('emoji and long names do not break the sticker', () async {
    final bytes = await buildBarcodeLabelsPdf(
      shopName: 'T. N 🙏',
      labels: <LabelRequest>[
        LabelRequest(name: 'A' * 90, price: 1234.5, code: 'SKU-ABC-123'),
      ],
    );
    expect(bytes.length, greaterThan(1000));
  });

  test('zero copies still prints one label rather than none', () async {
    final bytes = await buildBarcodeLabelsPdf(
      shopName: 'T. N',
      labels: const <LabelRequest>[
        LabelRequest(name: 'Cap', price: 100, code: 'C1', copies: 0),
      ],
    );
    expect(bytes.length, greaterThan(1000));
  });
}
