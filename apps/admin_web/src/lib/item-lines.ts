/** The one shape a delivery is entered in, wherever it is entered.
 *
 *  A purchase is the single event that moves five things at once: stock goes
 *  up, the item's cost price is rewritten, the last supplier and date are
 *  stamped on it, the supplier's ledger gains an entry and their balance
 *  grows. The backend does all five - but only for a line that names a stock
 *  item. A line without one is filed as money owed and nothing else.
 *
 *  That is why this lives in one place. Two screens book purchases - Purchase
 *  orders when a delivery arrives, Suppliers when a bill is typed straight in
 *  - and they must produce the same payload, or the same delivery updates
 *  stock through one door and silently does not through the other.
 */
import { searchItems } from "@/lib/stock-search";

export type StockItem = {
  id: string;
  name: string;
  sku: string;
  size: string;
  /** The unit the shop counts this item in. Everything - stock, sales,
   *  purchases - is in it, so it is what a quantity on this screen means. */
  unit: string;
  /** Null when no cost was ever recorded, or when this role cannot see one. */
  costPrice: number | null;
  stock: number;
  /** Optional: a scanner is not always to hand on a buying screen. */
  barcode?: string;
};

export type DraftLine = {
  itemId: string;
  quantity: string;
  unitCost: string;
  /** What has been typed into the item search before one is chosen. */
  query: string;
  /** The pack helper, open only while a delivery is being converted. */
  packMode: boolean;
  packs: string;
  unitsPerPack: string;
  packCost: string;
};

export const BLANK_LINE: DraftLine = {
  itemId: "",
  quantity: "",
  unitCost: "",
  query: "",
  packMode: false,
  packs: "",
  unitsPerPack: "",
  packCost: "",
};

/** A line as the purchases API takes it. */
export type LinePayload = {
  inventory_item_id: string;
  name: string;
  sku: string;
  quantity: string;
  unit_cost: string;
};

function num(value: string | number | null | undefined): number {
  const n = typeof value === "number" ? value : parseFloat(String(value ?? ""));
  return Number.isFinite(n) ? n : 0;
}

/** What the picker should list.
 *
 *  Delegates the search itself to stock-search, which is where the matching
 *  rule is pinned. The one difference is an empty query: a scan that matches
 *  nothing must select nothing, but a buyer who has clicked into an empty box
 *  is browsing, and an empty list would look like an empty shop.
 */
export function matchesFor(items: StockItem[], query: string, limit = 8): StockItem[] {
  if (!query.trim()) return items.slice(0, limit);
  return searchItems(
    items.map((it) => ({ ...it, barcode: it.barcode ?? "" })),
    query,
    limit,
  );
}

/** Choosing an item fills the cost it was last bought at - but only into an
 *  empty field, because a cost typed by hand is a negotiation. */
export function applyPick(line: DraftLine, item: StockItem): DraftLine {
  return {
    ...line,
    itemId: item.id,
    query: "",
    unitCost:
      line.unitCost.trim() === "" && item.costPrice != null
        ? String(item.costPrice)
        : line.unitCost,
  };
}

/** True once a line carries enough to move stock: an item and a quantity.
 *  A cost of zero is allowed - free stock and samples are real. */
export function isComplete(line: DraftLine): boolean {
  return Boolean(line.itemId) && num(line.quantity) > 0;
}

/** A line nobody has touched. Distinguished from an incomplete one so the
 *  spare row at the bottom of the form is not an error. */
export function isBlank(line: DraftLine): boolean {
  return (
    !line.itemId &&
    !line.query.trim() &&
    !line.quantity.trim() &&
    !line.unitCost.trim()
  );
}

export function lineTotal(line: DraftLine): number {
  return num(line.quantity) * num(line.unitCost);
}

export function linesSubtotal(lines: DraftLine[]): number {
  return lines.reduce((sum, line) => (isComplete(line) ? sum + lineTotal(line) : sum), 0);
}

/** What is wrong, in the words used on the screen - or null to proceed.
 *
 *  A half-filled line is refused rather than dropped. Dropping it books a
 *  bill whose total is right and whose stock is short, which is the one
 *  failure nobody notices until a count.
 */
export function validateLines(lines: DraftLine[]): string | null {
  const used = lines.filter((line) => !isBlank(line));
  if (used.length === 0) return "Add at least one item.";

  if (used.some((line) => !line.itemId)) {
    return "Choose each item from stock, so the delivery reaches the right product.";
  }
  if (used.some((line) => num(line.quantity) <= 0)) {
    return "Enter how many of each item arrived.";
  }

  const seen = new Set<string>();
  for (const line of used) {
    if (seen.has(line.itemId)) {
      return "The same item is on two lines. Put the whole quantity on one.";
    }
    seen.add(line.itemId);
  }
  return null;
}

/** The lines as the API takes them, with the name and SKU snapshotted from
 *  stock so the bill still reads correctly if the product is renamed later. */
export function toPayload(lines: DraftLine[], items: StockItem[]): LinePayload[] {
  return lines.filter(isComplete).map((line) => {
    const item = items.find((it) => it.id === line.itemId);
    return {
      inventory_item_id: line.itemId,
      name: item?.name ?? "",
      sku: item?.sku ?? "",
      quantity: String(num(line.quantity)),
      unit_cost: num(line.unitCost).toFixed(2),
    };
  });
}

/** One row of /api/inventory as a picker item.
 *
 *  The null rule is the one that matters: a cost of null means the item was
 *  never bought, or that this role may not see costs. Coercing it to zero
 *  makes zero the suggested cost, and the first receipt that accepts the
 *  suggestion writes zero as the item's cost price - which then reads as pure
 *  profit on every report that item appears in.
 */
export function toStockItem(raw: Record<string, unknown>): StockItem {
  return {
    id: String(raw.id),
    name: String(raw.name ?? ""),
    sku: String(raw.sku ?? ""),
    size: String(raw.size ?? ""),
    unit: String(raw.unit ?? ""),
    costPrice:
      raw.cost_price === null || raw.cost_price === undefined
        ? null
        : Number(raw.cost_price),
    stock: Number(raw.stock_on_hand ?? 0),
    barcode: String(raw.barcode ?? ""),
  };
}

/** The inventory payload, whichever shape it arrives in.
 *
 *  The proxy returns { items, summary } while the API returns a bare list.
 *  Reading the wrong one is not a visible failure - it is an empty picker
 *  with no message, which is how the purchase-order screen sat unusable.
 */
export function readStockItems(payload: unknown): StockItem[] {
  const rows = Array.isArray(payload)
    ? payload
    : Array.isArray((payload as { items?: unknown })?.items)
      ? ((payload as { items: unknown[] }).items)
      : [];
  return rows.map((raw) => toStockItem(raw as Record<string, unknown>));
}
