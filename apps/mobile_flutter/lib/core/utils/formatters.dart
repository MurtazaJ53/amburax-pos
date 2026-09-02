/// Money, tax and date formatting, driven by the active [RegionProfile].
///
/// Two money representations exist during the migration to integer minor units:
///  - **major** (`double`, e.g. 12.99 pounds) — legacy, what most models still
///    hold today. Use [formatCurrency].
///  - **minor** (`int`, e.g. 1299 pence) — the target representation. Use
///    [formatMinor]. New code should prefer minor units.
library;

import '../region/region.dart';

/// Formats a **major-unit** amount (e.g. pounds) in the active region's
/// currency, e.g. `£1,234.50` (UK) or `₹1,23,450` (India).
String formatCurrency(num amount, {bool showFraction = true, RegionProfile? region}) {
  final r = region ?? activeRegion;
  final fraction = showFraction && _fractionDigits(r) > 0;
  return _format(amount.toDouble(), r, fraction);
}

/// Formats an **minor-unit** integer (e.g. pence) in the active region's
/// currency. `1299` -> `£12.99`.
String formatMinor(int minorUnits, {RegionProfile? region}) {
  final r = region ?? activeRegion;
  final divisor = _minorPerMajor(r);
  return _format(minorUnits / divisor, r, _fractionDigits(r) > 0);
}

/// Formats a quantity the way a shopkeeper writes one: `3`, not `3.0`, but
/// `1.5` kept as `1.5`.
///
/// Whole numbers lose the decimal because most of what crosses a counter is
/// counted, not weighed — a receipt reading "3.0 soap" looks like a machine
/// wrote it. Fractions survive intact because the ones that occur are real:
/// 1.5 kg of onions off the scale, half a dozen eggs.
String formatQuantity(num value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

/// Compact currency for dense surfaces: `£950`, `£1.2k`, `£3.4M`.
String formatCurrencyCompact(num amount, {RegionProfile? region}) {
  final r = region ?? activeRegion;
  final negative = amount < 0;
  final value = amount.abs().toDouble();
  final sign = negative ? '-' : '';
  if (value < 1000) {
    return formatCurrency(amount, showFraction: value != value.roundToDouble(), region: r);
  }
  if (value < 1000000) return '$sign${r.currencySymbol}${_trim(value / 1000)}k';
  if (value < 1000000000) return '$sign${r.currencySymbol}${_trim(value / 1000000)}M';
  return '$sign${r.currencySymbol}${_trim(value / 1000000000)}B';
}

String _format(double value, RegionProfile r, bool withFraction) {
  final negative = value < 0;
  final abs = value.abs();
  final String body;
  if (withFraction) {
    final places = _fractionDigits(r);
    final scaled = (abs * _pow10(places)).round();
    final whole = scaled ~/ _pow10(places);
    final frac = (scaled % _pow10(places)).toString().padLeft(places, '0');
    body = '${_group(whole, r.grouping)}.$frac';
  } else {
    body = _group(abs.round(), r.grouping);
  }
  return '${negative ? '-' : ''}${r.currencySymbol}$body';
}

int _fractionDigits(RegionProfile r) => r.currencyCode == 'INR' ? 0 : 2;
int _minorPerMajor(RegionProfile r) => 100; // GBP pence, INR paise(unused→0dp)
int _pow10(int n) => n == 2 ? 100 : (n == 0 ? 1 : 10);

/// Groups an integer per the region's [GroupingStyle].
String _group(int value, GroupingStyle style) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;

  if (style == GroupingStyle.indian) {
    final lastThree = digits.substring(digits.length - 3);
    var leading = digits.substring(0, digits.length - 3);
    final chunks = <String>[];
    while (leading.length > 2) {
      chunks.insert(0, leading.substring(leading.length - 2));
      leading = leading.substring(0, leading.length - 2);
    }
    if (leading.isNotEmpty) chunks.insert(0, leading);
    return '${chunks.join(',')},$lastThree';
  }

  // Western grouping (groups of 3).
  final buffer = StringBuffer();
  final firstGroup = digits.length % 3;
  var index = 0;
  if (firstGroup > 0) {
    buffer.write(digits.substring(0, firstGroup));
    index = firstGroup;
  }
  while (index < digits.length) {
    if (buffer.isNotEmpty) buffer.write(',');
    buffer.write(digits.substring(index, index + 3));
    index += 3;
  }
  return buffer.toString();
}

String _trim(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

// ---------------------------------------------------------------------------
// Tax (VAT / GST) helpers — operate on major-unit doubles.
// ---------------------------------------------------------------------------

/// Tax contained within a tax-inclusive (gross) amount at [rate].
double taxFromGross(double gross, double rate) =>
    rate <= 0 ? 0 : gross - (gross / (1 + rate));

/// Tax to add to a tax-exclusive (net) amount at [rate].
double taxFromNet(double net, double rate) => net * rate;

/// Net (tax-exclusive) portion of a gross amount.
double netFromGross(double gross, double rate) => gross - taxFromGross(gross, rate);

/// Rounds a major-unit value to whole minor units to avoid float drift.
double roundMinor(double amount) => (amount * 100).round() / 100;

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

/// Short date `dd/MM/yyyy` (shared by UK and India).
String formatCompactDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

/// Format a quantity/stock value without a trailing ".0" (2 stays "2",
/// 1.5 stays "1.5"). For fractional (weighed) goods.
String formatQty(num value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
