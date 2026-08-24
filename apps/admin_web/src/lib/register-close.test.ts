import { describe, expect, it } from "vitest";

import {
  closeRequestBody,
  discrepancy,
  emptyClose,
  expectedInTill,
  isMoneyInput,
  moneyValue,
  readRegisterPayload,
} from "./register-close";

const DAY = "2026-08-22";

describe("expectedInTill", () => {
  it("is the float plus the cash actually taken", () => {
    expect(expectedInTill(1000, 1405)).toBe(2405);
  });

  it("treats a nonsense float as zero rather than NaN", () => {
    expect(expectedInTill(Number.NaN, 1405)).toBe(1405);
  });

  it("never lets a negative float reduce what the drawer should hold", () => {
    expect(expectedInTill(-500, 1405)).toBe(1405);
  });
});

describe("discrepancy", () => {
  it("is withheld entirely until a person has entered the float", () => {
    expect(discrepancy({ openingFloat: 0, countedCash: 2405 }, 1405, false)).toBeNull();
  });

  it("is zero when the drawer matches", () => {
    expect(discrepancy({ openingFloat: 1000, countedCash: 2405 }, 1405, true)).toBe(0);
  });

  it("is negative when the drawer is short", () => {
    expect(discrepancy({ openingFloat: 1000, countedCash: 2305 }, 1405, true)).toBe(-100);
  });

  it("is positive when the drawer is over", () => {
    expect(discrepancy({ openingFloat: 1000, countedCash: 2505 }, 1405, true)).toBe(100);
  });
});

describe("readRegisterPayload", () => {
  it("reports an unanswered day when no close exists yet", () => {
    const read = readRegisterPayload(
      { business_date: DAY, cash_sales: "1405.00", expected_cash: "1405.00", session: null },
      DAY,
    );
    expect(read.cashSales).toBe(1405);
    expect(read.close.floatEntered).toBe(false);
    expect(read.close.closedAt).toBeNull();
  });

  it("reads a saved but still-open count", () => {
    const read = readRegisterPayload(
      {
        business_date: DAY,
        cash_sales: "1405.00",
        expected_cash: "2405.00",
        session: {
          opening_float: "1000.00",
          counted_cash: "2405.00",
          float_entered: true,
          notes: "handover to Asha",
          closed_at: null,
        },
      },
      DAY,
    );
    expect(read.close.openingFloat).toBe(1000);
    expect(read.close.countedCash).toBe(2405);
    expect(read.close.floatEntered).toBe(true);
    expect(read.close.notes).toBe("handover to Asha");
    expect(read.expectedCash).toBe(2405);
  });

  it("carries who locked the day, so a shortfall has a name against it", () => {
    const read = readRegisterPayload(
      {
        business_date: DAY,
        session: { closed_at: "2026-08-22T14:00:00Z", closed_by_name: "Asha Cashier" },
      },
      DAY,
    );
    expect(read.close.closedAt).toBe("2026-08-22T14:00:00Z");
    expect(read.close.closedByName).toBe("Asha Cashier");
  });

  it("survives a malformed payload as an unanswered day, not a confident zero", () => {
    const read = readRegisterPayload(null, DAY);
    expect(read.close).toEqual(emptyClose(DAY));
    expect(read.close.floatEntered).toBe(false);
  });

  it("does not trust a non-boolean float_entered", () => {
    const read = readRegisterPayload(
      { session: { float_entered: "yes", opening_float: "0" } },
      DAY,
    );
    expect(read.close.floatEntered).toBe(false);
  });

  it("falls back to the requested day when the payload names none", () => {
    expect(readRegisterPayload({ session: null }, DAY).close.date).toBe(DAY);
  });
});

describe("closeRequestBody", () => {
  it("sends the count and the lock intent, and nothing the server derives", () => {
    const body = closeRequestBody(
      {
        date: DAY,
        openingFloat: 1000,
        countedCash: 2405,
        notes: "",
        closedAt: null,
        floatEntered: true,
        closedByName: null,
      },
      true,
    );
    expect(body).toEqual({
      business_date: DAY,
      opening_float: 1000,
      counted_cash: 2405,
      float_entered: true,
      notes: "",
      lock: true,
    });
    // The expected figure and the discrepancy are the server's to compute.
    expect(body).not.toHaveProperty("expected_cash");
    expect(body).not.toHaveProperty("discrepancy");
  });
});

describe("isMoneyInput", () => {
  it("accepts the half-finished states typing a decimal passes through", () => {
    // If "10." were rejected the dot would be eaten as fast as it is typed.
    for (const text of ["", "1", "10", "10.", "10.5", "10.50"]) {
      expect(isMoneyInput(text)).toBe(true);
    }
  });

  it("rejects letters, which a text field would otherwise coerce to zero", () => {
    for (const text of ["abc", "10a", "1e5", "--"]) {
      expect(isMoneyInput(text)).toBe(false);
    }
  });

  it("rejects a negative, which in a drawer count is always a typo", () => {
    expect(isMoneyInput("-50")).toBe(false);
  });

  it("stops at paise, since no till holds a thousandth of a rupee", () => {
    expect(isMoneyInput("10.123")).toBe(false);
  });
});

describe("moneyValue", () => {
  it("reads a finished figure", () => {
    expect(moneyValue("2405.50")).toBe(2405.5);
  });

  it("treats an unfinished entry as zero rather than NaN", () => {
    expect(moneyValue("")).toBe(0);
    expect(moneyValue(".")).toBe(0);
  });
});
