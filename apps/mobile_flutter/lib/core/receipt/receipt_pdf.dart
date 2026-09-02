import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/mobile_models.dart';
import '../pos/upi_qr.dart';
import '../tax/gst.dart';
import '../utils/formatters.dart';

// Brand palette, kept in step with the app's primary blue.
const PdfColor _brand = PdfColor.fromInt(0xFF0EA5E9);
const PdfColor _ink = PdfColor.fromInt(0xFF0F172A);
const PdfColor _muted = PdfColor.fromInt(0xFF64748B);
const PdfColor _line = PdfColor.fromInt(0xFFE2E8F0);
const PdfColor _zebra = PdfColor.fromInt(0xFFF8FAFC);
const PdfColor _good = PdfColor.fromInt(0xFF059669);
const PdfColor _warn = PdfColor.fromInt(0xFFDC2626);

/// The built-in PDF fonts are Latin-1 only, so anything outside that range
/// (emoji, curly quotes, the rupee sign) renders as a hollow box. Strip those
/// characters and map the ones with a sensible ASCII equivalent, so a stray
/// emoji in the shop's footer can never disfigure a customer's receipt.
String _safe(String input) {
  const replacements = <String, String>{
    '₹': 'Rs ', // rupee
    '‘': "'", '’': "'",
    '“': '"', '”': '"',
    '–': '-', '—': '-',
    '…': '...',
    ' ': ' ',
  };
  var text = input;
  replacements.forEach((from, to) => text = text.replaceAll(from, to));
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    // Keep printable Latin-1 plus newline/tab; drop everything else.
    if (rune == 0x0A || rune == 0x09 || (rune >= 0x20 && rune <= 0xFF)) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
}

/// Rupee sign isn't in the base PDF font, so render amounts with "Rs ".
String _money(num value) => formatCurrency(value).replaceAll('₹', 'Rs ');

pw.Widget _totalRow(
  String label,
  String value, {
  bool bold = false,
  bool big = false,
  PdfColor? color,
}) {
  final style = pw.TextStyle(
    fontSize: big ? 13 : 9,
    fontWeight: bold || big ? pw.FontWeight.bold : pw.FontWeight.normal,
    color: color ?? (bold || big ? _ink : _muted),
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Text(_safe(label), style: style),
        pw.Text(value, style: style),
      ],
    ),
  );
}

pw.Widget _metaRow(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 1),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.SizedBox(
        width: 52,
        child: pw.Text(
          _safe(label),
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          _safe(value),
          style: pw.TextStyle(
            fontSize: 7.5,
            color: _ink,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    ],
  ),
);

