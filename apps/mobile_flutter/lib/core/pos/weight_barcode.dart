/// Parser for price/weight-embedded EAN-13 barcodes printed by retail weighing
/// scales. The exact field layout varies by scale brand, so it is expressed as
/// a [WeightBarcodeConfig]; the default matches the most common in-store format:
///
///   prefix(1) itemCode(5) embeddedValue(6) check(1)   e.g. 2 12345 001250 8
///
/// The 6-digit value is either a **price** in the smallest currency unit (paise,
/// so `001250` -> ₹12.50) or a **weight** in grams (`001500` -> 1.500 kg),
/// selected by [WeightBarcodeConfig.valueIsWeight]. For weight barcodes the line
/// price is the item's rate × the decoded weight. Adjust the config to your
/// scale if the field layout differs.
class WeightBarcodeConfig {
  const WeightBarcodeConfig({
    this.prefixes = const <String>['2'],
    this.itemCodeStart = 1,
    this.itemCodeLength = 5,
    this.valueStart = 6,
    this.valueLength = 6,
    this.valueDivisor = 100,
    this.valueIsWeight = false,
    this.totalLength = 13,
  });

  final List<String> prefixes;
  final int itemCodeStart;
  final int itemCodeLength;
  final int valueStart;
  final int valueLength;

  /// Divide the embedded integer by this to get the decoded value.
  /// For a price this is 100 (paise -> currency); for a weight 1000 (grams -> kg).
  final double valueDivisor;

  /// When true the embedded value is a **weight** (e.g. kg after dividing) and
  /// the line price must be computed as rate × weight. When false the embedded
  /// value is the **price** to charge directly.
  final bool valueIsWeight;
  final int totalLength;

  /// Price-embedded scale barcode (embedded value is the amount, in paise).
  static const WeightBarcodeConfig standard = WeightBarcodeConfig();

  /// Weight-embedded scale barcode (embedded value is grams -> kg); the line
  /// price is charged as the item's rate × weight.
  static const WeightBarcodeConfig weightStandard = WeightBarcodeConfig(
    valueDivisor: 1000,
    valueIsWeight: true,
  );
}

/// Price for a weighed/loose line: rate per unit × weight, rounded to paise.
/// Returns 0 for non-positive inputs.
double weighedLinePrice({required double rate, required double weight}) {
  if (rate <= 0 || weight <= 0) return 0;
  return double.parse((rate * weight).toStringAsFixed(2));
}

class WeightBarcode {
  const WeightBarcode({
    required this.itemCode,
    required this.embeddedValue,
    this.isWeight = false,
  });

  /// The PLU / item lookup digits.
  final String itemCode;

  /// The decoded number: a price amount when [isWeight] is false, or a weight
  /// (e.g. kg) when [isWeight] is true.
  final double embeddedValue;

  /// Whether [embeddedValue] is a weight (true) or a ready-to-charge price (false).
  final bool isWeight;

  /// Resolve the price to charge for one scanned line given the matched item's
  /// [itemRate] (per-unit / per-kg sell price). For a weight barcode this is
  /// rate × weight; for a price barcode it is the embedded amount directly.
  double resolveLinePrice(double itemRate) => isWeight
      ? weighedLinePrice(rate: itemRate, weight: embeddedValue)
      : embeddedValue;
}

/// Returns a [WeightBarcode] if [raw] is a price/weight-embedded scale barcode
/// under [config], or null for a normal product barcode.
WeightBarcode? parseWeightBarcode(
  String raw, {
  WeightBarcodeConfig config = WeightBarcodeConfig.standard,
}) {
  final code = raw.trim();
  if (code.length != config.totalLength) return null;
  if (!RegExp(r'^\d+$').hasMatch(code)) return null;
  if (!config.prefixes.any(code.startsWith)) return null;

  final itemEnd = config.itemCodeStart + config.itemCodeLength;
  final valueEnd = config.valueStart + config.valueLength;
  if (itemEnd > code.length || valueEnd > code.length) return null;

  final itemCode = code.substring(config.itemCodeStart, itemEnd);
  final rawValue = int.tryParse(code.substring(config.valueStart, valueEnd));
  if (rawValue == null) return null;

  return WeightBarcode(
    itemCode: itemCode,
    embeddedValue: rawValue / config.valueDivisor,
    isWeight: config.valueIsWeight,
  );
}
