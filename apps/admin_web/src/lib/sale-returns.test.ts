import { describe, expect, it } from "vitest";

import { refundsBySale, toReturnRows } from "./sale-returns";
import type { SaleReturnRecord } from "./types";

function ret(overrides: Partial<SaleReturnRecord> = {}): SaleReturnRecord {
  return {
    id: "r-1",
    reference: "RET-1",
    sale_id: "s-1",
    receipt_number: "S-ABC",
    refund_mode: "CASH",
    refund_amount: "100.00",
    note: "",
    occurred_at: "2026-08-21T06:30:00Z",
    ...overrides,
  };
}

describe("reading the returns payload", () => {
  // The endpoint answers { returns: [...], refunded_total } and treating that
  // as a list crashed the entire sales page with "returns is not iterable".
  it("pulls the rows out of the wrapper object", () => {
    const rows = toReturnRows({ returns: [ret()], refunded_total: "100.00" });
    expect(rows).toHaveLength(1);
  });

  it("still accepts a bare list, in case the endpoint is ever simplified", () => {
    expect(toReturnRows([ret()])).toHaveLength(1);
  });

  it("never throws on a shape it does not recognise", () => {
    // The sales screen must render even when this secondary panel cannot.
    expect(toReturnRows(null)).toEqual([]);
    expect(toReturnRows(undefined)).toEqual([]);
    expect(toReturnRows({})).toEqual([]);
    expect(toReturnRows({ returns: "nope" })).toEqual([]);
    expect(toReturnRows("nope")).toEqual([]);
  });
});

describe("totalling refunds against each sale", () => {
  it("adds up several returns on one bill", () => {
    expect(
      refundsBySale([
        ret({ id: "r-1", refund_amount: "60.00" }),
        ret({ id: "r-2", refund_amount: "40.00" }),
      ]),
    ).toEqual({ "s-1": 100 });
  });

  it("keeps separate bills apart", () => {
    const totals = refundsBySale([ret(), ret({ sale_id: "s-2", refund_amount: "25.00" })]);
    expect(totals).toEqual({ "s-1": 100, "s-2": 25 });
  });

  it("ignores a row with no sale attached", () => {
    expect(refundsBySale([ret({ sale_id: "" })])).toEqual({});
  });

  it("ignores an unparseable or zero refund rather than writing NaN", () => {
    expect(refundsBySale([ret({ refund_amount: "abc" })])).toEqual({});
    expect(refundsBySale([ret({ refund_amount: "0.00" })])).toEqual({});
  });

  it("returns an empty map for no returns", () => {
    expect(refundsBySale([])).toEqual({});
  });
});
