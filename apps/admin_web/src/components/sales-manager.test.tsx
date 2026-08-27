import { describe, expect, it } from "vitest";

import { toSaleOrder, type ApiSale } from "./sales-manager";

/** A bill as the sales API returns it, with only the fields under test set. */
function apiSale(fields: Partial<ApiSale>): ApiSale {
  return {
    id: "11111111-1111-1111-1111-111111111111",
    total_amount: "0.00",
    amount_received: "0.00",
    amount_due: "0.00",
    payments: [],
    ...fields,
  } as ApiSale;
}

describe("what a sale on the sales screen says is still owed", () => {
  it("takes the amount owed from the sale, not from a CREDIT payment row", () => {
    // A credit sale writes no CREDIT payment row - that is precisely the fix
    // that stopped the till counting khata as money received. Deriving the
    // figure from tenders made every credit sale after that fix read as
    // nothing owed.
    const sale = toSaleOrder(
      apiSale({
        total_amount: "285.00",
        amount_received: "0.00",
        amount_due: "285.00",
        payments: [],
      }),
    );

    expect(sale.payment_breakdown.khata_due).toBe(285);
  });

  it("counts only the unpaid part of a split bill", () => {
    const sale = toSaleOrder(
      apiSale({
        total_amount: "950.00",
        amount_received: "700.00",
        amount_due: "250.00",
        payments: [{ payment_method: "CASH", amount: "700.00" }],
      } as Partial<ApiSale>),
    );

    expect(sale.payment_breakdown.cash).toBe(700);
    expect(sale.payment_breakdown.khata_due).toBe(250);
  });

  it("makes the tenders add up to the bill", () => {
    // The regression showed itself here first: 335 + 570 against gross sales
    // of 1,190. A split that does not sum to the bill means money is being
    // shown in one place and not another, whichever number is wrong.
    const sale = toSaleOrder(
      apiSale({
        total_amount: "1000.00",
        amount_received: "600.00",
        amount_due: "400.00",
        payments: [
          { payment_method: "CASH", amount: "350.00" },
          { payment_method: "UPI", amount: "250.00" },
        ],
      } as Partial<ApiSale>),
    );

    const { cash, card, upi, khata_due } = sale.payment_breakdown;
    expect(cash + card + upi + khata_due).toBe(sale.total_amount);
  });

  it("shows nothing owed on a bill that was paid in full", () => {
    const sale = toSaleOrder(
      apiSale({
        total_amount: "120.00",
        amount_received: "120.00",
        amount_due: "0.00",
        payments: [{ payment_method: "CARD", amount: "120.00" }],
      } as Partial<ApiSale>),
    );

    expect(sale.payment_breakdown.khata_due).toBe(0);
    expect(sale.payment_breakdown.card).toBe(120);
  });

  it("treats a missing amount as nothing owed rather than NaN", () => {
    const sale = toSaleOrder(apiSale({ amount_due: undefined as unknown as string }));
    expect(sale.payment_breakdown.khata_due).toBe(0);
  });
});
