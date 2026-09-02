/// What a product tile says about its stock.
///
/// This is a rule, not a label, and the two clients have to agree on it: the
/// same shop viewed on the web and on the phone must not disagree about
/// whether an item is short, empty or fine. The web already had it, spread
/// across a four-branch ternary inside `pos-terminal.tsx`; this is that rule
/// written down where it can be tested.
///
/// The mobile tile previously showed the category instead, and fell back to
/// stock only when a product had no category. Every product has a category,
/// so the stock figure never appeared at all.
///
/// All four of the web's states are here. The fourth — "Stock not tracked" —
/// arrives from the backend's `has_stock_history`, which the mobile catalogue
/// was dropping on the floor: the field was serialized and tested server-side
/// and simply never read. It is resolved through
/// `InventoryCatalogItem.isTracked`, so callers pass a bool rather than
/// re-deriving the rule.
library;

import '../utils/formatters.dart';

/// The line under a product's name on a tile.
///
/// Negative stock is called out rather than shown as a number, because a
/// negative count means the books and the shelf have already disagreed and
/// the fix is not at the till.
String stockCaption({
  required double stock,
  String? unit,
  bool isTracked = true,
}) {
  if (!isTracked) {
    // The count is not wrong, it is meaningless: nothing has ever been booked
    // in or out, so zero is an absence of information rather than an empty
    // shelf. Saying "Shelf empty" here would be a claim we cannot support.
    return 'Stock not tracked';
  }
  if (stock < 0) {
    return 'Short by ${formatQuantity(stock.abs())} — fix in Stock';
  }
  if (stock == 0) {
    // Still sellable: a shopkeeper holding the item should not be blocked by
    // a count that has drifted.
    return 'Shelf empty — still sellable';
  }
  final trimmed = unit?.trim();
  final suffix = (trimmed != null && trimmed.isNotEmpty)
      ? ' $trimmed'
      : ' in stock';
  return '${formatQuantity(stock)}$suffix';
}

/// How urgent a tile's corner badge is. Maps onto `AppTone` at the call site;
/// this layer stays free of anything needing a `BuildContext`.
enum StockLevel { short, empty, low, fine }

/// The corner badge on a product tile, or null when there is nothing to say.
///
/// [reorderLevel] is the item's own threshold falling back to the shop
/// default — the figure `InventoryCatalogItem.effectiveReorderLevel` already
/// resolves.
({String label, StockLevel level})? stockBadge({
  required double stock,
  required int reorderLevel,
  bool isTracked = true,
}) {
  // No badge at all for an untracked item. A corner badge is an alarm, and
  // there is nothing to be alarmed about in a number that means nothing.
  if (!isTracked) return null;
  if (stock < 0) {
    return (
      label: 'Short ${formatQuantity(stock.abs())}',
      level: StockLevel.short,
    );
  }
  if (stock == 0) return (label: 'Shelf empty', level: StockLevel.empty);
  if (stock <= reorderLevel) {
    // "5 left" rather than "Low": the number is what decides whether the
    // shopkeeper reaches for the reorder book, and it costs no more room.
    return (label: '${formatQuantity(stock)} left', level: StockLevel.low);
  }
  return null;
}
