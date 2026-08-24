import type { SaleReturnListPayload, SaleReturnRecord } from "@/lib/types";

/** Pulls the rows out of the returns payload, whatever shape arrives.
 *
 *  The endpoint answers with `{ returns: [...], refunded_total }` rather than
 *  a bare list. Reading it as a list crashed the whole sales page — a screen
 *  that has to render even when a secondary panel cannot, so this never
 *  throws and never returns anything that is not an array.
 */
export function toReturnRows(payload: unknown): SaleReturnRecord[] {
  if (Array.isArray(payload)) {
    // Tolerated in case the endpoint is ever simplified to a plain list.
    return payload as SaleReturnRecord[];
  }
  const rows = (payload as SaleReturnListPayload | null)?.returns;
  return Array.isArray(rows) ? rows : [];
}

/** Total refunded against each sale id.
 *
 *  A return is a separate document and leaves the sale untouched, so this map
 *  is the only way the history table can tell a returned bill from one that
 *  still stands.
 */
export function refundsBySale(rows: SaleReturnRecord[]): Record<string, number> {
  const totals: Record<string, number> = {};
  for (const row of rows) {
    if (!row?.sale_id) continue;
    const amount = Number(row.refund_amount);
    if (!Number.isFinite(amount) || amount <= 0) continue;
    totals[row.sale_id] = (totals[row.sale_id] ?? 0) + amount;
  }
  return totals;
}
