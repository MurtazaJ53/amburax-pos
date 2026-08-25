import { describe, expect, it } from "vitest";

import { EMPTY_HISTORY, discountRate, readMemberHistory } from "./member-history";

describe("readMemberHistory", () => {
  it("reads a full payload", () => {
    const history = readMemberHistory({
      membership_id: "m1",
      member_name: "Asha",
      role: "cashier",
      has_pos_pin: true,
      from: "2026-08-01",
      to: "2026-08-31",
      attendance: {
        present: 20,
        half_days: 2,
        leave: 1,
        absent: 0,
        days_worked: "21.0",
        hours: "168.00",
        overtime: "6.00",
        bonus: "500.00",
      },
      sales: {
        bills: 140,
        gross: "46000.00",
        collected: "45000.00",
        discount_given: "900.00",
        average_bill: "328.57",
        per_day_worked: "2190.48",
      },
      recent_sessions: [
        { id: "s1", session_date: "2026-08-30", status: "PRESENT", total_hours: "8" },
      ],
    });

    expect(history.name).toBe("Asha");
    expect(history.daysWorked).toBe(21);
    expect(history.bills).toBe(140);
    expect(history.averageBill).toBeCloseTo(328.57);
    expect(history.sessions).toHaveLength(1);
    expect(history.hasPin).toBe(true);
  });

  it("keeps an unanswerable average as null, never zero", () => {
    // Zero is a claim: it says they averaged nothing per bill. Null says
    // there were no bills to average.
    const history = readMemberHistory({ sales: { bills: 0, average_bill: null } });
    expect(history.averageBill).toBeNull();
    expect(history.perDayWorked).toBeNull();
  });

  it("returns empty figures for a malformed payload rather than partial ones", () => {
    expect(readMemberHistory(null)).toEqual(EMPTY_HISTORY);
    expect(readMemberHistory("nonsense")).toEqual(EMPTY_HISTORY);
  });

  it("does not trust a non-boolean pin flag", () => {
    expect(readMemberHistory({ has_pos_pin: "yes" }).hasPin).toBe(false);
  });

  it("survives sessions that are not objects", () => {
    const history = readMemberHistory({ recent_sessions: [null, 5] });
    expect(history.sessions).toHaveLength(2);
    expect(history.sessions[0].status).toBe("ABSENT");
  });
});

describe("discountRate", () => {
  it("is a share of what they actually sold", () => {
    const history = { ...EMPTY_HISTORY, gross: 10000, discountGiven: 500 };
    expect(discountRate(history)).toBeCloseTo(5);
  });

  it("is null when they sold nothing, rather than dividing by zero", () => {
    // A busy cashier always gives away more rupees than a quiet one, so the
    // rupee total alone compares nobody fairly.
    expect(discountRate({ ...EMPTY_HISTORY, gross: 0, discountGiven: 200 })).toBeNull();
  });
});
