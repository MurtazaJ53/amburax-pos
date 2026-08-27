// Pinned before anything reads a Date. Without it these tests pass or fail
// according to where the machine happens to be: written on an IST laptop they
// were green, and four of them failed the moment they ran under UTC - which is
// what CI is. A test that only holds in one timezone proves nothing about a
// bug that only exists in another.
process.env.TZ = "Asia/Kolkata";

import { afterEach, describe, expect, it, vi } from "vitest";

import { daysAgoKey, monthStartKey, toDateKey, todayKey } from "./local-date";

/** Dates that belong to the shopkeeper's day, not to Greenwich.
 *
 *  Found in production: an expense entered at 01:47 IST on 28 August was filed
 *  against 27 August, while the sales beside it were filed against the 28th.
 *  The day book then reported that nothing had been paid out on a day money
 *  had visibly left the till.
 *
 *  Every test here pins a real instant with fake timers, because the bug only
 *  exists in the hours where the local date and the UTC date differ - which is
 *  exactly the window a test written at midday would never enter.
 */
describe("dates in the viewer's own timezone", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  /** Pretend "now" is this instant. The offset is written into the string, so
   *  it pins a real moment regardless of where the test runner sits. */
  function at(iso: string) {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(iso));
  }

  it("keeps the local day when UTC is still on the day before", () => {
    // 01:47 on 28 August in India is 20:17 on the 27th in UTC. The old code
    // returned the 27th; the shopkeeper's calendar says the 28th.
    at("2026-08-28T01:47:00+05:30");
    expect(todayKey()).toBe("2026-08-28");
  });

  it("agrees with UTC during the hours when they agree", () => {
    at("2026-08-28T14:00:00+05:30");
    expect(todayKey()).toBe("2026-08-28");
  });

  it("rolls over at local midnight, not at UTC midnight", () => {
    at("2026-08-27T23:59:00+05:30");
    expect(todayKey()).toBe("2026-08-27");

    at("2026-08-28T00:01:00+05:30");
    expect(todayKey()).toBe("2026-08-28");
  });

  it("starts the month on the first, not the last day of the previous one", () => {
    // new Date(2026, 7, 1) is local midnight, which in IST is 31 July in UTC.
    // Rendering that through toISOString put a month's report a day early.
    at("2026-08-15T10:00:00+05:30");
    expect(monthStartKey()).toBe("2026-08-01");
  });

  it("still starts the month on the first in the small hours", () => {
    at("2026-08-01T00:30:00+05:30");
    expect(monthStartKey()).toBe("2026-08-01");
  });

  it("counts days back on the local calendar", () => {
    at("2026-08-28T01:47:00+05:30");
    expect(daysAgoKey(0)).toBe("2026-08-28");
    expect(daysAgoKey(1)).toBe("2026-08-27");
    expect(daysAgoKey(28)).toBe("2026-07-31");
  });

  it("pads single-digit months and days", () => {
    // "2026-1-5" is not a date the API will accept, and the failure would be a
    // rejected save rather than anything visible here.
    expect(toDateKey(new Date(2026, 0, 5, 12, 0))).toBe("2026-01-05");
  });

  it("renders a date it is handed rather than the current time", () => {
    at("2026-08-28T01:47:00+05:30");
    expect(toDateKey(new Date(2026, 11, 31, 23, 30))).toBe("2026-12-31");
  });
});
