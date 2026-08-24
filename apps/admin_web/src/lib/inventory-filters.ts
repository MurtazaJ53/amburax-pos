/** Narrowing a two-hundred-row catalogue down to the rows that need a decision.
 *
 *  The Stock screen had four slices — everything, out, low, and missing a cost
 *  price. Those answer "what do I reorder" and nothing else. A shop also has
 *  to answer "what can't the counter scan", "what will fail a GST return", and
 *  "what is actually still sellable", and none of those were reachable without
 *  reading two hundred rows by eye.
 *
 *  Kept out of the component so each rule can be pinned by a test: a filter
 *  that silently includes the wrong rows is worse than no filter, because the
 *  count beside it reads as a fact.
 */

export type StockFilter =
  | "all"
  | "in"
  | "out"
  | "low"
  | "nocost"
  | "nobarcode"
  | "nohsn"
  | "oversold"
  | "untracked";

export type SortKey =
  | "name"
  | "stock-low"
  | "value-high"
  | "margin-low"
  | "recent";

/** Only the fields the filters read, so this stays usable from a test. */
export type FilterableRow = {
  name: string;
  sku: string;
  barcode: string;
  category: string;
  cost_price: number | null;
  selling_price: number;
  current_stock: number;
  hsn_code: string;
  is_low_stock: boolean;
  is_out_of_stock: boolean;
  is_tracked: boolean;
  updated_at: string;
};

export type FilterState = {
  search: string;
  category: string;
  stock: StockFilter;
  sort: SortKey;
};

export const DEFAULT_FILTERS: FilterState = {
  search: "",
  category: "all",
  stock: "all",
  sort: "name",
};

/** Does this row satisfy the chosen slice? */
export function matchesStockFilter(row: FilterableRow, filter: StockFilter): boolean {
  switch (filter) {
    case "in":
      return !row.is_out_of_stock;
    case "out":
      return row.is_out_of_stock;
    case "low":
      return row.is_low_stock;
    case "nocost":
      // Null means "not known". A real zero cost is a claim someone made and
      // must not be swept in here.
      return row.cost_price === null;
    case "nobarcode":
      return row.barcode.trim() === "";
    case "nohsn":
      return row.hsn_code.trim() === "";
    case "oversold":
      // Below zero on an item that WAS being tracked: units left the shop
      // that nobody recorded buying, and the count needs correcting.
      //
      // An untracked item is excluded on purpose. Its negative is an artefact
      // of selling something nobody ever counted, not a shortfall, and
      // putting it on this list would bury the real ones under it.
      return row.is_tracked && row.current_stock < 0;
    case "untracked":
      return !row.is_tracked;
    case "all":
    default:
      return true;
  }
}

/** Name, SKU or barcode. Barcode is matched raw so a scanner gun works. */
export function matchesSearch(row: FilterableRow, search: string): boolean {
  const query = search.trim().toLowerCase();
  if (!query) return true;
  return (
    row.name.toLowerCase().includes(query) ||
    row.sku.toLowerCase().includes(query) ||
    row.barcode.toLowerCase().includes(query)
  );
}

/** Retail value sitting on the shelf for this row. */
export function shelfValue(row: FilterableRow): number {
  return row.selling_price * row.current_stock;
}

/** Margin as a fraction of the selling price, or null when cost is unknown. */
export function rowMargin(row: FilterableRow): number | null {
  if (row.cost_price === null || row.selling_price <= 0) return null;
  return (row.selling_price - row.cost_price) / row.selling_price;
}

function compare(a: FilterableRow, b: FilterableRow, sort: SortKey): number {
  switch (sort) {
    case "stock-low":
      return a.current_stock - b.current_stock;
    case "value-high":
      return shelfValue(b) - shelfValue(a);
    case "margin-low": {
      const left = rowMargin(a);
      const right = rowMargin(b);
      // Rows with no cost cannot be ranked by margin. They sort last rather
      // than masquerading as the worst performers.
      if (left === null && right === null) return 0;
      if (left === null) return 1;
      if (right === null) return -1;
      return left - right;
    }
    case "recent":
      return (b.updated_at || "").localeCompare(a.updated_at || "");
    case "name":
    default:
      return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
  }
}