/// Build an 80mm receipt PDF. When the shop has a GSTIN it is rendered as a
/// GST **tax invoice** (per-item HSN + taxable + tax, and a CGST/SGST/IGST
/// summary); otherwise a plain receipt.
Future<Uint8List> buildReceiptPdf(
  SaleRecordDetail detail,
  ShopInfo shop,
) async {
  final doc = pw.Document();
  final format = PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 0,
  );

  final rawFooter = detail.footerNote ?? '';
  final buyerMatch = RegExp(
    r'Buyer GSTIN:\s*([0-9A-Za-z]+)',
  ).firstMatch(rawFooter);
  final buyerGstin = buyerMatch?.group(1);
  final footer = _safe(
    rawFooter.replaceAll(RegExp(r'\n*\s*Buyer GSTIN:.*'), '').trim(),
  );

  final isTaxInvoice = shop.hasGstin;
  // Same-state supply assumed (CGST+SGST). A cross-state IGST split would
  // compare the buyer/seller GSTIN state codes.
  const intraState = true;

  var taxable = 0.0;
  var cgst = 0.0;
  var sgst = 0.0;
  var totalTax = 0.0;
  for (final it in detail.items) {
    final line = computeLineGst(
      lineTotal: it.unitPrice * it.quantity,
      gstRate: it.gstRate,
      priceIncludesTax: it.priceIncludesTax,
      intraState: intraState,
    );
    taxable += line.taxableAmount;
    cgst += line.cgstAmount;
    sgst += line.sgstAmount;
    totalTax += line.taxAmount;
  }

  final upiUri = receiptUpiUri(
    shopName: shop.name,
    amountDue: detail.amountDue,
  );
  final totalQty = detail.items.fold<double>(0, (sum, it) => sum + it.quantity);

  doc.addPage(
    pw.Page(
      pageFormat: format,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: <pw.Widget>[
            // ---- Header band -------------------------------------------
            pw.Container(
              width: double.infinity,
              color: _brand,
              padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: pw.Column(
                children: <pw.Widget>[
                  pw.Text(
                    _safe(shop.name).toUpperCase(),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                  if (shop.tagline.trim().isNotEmpty) ...<pw.Widget>[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      _safe(shop.tagline),
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                  if (shop.phone.trim().isNotEmpty) ...<pw.Widget>[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Ph: ${_safe(shop.phone)}',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                  if (isTaxInvoice) ...<pw.Widget>[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'GSTIN: ${_safe(shop.gstin)}',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ---- Document type badge ------------------------------------
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              color: _ink,
              child: pw.Text(
                isTaxInvoice ? 'TAX INVOICE' : 'RECEIPT',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  letterSpacing: 2.4,
                ),
              ),
            ),
            // ---- Meta ---------------------------------------------------
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: <pw.Widget>[
                  _metaRow('Invoice', detail.id),
                  _metaRow('Date', detail.date),
                  if ((detail.customerName ?? '').trim().isNotEmpty)
                    _metaRow('Customer', detail.customerName!),
                  if ((detail.customerPhone ?? '').trim().isNotEmpty)
                    _metaRow('Mobile', detail.customerPhone!),
                  if (buyerGstin != null) _metaRow('Buyer GST', buyerGstin),
                  _metaRow('Payment', detail.paymentMode),
                ],
              ),
            ),
            // ---- Item table header --------------------------------------
            pw.Container(
              color: _ink,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              child: pw.Row(
                children: <pw.Widget>[
                  pw.Expanded(
                    child: pw.Text(
                      'ITEM',
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  pw.Text(
                    'AMOUNT',
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            // ---- Items --------------------------------------------------
            for (var i = 0; i < detail.items.length; i++)
              pw.Container(
                color: i.isEven ? _zebra : PdfColors.white,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: <pw.Widget>[
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.Expanded(
                          child: pw.Text(
                            _safe(detail.items[i].name),
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                        ),
                        pw.Text(
                          _money(
                            detail.items[i].unitPrice *
                                detail.items[i].quantity,
                          ),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 1),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: <pw.Widget>[
                        pw.Text(
                          '${formatQty(detail.items[i].quantity)} x '
                          '${_money(detail.items[i].unitPrice)}'
                          '${isTaxInvoice && detail.items[i].gstRate > 0 ? '   GST ${detail.items[i].gstRate.toStringAsFixed(0)}%' : ''}'
                          '${isTaxInvoice && (detail.items[i].hsnCode ?? '').isNotEmpty ? '   HSN ${_safe(detail.items[i].hsnCode!)}' : ''}',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: _muted,
                          ),
                        ),
                        if (detail.items[i].lineDiscount > 0.009)
                          pw.Text(
                            'Discount - ${_money(detail.items[i].lineDiscount)}',
                            style: pw.TextStyle(
                              fontSize: 7.5,
                              color: _good,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            pw.Container(height: 1, color: _ink),
            // ---- Totals -------------------------------------------------
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: <pw.Widget>[
                  _totalRow(
                    'Items (${detail.items.length})  Qty ${formatQty(totalQty)}',
                    '',
                  ),
                  if (isTaxInvoice) ...<pw.Widget>[
                    _totalRow('Taxable value', _money(taxable)),
                    if (cgst > 0) _totalRow('CGST', _money(cgst)),
                    if (sgst > 0) _totalRow('SGST', _money(sgst)),
                    if (totalTax > 0)
                      _totalRow('Total GST', _money(totalTax), bold: true),
                  ],
                  if (detail.discount > 0.009)
                    _totalRow(
                      'You saved',
                      '- ${_money(detail.discount)}',
                      bold: true,
                      color: _good,
                    ),
                  pw.SizedBox(height: 4),
                  pw.Container(height: 1, color: _line),
                  pw.SizedBox(height: 4),
                  _totalRow(
                    'TOTAL',
                    _money(detail.total),
                    big: true,
                    color: _brand,
                  ),
                  pw.SizedBox(height: 2),
                  _totalRow(
                    'Paid (${_safe(detail.paymentMode)})',
                    _money(detail.amountReceived),
                  ),
                  if (detail.amountDue > 0.009)
                    _totalRow(
                      'BALANCE DUE',
                      _money(detail.amountDue),
                      bold: true,
                      color: _warn,
                    ),
                ],
              ),
            ),
            // ---- UPI collect QR ------------------------------------------
            if (upiUri != null) ...<pw.Widget>[
              pw.Container(
                width: double.infinity,
                color: _zebra,
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                child: pw.Column(
                  children: <pw.Widget>[
                    pw.Text(
                      'SCAN TO PAY ${_money(detail.amountDue)}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                        letterSpacing: 1,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(5),
                      color: PdfColors.white,
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: upiUri,
                        width: 92,
                        height: 92,
                        drawText: false,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Any UPI app - GPay / PhonePe / Paytm',
                      style: const pw.TextStyle(fontSize: 7, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
            // ---- Footer --------------------------------------------------
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: pw.Column(
                children: <pw.Widget>[
                  if (footer.isNotEmpty)
                    pw.Text(
                      footer,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: _ink,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Powered by Amburax',
                    style: const pw.TextStyle(fontSize: 6.5, color: _muted),
                  ),
                ],
              ),
            ),
            pw.Container(height: 4, color: _brand),
          ],
        );
      },
    ),
  );

  return doc.save();
}
