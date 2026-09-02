import '../models/mobile_models.dart';

double _money(num value) => (value * 100).roundToDouble() / 100;

class GstLineBreakdown {
  const GstLineBreakdown({
    required this.taxableAmount,
    required this.taxAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.grossAmount,
  });

  final double taxableAmount;
  final double taxAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double grossAmount;
}

class GstCartSummary {
  const GstCartSummary({
    required this.taxableAmount,
    required this.taxAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.grossAmount,
  });

  final double taxableAmount;
  final double taxAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double grossAmount;

  bool get hasTax => taxAmount.abs() > 0.009;
}

GstLineBreakdown computeLineGst({
  required double lineTotal,
  required double gstRate,
  required bool priceIncludesTax,
  required bool intraState,
}) {
  final rate = gstRate / 100;
  if (rate <= 0) {
    final taxable = _money(lineTotal);
    return GstLineBreakdown(
      taxableAmount: taxable,
      taxAmount: 0,
      cgstAmount: 0,
      sgstAmount: 0,
      igstAmount: 0,
      grossAmount: taxable,
    );
  }

  final taxableAmount = priceIncludesTax
      ? _money(lineTotal / (1 + rate))
      : _money(lineTotal);
  final taxAmount = priceIncludesTax
      ? _money(lineTotal - taxableAmount)
      : _money(taxableAmount * rate);
  final grossAmount = priceIncludesTax
      ? _money(lineTotal)
      : _money(taxableAmount + taxAmount);

  if (intraState) {
    final cgstAmount = _money(taxAmount / 2);
    return GstLineBreakdown(
      taxableAmount: taxableAmount,
      taxAmount: taxAmount,
      cgstAmount: cgstAmount,
      sgstAmount: _money(taxAmount - cgstAmount),
      igstAmount: 0,
      grossAmount: grossAmount,
    );
  }

  return GstLineBreakdown(
    taxableAmount: taxableAmount,
    taxAmount: taxAmount,
    cgstAmount: 0,
    sgstAmount: 0,
    igstAmount: taxAmount,
    grossAmount: grossAmount,
  );
}

List<double> apportionDiscount(List<double> lineTotals, double discount) {
  if (discount <= 0 || lineTotals.isEmpty) {
    return List.generate(lineTotals.length, (_) => 0.0);
  }

  final total = lineTotals.fold<double>(0.0, (sum, val) => sum + val);
  if (total <= 0) {
    return List.generate(lineTotals.length, (_) => 0.0);
  }

  final results = <double>[];
  var accumulatedDiscount = 0.0;

  for (var i = 0; i < lineTotals.length; i++) {
    if (i == lineTotals.length - 1) {
      results.add(_money(discount - accumulatedDiscount));
    } else {
      final portion = _money((lineTotals[i] / total) * discount);
      results.add(portion);
      accumulatedDiscount += portion;
    }
  }

  return results;
}

GstCartSummary computeCartGst(
  Iterable<PosCartItem> items, {
  bool intraState = true,
  double discount = 0.0,
}) {
  var taxableAmount = 0.0;
  var taxAmount = 0.0;
  var cgstAmount = 0.0;
  var sgstAmount = 0.0;
  var igstAmount = 0.0;
  var grossAmount = 0.0;

  final itemsList = items.toList();
  final lineTotals = itemsList.map((i) => i.lineTotal).toList();
  final apportionedDiscounts = apportionDiscount(lineTotals, discount);

  for (var i = 0; i < itemsList.length; i++) {
    final item = itemsList[i];
    final postDiscountTotal = item.lineTotal - apportionedDiscounts[i];
    // Avoid passing negative values just in case
    final effectiveTotal = postDiscountTotal < 0 ? 0.0 : postDiscountTotal;

    final line = computeLineGst(
      lineTotal: effectiveTotal,
      gstRate: item.gstRate,
      priceIncludesTax: item.priceIncludesTax,
      intraState: intraState,
    );
    taxableAmount += line.taxableAmount;
    taxAmount += line.taxAmount;
    cgstAmount += line.cgstAmount;
    sgstAmount += line.sgstAmount;
    igstAmount += line.igstAmount;
    grossAmount += line.grossAmount;
  }

  return GstCartSummary(
    taxableAmount: _money(taxableAmount),
    taxAmount: _money(taxAmount),
    cgstAmount: _money(cgstAmount),
    sgstAmount: _money(sgstAmount),
    igstAmount: _money(igstAmount),
    grossAmount: _money(grossAmount),
  );
}
