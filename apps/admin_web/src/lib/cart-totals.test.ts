import { describe, expect, it } from "vitest";

import { computeCartTotals } from "./cart-totals";
import type { TotalsLine } from "./cart-totals";

/** The bill from the screenshot: one ₹150 line at 5% GST.
 *
 *  The till showed ₹157.50 and the server refused it with "Total must equal
 *  subtotal minus discount (150.00000)". The till was wrong, not the server:
 *  price_includes_tax defaults to true, so ₹150 already contains the GST.
 */
const MRP_LINE = {
  quantity: 1,
  unit_price: 150,
  discount_amount: 0,
  tax_rate: 5,
};

describe("a tax-inclusive price (the default)", () => {
  it("charges the shelf price, not the shelf price plus tax", () => {
    expect(computeCartTotals([MRP_LINE]).grandTotal).toBe(150);
  });

  it("still reports the tax contained within, for the receipt", () => {
    // 150 / 1.05 = 142.857..., so tax = 7.142...
    expect(computeCartTotals([MRP_LINE]).totalTax).toBeCloseTo(7.14, 2);
  });

  it("splits that tax into cgst and sgst that sum to it exactly", () => {
    const t = computeCartTotals([MRP_LINE]);
    expect(t.cgst + t.sgst).toBeCloseTo(t.totalTax, 10);
  });

  it("matches subtotal minus discount, which is what the server validates", () => {
    const t = computeCartTotals([MRP_LINE]);
    expect(t.grandTotal).toBe(t.subtotal - t.discounts);
  });
});

describe("a tax-exclusive price", () => {
  const NET_LINE = { ...MRP_LINE, price_includes_tax: false };

  it("adds the tax on top", () => {
    expect(computeCartTotals([NET_LINE]).grandTotal).toBe(157.5);
  });

  it("reports the tax it added", () => {
    expect(computeCartTotals([NET_LINE]).totalTax).toBeCloseTo(7.5, 2);
  });
});

describe("mixed and awkward carts", () => {
  it("only the exclusive line adds anything", () => {
    const totals = computeCartTotals([
      MRP_LINE,
      { ...MRP_LINE, price_includes_tax: false },
    ]);
    // 150 inclusive + 150 net + 7.50 its own tax
    expect(totals.grandTotal).toBe(307.5);
  });

  it("a zero-rated item adds no tax and no total", () => {
    const totals = computeCartTotals([{ ...MRP_LINE, tax_rate: 0 }]);
    expect(totals.totalTax).toBe(0);
    expect(totals.grandTotal).toBe(150);
  });

  it("an item with no tax_rate at all is treated as zero-rated", () => {
    const totals = computeCartTotals([
      { quantity: 2, unit_price: 40, discount_amount: 0 },
    ]);
    expect(totals.totalTax).toBe(0);
    expect(totals.grandTotal).toBe(80);
  });

  it("a line discount reduces the bill and the tax inside it", () => {
    const totals = computeCartTotals([{ ...MRP_LINE, discount_amount: 50 }]);
    expect(totals.grandTotal).toBe(100);
    expect(totals.totalTax).toBeCloseTo(100 - 100 / 1.05, 2);
  });

  it("a fractional weight quantity is priced correctly", () => {
    // 0.75 kg at 120/kg — the grocery case weight_selling exists for.
    const totals = computeCartTotals([
      { quantity: 0.75, unit_price: 120, discount_amount: 0, tax_rate: 0 },
    ]);
    expect(totals.grandTotal).toBe(90);
  });

  it("an empty cart is zero, not NaN", () => {
    const totals = computeCartTotals([]);
    expect(totals.grandTotal).toBe(0);
    expect(totals.totalTax).toBe(0);
  });

  it("does not leak floating point noise into the bill", () => {
    // 0.1 + 0.2 territory: three lines that would otherwise end .00000000004
    const totals = computeCartTotals([
      { quantity: 3, unit_price: 0.1, discount_amount: 0 },
      { quantity: 3, unit_price: 0.2, discount_amount: 0 },
    ]);
    expect(totals.grandTotal).toBe(0.9);
  });
});