export function applyFilters<T extends FilterableRow>(
  rows: T[],
  state: FilterState,
): T[] {
  const narrowed = rows.filter((row) => {
    if (!matchesCategory(row, state.category)) return false;
    if (!matchesStockFilter(row, state.stock)) return false;
    return matchesSearch(row, state.search);
  });
  // Copied before sorting: sorting the filter result in place is fine, but
  // returning a sorted view of the caller's array is not.
  return [...narrowed].sort((a, b) => compare(a, b, state.sort));
}

/** How many rows each slice would return, for the chip labels. */
export function filterCounts(rows: FilterableRow[]): Record<StockFilter, number> {
  return {
    all: rows.length,
    in: rows.filter((r) => matchesStockFilter(r, "in")).length,
    out: rows.filter((r) => matchesStockFilter(r, "out")).length,
    low: rows.filter((r) => matchesStockFilter(r, "low")).length,
    nocost: rows.filter((r) => matchesStockFilter(r, "nocost")).length,
    nobarcode: rows.filter((r) => matchesStockFilter(r, "nobarcode")).length,
    nohsn: rows.filter((r) => matchesStockFilter(r, "nohsn")).length,
    oversold: rows.filter((r) => matchesStockFilter(r, "oversold")).length,
    untracked: rows.filter((r) => matchesStockFilter(r, "untracked")).length,
  };
}

/** Is anything actually narrowing the list right now? */
export function hasActiveFilters(state: FilterState): boolean {
  return (
    state.search.trim() !== "" || state.category !== "all" || state.stock !== "all"
  );
}

/** One category, and how many rows it would return right now. */
export type CategoryFacet = { key: string; label: string; count: number };

/** The categories worth offering, ordered by how much of the shelf they hold.
 *
 *  Alphabetical order is the wrong default here: with twenty-one categories
 *  the ones a shopkeeper touches all day would be scattered among the ones
 *  holding two items each. Counting first puts the working set in front.
 *
 *  Counts are faceted — narrowed by the stock slice but NOT by the category
 *  itself, so "Vests 12" keeps saying what picking Vests would give you even
 *  while Vests is the active choice.
 */
export function categoryFacets(
  rows: FilterableRow[],
  stock: StockFilter = "all",
  search = "",
): CategoryFacet[] {
  const pool = rows.filter(
    (row) => matchesStockFilter(row, stock) && matchesSearch(row, search),
  );

  const tally = new Map<string, number>();
  for (const row of pool) {
    // An item with no category still has to be findable, so it gets a named
    // bucket rather than being dropped out of the row entirely.
    const key = row.category.trim() || UNCATEGORISED;
    tally.set(key, (tally.get(key) ?? 0) + 1);
  }

  return [...tally.entries()]
    .map(([key, count]) => ({ key, label: key, count }))
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}

/** The bucket for items nobody filed. */
export const UNCATEGORISED = "Uncategorised";

/** Counts for the stock chips, faceted by the category in play.
 *
 *  Global counts lie once a category is chosen: the chip would promise 144
 *  out-of-stock items and the table would show nine.
 */
export function stockFacets(
  rows: FilterableRow[],
  category: string,
  search = "",
): Record<StockFilter, number> {
  const pool = rows.filter(
    (row) => matchesCategory(row, category) && matchesSearch(row, search),
  );
  return filterCounts(pool);
}

/** Category match, with the uncategorised bucket handled explicitly. */
export function matchesCategory(row: FilterableRow, category: string): boolean {
  if (category === "all") return true;
  const own = row.category.trim();
  if (category === UNCATEGORISED) return own === "";
  return own === category;
}
