import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../models/mobile_models.dart';
import '../pos/upi_qr.dart';

/// Thrown instead of a bare MissingPluginException when Bluetooth printing is
/// asked for on a platform that cannot do it.
class PrinterUnsupportedError implements Exception {
  const PrinterUnsupportedError(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReceiptPrinterService {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  /// Whether this device can drive a Bluetooth thermal printer at all.
  ///
  /// `blue_thermal_printer` speaks Bluetooth Classic SPP, which iOS does not
  /// expose to apps — Apple only permits BLE, or accessories enrolled in the
  /// MFi programme. So the plugin is Android-only, and on iOS every call would
  /// otherwise fail with a bare MissingPluginException at the till.
  ///
  /// Callers should check this before offering a "print" action rather than
  /// catching the failure afterwards: a cashier finding out at the counter is
  /// the worst possible moment.
  static bool get supportsBluetoothPrinting => Platform.isAndroid;

  /// Guard every entry point that touches the plugin.
  void _requireBluetooth() {
    if (!supportsBluetoothPrinting) {
      throw const PrinterUnsupportedError(
        'Bluetooth receipt printing is only available on Android. '
        'Use Share or Save as PDF to send the receipt instead.',
      );
    }
  }

  Future<List<BluetoothDevice>> getDevices() async {
    if (!supportsBluetoothPrinting) return const <BluetoothDevice>[];
    return await bluetooth.getBondedDevices();
  }

  Future<void> connect(BluetoothDevice device) async {
    _requireBluetooth();
    await bluetooth.connect(device);
  }

  Future<void> disconnect() async {
    if (!supportsBluetoothPrinting) return;
    await bluetooth.disconnect();
  }

  Future<void> printTaxInvoice(SaleRecordDetail detail, ShopInfo shop) async {
    _requireBluetooth();
    final bool? isConnected = await bluetooth.isConnected;
    if (isConnected != true) {
      throw Exception('Printer is not connected.');
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // Header
    final isB2b = detail.footerNote?.contains('Buyer GSTIN:') == true;
    bytes += generator.text(
      isB2b ? 'TAX INVOICE' : 'RECEIPT',
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      linesAfter: 1,
    );

    bytes += generator.text(
      shop.name,
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    // Removing unsupported ShopInfo address and stateCode
    bytes += generator.emptyLines(1);
    bytes += generator.text('Date: ${detail.date}');
    bytes += generator.text(
      'Customer: ${detail.customerName?.isNotEmpty == true ? detail.customerName : 'Walk-in'}',
    );

    // Parse buyer GSTIN from footerNote
    if (isB2b) {
      final parts = detail.footerNote!.split('Buyer GSTIN:');
      if (parts.length > 1) {
        final buyerGstin = parts[1].trim();
        bytes += generator.text('Buyer GSTIN: $buyerGstin');
      }
    }

    bytes += generator.emptyLines(1);

    // Items Header
    bytes += generator.row([
      PosColumn(text: 'Item', width: 6),
      PosColumn(text: 'Qty', width: 2),
      PosColumn(
        text: 'Total',
        width: 4,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += generator.hr();

    // Items
    for (final item in detail.items) {
      bytes += generator.row([
        PosColumn(text: item.name, width: 6),
        PosColumn(text: item.quantity.toString(), width: 2),
        PosColumn(
          text: item.lineTotal.toStringAsFixed(2),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (item.gstRate > 0) {
        bytes += generator.row([
          PosColumn(
            text: ' GST ${item.gstRate}%',
            width: 6,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(text: '', width: 2),
          PosColumn(
            text: item.taxAmount.toStringAsFixed(2),
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }
    }
    bytes += generator.hr();

    // Totals
    // Totals
    var totalTaxable = 0.0;
    var totalCgst = 0.0;
    var totalSgst = 0.0;
    var totalIgst = 0.0;
    for (final item in detail.items) {
      totalTaxable += item.taxableAmount;
      totalCgst += item.cgstAmount;
      totalSgst += item.sgstAmount;
      totalIgst += item.igstAmount;
    }
    final hasTax = (totalCgst + totalSgst + totalIgst) > 0.009;

    bytes += generator.row([
      PosColumn(
        text: 'Subtotal:',
        width: 8,
        styles: const PosStyles(align: PosAlign.right),
      ),
      PosColumn(
        text: detail.total.toStringAsFixed(2),
        width: 4,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    if (hasTax) {
      bytes += generator.row([
        PosColumn(
          text: 'Taxable:',
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: totalTaxable.toStringAsFixed(2),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'CGST/SGST:',
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text:
              '${totalCgst.toStringAsFixed(2)}/${totalSgst.toStringAsFixed(2)}',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if (totalIgst > 0) {
        bytes += generator.row([
          PosColumn(
            text: 'IGST:',
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: totalIgst.toStringAsFixed(2),
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }
    }

    bytes += generator.hr();
    bytes += generator.row([
      PosColumn(
        text: 'TOTAL DUE:',
        width: 8,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
      PosColumn(
        text: detail.amountDue.toStringAsFixed(2),
        width: 4,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);

    // UPI pay QR on the paper bill: the customer can clear the balance straight
    // from the receipt. Omitted when nothing is due or no merchant VPA is set.
    final payUri = receiptUpiUri(
      shopName: shop.name,
      amountDue: detail.amountDue,
    );
    if (payUri != null) {
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        'Scan to pay via UPI',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.qrcode(payUri);
    }

    bytes += generator.emptyLines(1);
    // Use the shop's own closing message (Business settings) so paper and PDF
    // receipts say the same thing, instead of a hardcoded line.
    final closing = shop.footer.trim();
    if (closing.isNotEmpty) {
      bytes += generator.text(
        closing,
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    bytes += generator.text(
      'Powered by Amburax',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(2);

    bluetooth.writeBytes(Uint8List.fromList(bytes));
  }

  /// Send the ESC/POS cash-drawer kick pulse to a drawer wired to the printer's
  /// RJ11 port. No-op if no printer is connected. Verify the pulse pin/timing
  /// against your drawer if it doesn't open.
  Future<void> openCashDrawer() async {
    // Silent no-op rather than a throw: this is fired unawaited after a sale
    // completes, so an exception here would surface as an unhandled error long
    // after the bill was already printed.
    if (!supportsBluetoothPrinting) return;
    final isConnected = await bluetooth.isConnected ?? false;
    if (!isConnected) return;
    bluetooth.writeBytes(Uint8List.fromList(cashDrawerKickBytes()));
  }
}

/// ESC/POS "generate pulse" command for an RJ11-connected cash drawer:
/// `ESC p m t1 t2` = `0x1B 0x70 <pin> <onTime> <offTime>`. Times are in 2 ms
/// units per the ESC/POS spec, so the defaults are ~50 ms on / ~500 ms off on
/// drawer pin 2. Swap [pin] to 1 if your drawer is wired to pin 5.
List<int> cashDrawerKickBytes({
  int pin = 0,
  int onTime = 25,
  int offTime = 250,
}) {
  assert(pin == 0 || pin == 1, 'Drawer pin must be 0 (pin 2) or 1 (pin 5).');
  return <int>[0x1B, 0x70, pin, onTime & 0xFF, offTime & 0xFF];
}
