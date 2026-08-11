/**
 * Finding one item from a scan or a typed search.
 *
 * Extracted from the stocktake screen so the selection rule can be pinned by
 * tests. The rule is not obvious and getting it wrong is expensive: a counter
 * scanning a shelf presses Enter after every barcode without looking up, so a
 * wrong pick silently records a count against the wrong item, and the variance
 * it produces looks exactly like real shrinkage.
 */

export type SearchableItem = {
  id: string;
  name: string;
  sku: string;
  barcode: string;
};

/** Items whose name, SKU or barcode contain the query. Empty query matches nothing. */
export function searchItems<T extends SearchableItem>(
  items: readonly T[],
  query: string,
  limit = 8,
): T[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  return items
    .filter(
      (i) =>
        i.name.toLowerCase().includes(q) ||
        i.sku.toLowerCase().includes(q) ||
        i.barcode.toLowerCase().includes(q),
    )
    .slice(0, limit);
}

/**
 * What Enter should select.
 *
 * An exact barcode or SKU wins outright, even when the same string also appears
 * inside other items' names — a scanner produced it, so it is not a guess.
 * Otherwise a single remaining match is taken as unambiguous. Anything else
 * returns null and the counter picks from the list: choosing the first of
 * several would be a coin toss recorded as a count.
 */
export function resolveScan<T extends SearchableItem>(
  items: readonly T[],
  query: string,
): T | null {
  const q = query.trim().toLowerCase();
  if (!q) return null;
  const exact = items.find(
    (i) => i.barcode.toLowerCase() === q || i.sku.toLowerCase() === q,
  );
  if (exact) return exact;
  const matches = searchItems(items, q);
  return matches.length === 1 ? matches[0] : null;
}
