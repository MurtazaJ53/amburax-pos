import { describe, expect, it } from "vitest";

import {
  buildHourlyBuckets,
  buildPaymentMix,
  hourInTimeZone,
  percentChange,
  shopDateKey,
  summariseToday,
} from "./dashboard-metrics";
import type { Sale } from "./types";

let counter = 0;

/** A minimal Sale — only the fields the metrics actually read carry meaning. */
function sale(overrides: Partial<Sale>): Sale {
  counter += 1;
  return {
    id: `sale-${counter}`,
    receipt_number: `R-${counter}`,
    customer_id: null,
    customer_name: "",
    customer_phone: "",
    subtotal_amount: "0.00",
    discount_amount: "0.00",
    total_amount: "0.00",
    amount_received: "0.00",
    amount_due: "0.00",
    payment_mode: "CASH",
    footer_note: "",
    note: "",
    sale_date: "2026-08-21",
    occurred_at: "2026-08-21T06:30:00Z",
    status: "COMPLETED",
    tombstone: false,
    source_meta_json: {},
    actor_name: null,
    item_count: 1,
    payment_count: 1,
    items: [],
    payments: [],
    ...overrides,
  } as Sale;
}

describe("reading the clock the shop reads", () => {
  it("puts a 06:30 UTC sale at noon for an Asia/Kolkata shop", () => {
    expect(hourInTimeZone("2026-08-21T06:30:00Z", "Asia/Kolkata")).toBe(12);
  });

  it("keeps midnight as hour 0, not hour 24", () => {
    expect(hourInTimeZone("2026-08-20T18:30:00Z", "Asia/Kolkata")).toBe(0);
  });

  it("returns null for a timestamp it cannot parse", () => {
    expect(hourInTimeZone("not-a-date", "Asia/Kolkata")).toBeNull();
  });

  it("dates the day in the shop's zone, so late-evening sales stay on today", () => {
    // 20:00 in Kolkata on the 21st is 14:30 UTC on the 21st.
    expect(shopDateKey(new Date("2026-08-21T14:30:00Z"), "Asia/Kolkata")).toBe("2026-08-21");
    // 01:00 in Kolkata on the 22nd is 19:30 UTC on the 21st — a different day
    // for the shop than for a UTC server.
    expect(shopDateKey(new Date("2026-08-21T19:30:00Z"), "Asia/Kolkata")).toBe("2026-08-22");
  });
});

describe("the hourly curve", () => {
  const sales = [
    sale({ occurred_at: "2026-08-21T04:30:00Z", total_amount: "500.00" }), // 10 AM
    sale({ occurred_at: "2026-08-21T04:45:00Z", total_amount: "300.00" }), // 10 AM
    sale({ occurred_at: "2026-08-21T07:30:00Z", total_amount: "900.00" }), // 1 PM
  ];

  it("sums each hour and counts its bills", () => {
    const buckets = buildHourlyBuckets(sales, "Asia/Kolkata");
    expect(buckets[0]).toMatchObject({ hour: 10, amount: 800, count: 2 });
  });

  it("fills the quiet hours between, so the line reads as a day", () => {
    const buckets = buildHourlyBuckets(sales, "Asia/Kolkata");
    expect(buckets.map((b) => b.hour)).toEqual([10, 11, 12, 13]);
    expect(buckets[1]).toMatchObject({ amount: 0, count: 0 });
  });

  it("does not pad beyond trading hours — a 10-to-1 shop shows four hours", () => {
    expect(buildHourlyBuckets(sales, "Asia/Kolkata")).toHaveLength(4);
  });

  it("is empty when nothing sold, so the card can say so honestly", () => {
    expect(buildHourlyBuckets([], "Asia/Kolkata")).toEqual([]);
  });
});

describe("bills that did not happen", () => {
  const withVoid = [
    sale({ total_amount: "1000.00" }),
    sale({ total_amount: "9999.00", status: "VOID" }),
    sale({ total_amount: "8888.00", tombstone: true }),
  ];

  it("leaves voided bills out of the payment mix", () => {
    const mix = buildPaymentMix(withVoid);
    expect(mix).toHaveLength(1);
    expect(mix[0].amount).toBe(1000);
  });

  it("leaves them out of the average bill too", () => {
    expect(summariseToday(withVoid, "Asia/Kolkata").averageBill).toBe(1000);
  });
});

