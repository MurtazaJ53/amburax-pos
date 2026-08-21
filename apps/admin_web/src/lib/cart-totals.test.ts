import { describe, expect, it } from "vitest";

import { computeCartTotals } from "./cart-totals";

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
