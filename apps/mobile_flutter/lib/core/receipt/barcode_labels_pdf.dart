import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/formatters.dart';

/// A label to print: what goes on the sticker, and how many copies.
class LabelRequest {
  const LabelRequest({
    required this.name,
    required this.price,
    this.code = '',
    this.size,
    this.copies = 1,
  });

  final String name;
  final double price;

  /// SKU or barcode. When empty the label prints without a barcode rather than
  /// rendering a meaningless one.
  final String code;
  final String? size;
  final int copies;
}

/// Base PDF fonts are Latin-1 only, so strip anything they can't draw instead
/// of printing hollow boxes onto a sticker that goes on the shelf.
String _safe(String input) {
  final buffer = StringBuffer();
  for (final rune in input.replaceAll('₹', 'Rs ').runes) {
    if (rune >= 0x20 && rune <= 0xFF) buffer.writeCharCode(rune);
  }
  return buffer.toString().trim();
}

String _money(num value) => formatCurrency(value).replaceAll('₹', 'Rs ');

/// Build a printable A4 sheet of price/barcode labels, 3 columns x 8 rows.
///
/// Sized for the common 63.5 x 33.9 mm (24-per-sheet) sticker paper sold in
/// Indian stationery shops, so the output lines up with paper people can
/// actually buy. Falls back gracefully when an item has no barcode.
Future<Uint8List> buildBarcodeLabelsPdf({
  required List<LabelRequest> labels,
  required String shopName,
  bool showShopName = true,
}) async {
  final doc = pw.Document();

  // Expand copies into individual labels so a request for 10 of one item fills
  // the sheet correctly.
  final cells = <LabelRequest>[];
  for (final label in labels) {
    final copies = label.copies < 1 ? 1 : label.copies;
    for (var i = 0; i < copies; i++) {
      cells.add(label);
    }
  }
  if (cells.isEmpty) {
    // Never hand back a zero-page PDF — printers and viewers handle it badly.
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Center(child: pw.Text('No labels selected.')),
      ),
    );
    return doc.save();
  }

  const columns = 3;
  const rows = 8;
  const perPage = columns * rows;

  for (var start = 0; start < cells.length; start += perPage) {
    final pageCells = cells.sublist(
      start,
      (start + perPage).clamp(0, cells.length),
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: 8 * PdfPageFormat.mm,
          vertical: 12 * PdfPageFormat.mm,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              for (var row = 0; row < rows; row++)
                pw.Expanded(
                  child: pw.Row(
                    children: <pw.Widget>[
                      for (var col = 0; col < columns; col++)
                        pw.Expanded(
                          child: () {
                            final index = row * columns + col;
                            if (index >= pageCells.length) {
                              return pw.SizedBox();
                            }
                            return _label(
                              pageCells[index],
                              shopName,
                              showShopName: showShopName,
                            );
                          }(),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  return doc.save();
}

pw.Widget _label(
  LabelRequest label,
  String shopName, {
  required bool showShopName,
}) {
  final code = label.code.trim();
  final size = (label.size ?? '').trim();
  return pw.Container(
    margin: const pw.EdgeInsets.all(2),
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
    ),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        if (showShopName && shopName.trim().isNotEmpty)
          pw.Text(
            _safe(shopName).toUpperCase(),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700),
          ),
        pw.Text(
          _safe(label.name),
          maxLines: 2,
          textAlign: pw.TextAlign.center,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        ),
        if (size.isNotEmpty)
          pw.Text(
            _safe(size),
            style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
          ),
        pw.SizedBox(height: 1),
        pw.Text(
          _money(label.price),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        if (code.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 2),
          pw.BarcodeWidget(
            // Code128 encodes any alphanumeric SKU, unlike EAN-13 which would
            // reject most shop-assigned codes outright.
            barcode: pw.Barcode.code128(),
            data: _safe(code),
            width: 90,
            height: 18,
            drawText: true,
            textStyle: const pw.TextStyle(fontSize: 5),
          ),
        ],
      ],
    ),
  );
}