describe("the payment mix", () => {
  const sales = [
    sale({ payment_mode: "CASH", total_amount: "400.00" }),
    sale({ payment_mode: "UPI", total_amount: "1000.00" }),
    sale({ payment_mode: "upi", total_amount: "600.00" }),
    sale({ payment_mode: "CARD", total_amount: "0.00" }),
  ];

  it("groups case-insensitively, so 'upi' and 'UPI' are one slice", () => {
    const mix = buildPaymentMix(sales);
    expect(mix.find((s) => s.key === "UPI")).toMatchObject({ amount: 1600, count: 2 });
  });

  it("drops zero-value modes rather than drawing invisible segments", () => {
    expect(buildPaymentMix(sales).some((s) => s.key === "CARD")).toBe(false);
  });

  it("holds a stable legend order regardless of arrival order", () => {
    expect(buildPaymentMix(sales).map((s) => s.key)).toEqual(["UPI", "CASH"]);
  });

  it("labels CREDIT as Khata, the word the shop uses", () => {
    const mix = buildPaymentMix([sale({ payment_mode: "CREDIT", total_amount: "10.00" })]);
    expect(mix[0].label).toBe("Khata");
  });
});

describe("the day summary", () => {
  const sales = [
    sale({ occurred_at: "2026-08-21T04:30:00Z", total_amount: "500.00", payment_mode: "CASH" }),
    sale({ occurred_at: "2026-08-21T07:30:00Z", total_amount: "900.00", payment_mode: "UPI" }),
  ];

  it("names the best hour by takings", () => {
    expect(summariseToday(sales, "Asia/Kolkata").bestHour).toMatchObject({
      hour: 13,
      label: "1 PM",
      amount: 900,
    });
  });

  it("reports cash separately, since that is what sits in the drawer", () => {
    expect(summariseToday(sales, "Asia/Kolkata").cashTaken).toBe(500);
  });

  it("has no best hour on a day with no sales", () => {
    expect(summariseToday([], "Asia/Kolkata").bestHour).toBeNull();
  });

  it("averages to zero rather than NaN on an empty day", () => {
    expect(summariseToday([], "Asia/Kolkata").averageBill).toBe(0);
  });
});

describe("comparing against yesterday", () => {
  it("reports a rise as a rounded percentage", () => {
    expect(percentChange(11800, 10000)).toBe(18);
  });

  it("reports a fall as a negative", () => {
    expect(percentChange(8000, 10000)).toBe(-20);
  });

  it("stays silent when yesterday was zero, instead of claiming +100%", () => {
    expect(percentChange(5000, 0)).toBeNull();
  });
});

describe("a bill settled in more than one tender", () => {
  // A split bill carries payment_mode "SPLIT" and the real amounts sit in
  // payments[]. Bucketing on the mode alone put the whole sale in a "Split"
  // slice, so its cash never reached the figure the drawer is counted
  // against at close — the money looked present in gross sales and absent
  // from the breakdown.
  const split = sale({
    payment_mode: "SPLIT",
    total_amount: "1500.00",
    payments: [
      { id: "p1", payment_method: "CASH", amount: "15.00", reference_code: "", note: "", occurred_at: "2026-08-21T06:30:00Z" },
      { id: "p2", payment_method: "UPI", amount: "1485.00", reference_code: "", note: "", occurred_at: "2026-08-21T06:30:00Z" },
    ],
  } as Partial<Sale>);

  it("puts the cash part in Cash, not in a Split bucket", () => {
    const mix = buildPaymentMix([split]);
    expect(mix.find((s) => s.key === "CASH")?.amount).toBe(15);
    expect(mix.some((s) => s.key === "SPLIT")).toBe(false);
  });

  it("puts the rest under its own tender", () => {
    expect(buildPaymentMix([split]).find((s) => s.key === "UPI")?.amount).toBe(1485);
  });

  it("keeps the split cash in the drawer figure", () => {
    expect(summariseToday([split], "Asia/Kolkata").cashTaken).toBe(15);
  });

  it("accounts for every rupee of the bill", () => {
    const total = buildPaymentMix([split]).reduce((sum, s) => sum + s.amount, 0);
    expect(total).toBe(1500);
  });

  it("still counts a bill that recorded no tender rows", () => {
    // Older sales, and the offline path, may arrive without payments[].
    // Losing them entirely would be worse than bucketing them by mode.
    const bare = sale({ payment_mode: "CASH", total_amount: "200.00", payments: [] });
    expect(buildPaymentMix([bare]).find((s) => s.key === "CASH")?.amount).toBe(200);
  });

  it("ignores a zero-value tender row", () => {
    const withZero = sale({
      payment_mode: "SPLIT",
      total_amount: "100.00",
      payments: [
        { id: "p1", payment_method: "CASH", amount: "100.00", reference_code: "", note: "", occurred_at: "2026-08-21T06:30:00Z" },
        { id: "p2", payment_method: "CARD", amount: "0.00", reference_code: "", note: "", occurred_at: "2026-08-21T06:30:00Z" },
      ],
    } as Partial<Sale>);
    expect(buildPaymentMix([withZero]).some((s) => s.key === "CARD")).toBe(false);
  });

  it("leaves a voided split bill out entirely", () => {
    expect(buildPaymentMix([{ ...split, status: "VOID" } as Sale])).toEqual([]);
  });
});
