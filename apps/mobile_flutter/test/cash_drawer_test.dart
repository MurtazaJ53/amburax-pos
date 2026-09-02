import 'package:business_hub_mobile/core/printer/receipt_printer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cashDrawerKickBytes', () {
    test('default kick is ESC p on pin 2 (0x1B 0x70 0x00 0x19 0xFA)', () {
      expect(cashDrawerKickBytes(), <int>[0x1B, 0x70, 0x00, 0x19, 0xFA]);
    });

    test('supports drawer pin 5 and custom pulse timing', () {
      expect(cashDrawerKickBytes(pin: 1, onTime: 50, offTime: 100), <int>[
        0x1B,
        0x70,
        0x01,
        0x32,
        0x64,
      ]);
    });

    test('clamps timing bytes into a single byte', () {
      final bytes = cashDrawerKickBytes(onTime: 300, offTime: 300);
      expect(bytes[3], 300 & 0xFF);
      expect(bytes[4], 300 & 0xFF);
    });
  });
}
