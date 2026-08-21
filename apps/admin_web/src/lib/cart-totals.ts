/** What the customer owes, and how it breaks down for the receipt.
 *
 *  Extracted from the POS component so it can be tested. It could not be
 *  before, and it was wrong: it computed `tax = lineTotal * rate` and ADDED it
 *  to the subtotal. But `price_includes_tax` defaults to true — the Indian MRP
 *  convention — so the shelf price already contains GST and the server divides
 *  it back out (see apps/backend/platform_apps/sales/gst.py).
 *
 *  The till therefore asked for ₹157.50 on a ₹150 bill: a 5% overcharge on
 *  every taxed item. The only reason no customer was ever charged it is that
 *  the server rejected the sale outright with "Total must equal subtotal minus
 *  discount".
 *
 *  Tax here is a BREAKDOWN for the receipt, not an addition to the bill.
 */

export type TotalsLine = {
  quantity: number;
  unit_price: number;
  discount_amount: number;
  tax_rate?: number;
  /** Defaults to true, matching InventoryItem.price_includes_tax. */
  price_includes_tax?: boolean;
};

export type CartTotals = {
  subtotal: number;
  discounts: number;
  cgst: number;
  sgst: number;
  totalTax: number;
  grandTotal: number;
};

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function computeCartTotals(cart: TotalsLine[]): CartTotals {
  let subtotal = 0;
  let discounts = 0;
  let totalTax = 0;
  let exclusiveTax = 0;

  for (const item of cart) {
    const lineGross = item.quantity * item.unit_price;
    subtotal += lineGross;
    discounts += item.discount_amount;

    const net = lineGross - item.discount_amount;
    const rate = (item.tax_rate ?? 0) / 100;
    if (rate <= 0) continue;

    if (item.price_includes_tax === false) {
      // Added on top — and only this line's tax, never the whole cart's.
      const tax = net * rate;
      totalTax += tax;
      exclusiveTax += tax;
    } else {
      // Already inside the price; take it back out for the receipt only.
      totalTax += net - net / (1 + rate);
    }
  }

  const roundedTax = round2(totalTax);
  const cgst = round2(roundedTax / 2);

  return {
    subtotal: round2(subtotal),
    discounts: round2(discounts),
    cgst,
    // Paired so cgst + sgst is exactly totalTax, matching gst.py — otherwise a
    // half-paisa rounding gap shows on the receipt as tax that adds up wrong.
    sgst: round2(roundedTax - cgst),
    totalTax: roundedTax,
    grandTotal: round2(subtotal - discounts + exclusiveTax),
  };
}
