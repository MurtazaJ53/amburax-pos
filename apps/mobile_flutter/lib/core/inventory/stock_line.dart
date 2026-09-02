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
/// One web state is deliberately missing. The web distinguishes "Stock not
/// tracked" using `is_tracked`, which the mobile catalogue model does not
/// carry. Rather than guess at it from a zero, an untracked item reads as
/// whatever its stock figure says; adding the flag is a model change for
/// another day.
library;

import '../utils/formatters.dart';

/// The line under a product's name on a tile.
///
/// Negative stock is called out rather than shown as a number, because a
/// negative count means the books and the shelf have already disagreed and
/// the fix is not at the till.
String stockCaption({required double stock, String? unit}) {
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
}) {
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
