/** Turning an inventory row from the API into the shape the Stock screen draws.
 *
 *  This lived inline in the manager component and quietly lost data three
 *  ways: a null cost became a real ₹0.00, every item's reorder level was
 *  hardcoded to 10 regardless of what the shopkeeper set, and a missing GST
 *  rate defaulted to 5%. All three then flowed into what the screen claimed
 *  as fact, so they are pinned by tests here.
 */

/** An inventory row as the API returns it; only the fields the screen reads. */
export type ApiInventoryRow = {
  id: string;
  name: string;
  sku?: string;
  barcode?: string;
  category?: string;
  /** Null when unset — and ALSO null when the viewer may not see costs. */
  cost_price?: string | null;
  sell_price?: string;
  stock_on_hand?: number;
  reorder_level?: number | null;
  gst_rate?: string | null;
  hsn_code?: string;
  unit?: string;
  price_includes_tax?: boolean;
  /** A data URI holding a small product photo, or "" when none was set. */
  image_data?: string | null;
  /** Was this item ever given stock? False for a row imported without any,
   *  which is not the same as a shelf that emptied. */
  has_stock_history?: boolean;
  status?: string;
  size?: string;
  description?: string;
  created_at?: string;
  updated_at?: string;
};

export type ProductRow = {
  id: string;
  name: string;
  sku: string;
  barcode: string;
  category: string;
  /** Null means "not known", never zero. A zero cost is a real claim. */
  cost_price: number | null;
  selling_price: number;
  current_stock: number;
  /** Null when the shop has not set one for this item. */
  reorder_level: number | null;
  is_low_stock: boolean;
  is_out_of_stock: boolean;
  /** True once the item has ever received stock. Until then its count carries
   *  no information: zero does not mean empty, and a negative does not mean
   *  short - nobody ever said how many there were. */
  is_tracked: boolean;
  /** Null when the API did not say. Not the same as 0% (exempt). */
  tax_rate: number | null;
  hsn_code: string;
  unit: string;
  price_includes_tax: boolean;
  /** Empty string when there is no photo — the tiles fall back to an initial. */
  image_data: string;
  status: string;
  created_at: string;
  updated_at: string;
};

/** The level below which an item counts as low, when none is configured. */
export const DEFAULT_REORDER_LEVEL = 10;

function toNumberOrNull(value: string | null | undefined): number | null {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function mapInventoryRow(row: ApiInventoryRow): ProductRow {
  const stock = row.stock_on_hand ?? 0;
  // A configured level of 0 is meaningful ("never warn me"), so only fall
  // back when the field is genuinely absent.
  const reorder = row.reorder_level ?? null;
  const threshold = reorder ?? DEFAULT_REORDER_LEVEL;

  return {
    id: row.id,
    name: row.name,
    sku: row.sku ?? "",
    barcode: row.barcode ?? "",
    category: row.category || "General",
    cost_price: toNumberOrNull(row.cost_price),
    selling_price: Number(row.sell_price ?? 0) || 0,
    current_stock: stock,
    reorder_level: reorder,
    is_low_stock: stock > 0 && stock <= threshold,
    is_out_of_stock: stock <= 0,
    // A MISSING field means "this API did not say", not "never stocked".
    // Defaulting it to false made every row on an older server read "Stock not
    // tracked" — including one holding 462 units. When the server is silent,
    // infer from the count instead: a non-zero balance cannot exist without a
    // stock movement behind it, so it is proof of history. Only a zero stays
    // genuinely unknown, which is the ambiguity this field exists to remove
    // and the honest answer when nobody has told us.
    is_tracked:
      row.has_stock_history === undefined ? stock !== 0 : row.has_stock_history === true,
    tax_rate: toNumberOrNull(row.gst_rate),
    hsn_code: row.hsn_code ?? "",
    unit: row.unit ?? "",
    price_includes_tax: row.price_includes_tax ?? true,
    image_data: row.image_data ?? "",
    status: row.status ?? "active",
    created_at: row.created_at || "",
    updated_at: row.updated_at || "",
  };
}

/** Margin as a percentage of the selling price, or null when unknowable.
 *
 *  Percent-of-selling rather than markup-on-cost, because that is the figure
 *  a shopkeeper compares against what a distributor offers.
 */
export function marginPercent(row: ProductRow): number | null {
  if (row.cost_price === null || row.selling_price <= 0) {
    return null;
  }
  return ((row.selling_price - row.cost_price) / row.selling_price) * 100;
}

/** Mean margin across the rows that have one, or null if none do. */
export function averageMargin(rows: ProductRow[]): number | null {
  const margins = rows
    .map(marginPercent)
    .filter((value): value is number => value !== null);
  if (margins.length === 0) {
    return null;
  }
  return margins.reduce((sum, value) => sum + value, 0) / margins.length;
}

/** How full the shelf is relative to its reorder level, capped at 100. */
export function stockFillPercent(row: ProductRow): number {
  const threshold = row.reorder_level ?? DEFAULT_REORDER_LEVEL;
  if (threshold <= 0) {
    return row.current_stock > 0 ? 100 : 0;
  }
  // Twice the reorder level reads as a comfortably full shelf.
  return Math.max(0, Math.min(100, (row.current_stock / (threshold * 2)) * 100));
}
