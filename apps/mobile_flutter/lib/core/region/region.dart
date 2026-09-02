/// Region / locale layer.
///
/// The product targets multiple markets (UK first, India legacy). Everything
/// market-specific — currency, VAT/tax rules, number grouping, phone format —
/// lives behind a [RegionProfile] so screens and services never hard-code a
/// currency symbol or tax rate again. This is the canonical contract; the web
/// (`src/`), admin (`admin_web`) and backend mirror the same shape.
library;

enum AppRegion { uk, india }

/// How integer groups are separated for display.
enum GroupingStyle {
  /// Western: 1,234,567 (groups of 3).
  western,

  /// Indian: 12,34,567 (3 then 2s).
  indian,
}

/// A named tax band, e.g. UK standard 20%.
class TaxRate {
  const TaxRate(this.label, this.rate);

  /// Human label shown in pickers/receipts, e.g. 'Standard 20%'.
  final String label;

  /// Fractional rate, e.g. 0.20.
  final double rate;
}

class RegionProfile {
  const RegionProfile({
    required this.region,
    required this.currencyCode,
    required this.currencySymbol,
    required this.localeTag,
    required this.grouping,
    required this.taxLabel,
    required this.taxRates,
    required this.defaultTaxRate,
    required this.taxInclusivePricing,
  });

  final AppRegion region;

  /// ISO 4217, e.g. 'GBP', 'INR'.
  final String currencyCode;

  /// Display symbol, e.g. '£', '₹'.
  final String currencySymbol;

  /// BCP-47 locale, e.g. 'en-GB', 'en-IN'.
  final String localeTag;

  final GroupingStyle grouping;

  /// What the region calls its sales tax, e.g. 'VAT', 'GST'.
  final String taxLabel;

  /// Selectable tax bands for products.
  final List<TaxRate> taxRates;

  /// Default band applied to new products.
  final TaxRate defaultTaxRate;

  /// True if shelf/entered prices already include tax (UK retail convention).
  final bool taxInclusivePricing;
}

const RegionProfile ukRegion = RegionProfile(
  region: AppRegion.uk,
  currencyCode: 'GBP',
  currencySymbol: '£',
  localeTag: 'en-GB',
  grouping: GroupingStyle.western,
  taxLabel: 'VAT',
  taxRates: [
    TaxRate('Standard 20%', 0.20),
    TaxRate('Reduced 5%', 0.05),
    TaxRate('Zero 0%', 0.0),
  ],
  defaultTaxRate: TaxRate('Standard 20%', 0.20),
  taxInclusivePricing: true,
);

const RegionProfile indiaRegion = RegionProfile(
  region: AppRegion.india,
  currencyCode: 'INR',
  currencySymbol: '₹',
  localeTag: 'en-IN',
  grouping: GroupingStyle.indian,
  taxLabel: 'GST',
  taxRates: [
    TaxRate('GST 18%', 0.18),
    TaxRate('GST 12%', 0.12),
    TaxRate('GST 5%', 0.05),
    TaxRate('GST 0%', 0.0),
  ],
  defaultTaxRate: TaxRate('GST 18%', 0.18),
  taxInclusivePricing: true,
);

RegionProfile regionProfileFor(AppRegion region) => switch (region) {
  AppRegion.uk => ukRegion,
  AppRegion.india => indiaRegion,
};

/// Active region for non-widget code (pure formatters, services).
///
/// Defaults to **India** — the primary target market. UK is a supported
/// secondary region. The UI layer keeps this in sync with the shop's selected
/// region; persisting the choice is a follow-up.
RegionProfile activeRegion = indiaRegion;