describe("the summary must add up on screen", () => {
  /** The defect the shopkeeper spotted: the cart showed
   *    Subtotal 150.00 / Tax 7.14 / GRAND TOTAL 150.00
   *  Every stored figure was right, but read as arithmetic it is nonsense —
   *  the 7.14 was already inside the 150 and nothing said so. A cashier
   *  concludes the till is broken; a customer reading over their shoulder
   *  concludes worse.
   */
  const cases: Array<[string, TotalsLine[]]> = [
    ["tax-inclusive", [MRP_LINE]],
    ["tax-exclusive", [{ ...MRP_LINE, price_includes_tax: false }]],
    ["zero-rated", [{ ...MRP_LINE, tax_rate: 0 }]],
    ["discounted", [{ ...MRP_LINE, discount_amount: 37.5 }]],
    [
      "mixed",
      [MRP_LINE, { ...MRP_LINE, price_includes_tax: false }, { ...MRP_LINE, tax_rate: 0 }],
    ],
    ["empty", []],
    [
      "awkward rates",
      [
        { quantity: 3, unit_price: 10.01, discount_amount: 0, tax_rate: 12 },
        { quantity: 1, unit_price: 99.99, discount_amount: 0, tax_rate: 18 },
      ],
    ],
  ];

  it.each(cases)("taxable value + GST equals the total (%s)", (_label, cart) => {
    const t = computeCartTotals(cart);
    expect(t.taxableValue + t.totalTax).toBeCloseTo(t.grandTotal, 2);
  });

  it.each(cases)("cgst + sgst equals the GST shown (%s)", (_label, cart) => {
    const t = computeCartTotals(cart);
    expect(t.cgst + t.sgst).toBeCloseTo(t.totalTax, 10);
  });

  it("the taxable value is below the total when tax is inside the price", () => {
    const t = computeCartTotals([MRP_LINE]);
    expect(t.taxableValue).toBeCloseTo(142.86, 2);
    expect(t.grandTotal).toBe(150);
  });

  it("the taxable value equals the subtotal when tax is added on top", () => {
    const t = computeCartTotals([{ ...MRP_LINE, price_includes_tax: false }]);
    expect(t.taxableValue).toBeCloseTo(150, 2);
    expect(t.grandTotal).toBe(157.5);
  });
});

describe("inter-state supply uses IGST, not CGST+SGST", () => {
  /** Every client hardcoded intra-state, so an inter-state sale printed
   *  CGST+SGST on an invoice that legally requires IGST — while the backend
   *  stored the right thing. The customer's copy disagreed with the shop's
   *  return, and inter-state is routine for wholesalers. */
  it("splits into cgst and sgst within the same state", () => {
    const t = computeCartTotals([MRP_LINE], { intraState: true });
    expect(t.igst).toBe(0);
    expect(t.cgst + t.sgst).toBeCloseTo(t.totalTax, 10);
  });

  it("charges igst alone across states", () => {
    const t = computeCartTotals([MRP_LINE], { intraState: false });
    expect(t.cgst).toBe(0);
    expect(t.sgst).toBe(0);
    expect(t.igst).toBeCloseTo(t.totalTax, 10);
  });

  it("never charges both — that would double the tax on the invoice", () => {
    for (const intraState of [true, false]) {
      const t = computeCartTotals([MRP_LINE], { intraState });
      expect(t.cgst + t.sgst + t.igst).toBeCloseTo(t.totalTax, 10);
    }
  });

  it("the total the customer pays is identical either way", () => {
    // Only the split changes; the money does not.
    const intra = computeCartTotals([MRP_LINE], { intraState: true });
    const inter = computeCartTotals([MRP_LINE], { intraState: false });
    expect(intra.grandTotal).toBe(inter.grandTotal);
    expect(intra.totalTax).toBe(inter.totalTax);
  });

  it("defaults to intra-state, because a walk-in sale is", () => {
    const t = computeCartTotals([MRP_LINE]);
    expect(t.igst).toBe(0);
    expect(t.cgst).toBeGreaterThan(0);
  });
});
