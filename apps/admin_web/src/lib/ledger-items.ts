/** What a khata line was actually for.
 *
 * A balance nobody can break down is a balance the customer argues with. The
 * ledger has never had a foreign key to the sale, but every sale entry is
 * written with the sale's id in `source_id`, so the server can hand the lines
 * back on the timeline. Entries recorded before that — and opening balances
 * and manual adjustments, which never had a sale at all — carry no sale, and
 * must read as "not recorded" rather than as "nothing was bought".
 */

export type LedgerSaleLine = {
  name: string;
  sku?: string;
  size?: string;
  quantity: string;
  unit_price: string;
  line_total: string;
  is_return?: boolean;
};

export type LedgerSale = {
  id: string;
  receipt_number?: string;
  status?: string;
  total_amount?: string;
  discount_amount?: string;
  tax_amount?: string;
  items?: LedgerSaleLine[];
};

/** Lines to show for an entry, or an empty array when there are none. */
export function saleLines(sale: LedgerSale | null | undefined): LedgerSaleLine[] {
  if (!sale || !Array.isArray(sale.items)) return [];
  return sale.items.filter((line) => line && typeof line.name === "string" && line.name !== "");
}

// One implementation of quantity formatting, shared with the dashboard's
// low-stock chips, so "1.000" cannot come back in one place and not the other.
import { formatQuantity } from "./utils";

export { formatQuantity };

/** One-line summary for the collapsed row: "3 items · 5 units". */
export function linesSummary(lines: LedgerSaleLine[]): string {
  if (lines.length === 0) return "";
  const units = lines.reduce((sum, line) => {
    const value = Number(line.quantity);
    return sum + (Number.isFinite(value) ? value : 0);
  }, 0);
  const itemWord = lines.length === 1 ? "item" : "items";
  const unitLabel = formatQuantity(units);
  return `${lines.length} ${itemWord} · ${unitLabel} ${units === 1 ? "unit" : "units"}`;
}
