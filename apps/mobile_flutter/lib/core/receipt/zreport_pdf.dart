import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/mobile_models.dart';
import '../utils/formatters.dart';

String _money(num value) => formatCurrency(value).replaceAll('₹', 'Rs ');

String _time(DateTime? dt) => dt == null
    ? '—'
    : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

pw.Widget _row(String label, String value, {bool bold = false}) {
  final style = pw.TextStyle(
    fontSize: 9,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(label, style: style),
        pw.Text(value, style: style),
      ],
    ),
  );
}

pw.Widget _divider() => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3),
  child: pw.Divider(height: 1, thickness: 0.5),
);

/// Build an 80mm end-of-day Z-report PDF: opening float, tender split,
/// discounts, tax, and the cash reconciliation.
Future<Uint8List> buildZReportPdf({
  required ZReportSnapshot z,
  required ShopInfo shop,
  required String dateLabel,
  required double openingFloat,
  double? countedCash,
}) async {
  final doc = pw.Document();
  final expectedCash = openingFloat + z.cashCollected;
  final variance = countedCash == null ? null : countedCash - expectedCash;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
      margin: const pw.EdgeInsets.all(10),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Center(
            child: pw.Text(
              shop.name.isEmpty ? 'Business Hub' : shop.name,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'Z-REPORT · DAY CLOSE',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text(dateLabel, style: const pw.TextStyle(fontSize: 8)),
          ),
          _divider(),
          _row('Bills', '${z.salesCount}'),
          _row('First bill', _time(z.firstBillAt)),
          _row('Last bill', _time(z.lastBillAt)),
          _divider(),
          _row('Gross sales', _money(z.grossSales), bold: true),
          _row('Discounts given', _money(z.discountTotal)),
          _row('Tax collected', _money(z.taxCollected)),
          _row('Collected', _money(z.collected)),
          _row('Outstanding (credit)', _money(z.due)),
          _divider(),
          pw.Text(
            'TENDER BREAKDOWN',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          if (z.tenderBreakdown.isEmpty)
            _row('No payments', _money(0))
          else
            ...(z.tenderBreakdown.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .map((e) => _row(e.key, _money(e.value))),
          _divider(),
          pw.Text(
            'CASH RECONCILIATION',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          _row('Opening float', _money(openingFloat)),
          _row('+ Cash sales', _money(z.cashCollected)),
          _row('= Expected in drawer', _money(expectedCash), bold: true),
          if (countedCash != null) _row('Counted', _money(countedCash)),
          if (variance != null)
            _row(
              variance.abs() < 0.01
                  ? 'Variance (matched)'
                  : variance > 0
                  ? 'Variance (over)'
                  : 'Variance (short)',
              _money(variance.abs()),
              bold: true,
            ),
          _divider(),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'Generated ${DateTime.now()}',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
