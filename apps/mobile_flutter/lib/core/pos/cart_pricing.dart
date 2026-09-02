import '../money/money.dart';
import '../models/mobile_models.dart';

/// Pure, side-effect-free money math for the POS cart.
///
/// All arithmetic runs through [Money] (integer paise) so repeated
/// add/discount/split operations are exact — no binary-double drift. The
/// public API stays in rupee doubles for the UI and storage layers, which snap
/// to whole paise on the way in.
class CartPricing {
  const CartPricing._();

  /// Sum of line totals after any per-item discount, but before the
  /// sale-level discount.
  static double subtotal(Iterable<PosCartItem> items) {
    var total = Money.zero;
    for (final item in items) {
      // price * qty may be fractional (weighed goods); round to paise via Money.
      total = total + Money.rupees(item.lineTotal);
    }
    return total.rupees;
  }

  /// Resolve a discount input (fixed rupees or a percent) to an amount,
  /// never negative and never more than the subtotal.
  static double discountAmount({
    required double subtotal,
    required double value,
    required bool isPercent,
  }) {
    if (value <= 0 || subtotal <= 0) return 0;
    final sub = Money.rupees(subtotal);
    final amount = isPercent ? sub.percent(value) : Money.rupees(value);
    if (!amount.isPositive) return 0;
    return amount.min(sub).rupees;
  }

  /// Net payable after discount.
  static double net({required double subtotal, required double discount}) {
    return (Money.rupees(subtotal) - Money.rupees(discount))
        .clampedToZero
        .rupees;
  }

  /// Total tendered across all payment lines.
  static double paid(Iterable<PosPayment> payments) {
    var total = Money.zero;
    for (final p in payments) {
      total = total + Money.rupees(p.amount);
    }
    return total.rupees;
  }

  /// Balance still owed (credit / khata) — 0 if fully paid.
  static double due({required double net, required double paid}) {
    final d = Money.rupees(net) - Money.rupees(paid);
    return d.isPositive ? d.rupees : 0;
  }

  /// Change to return (cash overpayment) — 0 if not overpaid.
  static double change({required double net, required double paid}) {
    final c = Money.rupees(paid) - Money.rupees(net);
    return c.isPositive ? c.rupees : 0;
  }
}
