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

export type TotalsOptions = {
  /** CGST+SGST when the buyer is in the shop's own state, IGST when not.
   *
   *  Every client hardcoded this to true, so an inter-state sale printed
   *  CGST+SGST on an invoice that legally requires IGST — while the backend,
   *  which derives it properly from place of supply (sales/gst.py
   *  is_intra_state), stored the right thing. The document the customer takes
   *  away disagreed with the return the shop files, and inter-state is routine
   *  for the wholesalers this matters most to.
   *
   *  Defaults true: a walk-in retail sale is intra-state. */
  intraState?: boolean;
};

export type CartTotals = {
  subtotal: number;
  discounts: number;
  /** The value the tax is charged ON, i.e. the bill excluding GST.
   *
   *  Exists so the summary ADDS UP. Showing "Subtotal 150 / Tax 7.14 / Total
   *  150" is arithmetic nonsense on screen even when the stored figures are
   *  right, and a cashier or customer reading it concludes the till is broken.
   *  taxableValue + totalTax === grandTotal in every case: tax-inclusive,
   *  tax-exclusive and zero-rated. That is also the format a GST invoice is
   *  expected to take. */
  taxableValue: number;
  cgst: number;
  sgst: number;
  /** Non-zero only on an inter-state supply, where it replaces cgst+sgst. */
  igst: number;
  totalTax: number;
  grandTotal: number;
};

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function computeCartTotals(
  cart: TotalsLine[],
  options: TotalsOptions = {},
): CartTotals {
  const intraState = options.intraState ?? true;
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
  // Intra-state splits into CGST+SGST; inter-state is IGST alone. Never both.
  const cgst = intraState ? round2(roundedTax / 2) : 0;

  const grandTotal = round2(subtotal - discounts + exclusiveTax);

  return {
    subtotal: round2(subtotal),
    discounts: round2(discounts),
    // Derived from the total rather than accumulated separately, so the three
    // figures can never disagree by a rounding step.
    taxableValue: round2(grandTotal - roundedTax),
    cgst,
    // Paired so cgst + sgst is exactly totalTax, matching gst.py — otherwise a
    // half-paisa rounding gap shows on the receipt as tax that adds up wrong.
    sgst: intraState ? round2(roundedTax - cgst) : 0,
    igst: intraState ? 0 : roundedTax,
    totalTax: roundedTax,
    grandTotal,
  };
}
