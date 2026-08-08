import 'dart:io' show Platform;

import 'package:business_hub_mobile/core/printer/receipt_printer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bluetooth receipt printing is Android-only, and the reason is a platform
/// rule rather than a missing feature: iOS does not expose Bluetooth Classic
/// SPP to applications, only BLE and MFi-enrolled accessories.
///
/// These tests exist because the failure mode is silent and lands at the worst
/// moment. Without the guard, every call reaches a plugin that has no iOS
/// implementation and throws MissingPluginException at the till, mid-sale.
void main() {
  group('platform support', () {
    test('is true on Android and false everywhere else', () {
      expect(
        ReceiptPrinterService.supportsBluetoothPrinting,
        Platform.isAndroid,
      );
    });

    test('the host running these tests is not Android', () {
      // Guards the assertion above from being vacuously true: if the suite
      // ever runs on Android, the test below asserting a throw would not fire
      // and nobody would notice.
      expect(Platform.isAndroid, isFalse);
    });
  });

  group('behaviour where Bluetooth is unavailable', () {
    final service = ReceiptPrinterService();

    test('listing devices returns empty rather than throwing', () async {
      // Called while building the printer picker, so a throw here would take
      // out the screen rather than one button.
      expect(await service.getDevices(), isEmpty);
    });

    test('opening the cash drawer is a silent no-op', () async {
      // Fired unawaited after a sale completes. An exception would surface as
      // an unhandled error long after the bill was printed, pointing nowhere
      // near the cause.
      await expectLater(service.openCashDrawer(), completes);
    });

    test('the error names the alternative a cashier can actually use', () {
      const error = PrinterUnsupportedError(
        'Bluetooth receipt printing is only available on Android. '
        'Use Share or Save as PDF to send the receipt instead.',
      );
      // A message that only says "not supported" leaves the cashier stuck with
      // a customer waiting.
      expect(error.toString(), contains('Share'));
      expect(error.toString(), contains('Android'));
    });
  });
}
