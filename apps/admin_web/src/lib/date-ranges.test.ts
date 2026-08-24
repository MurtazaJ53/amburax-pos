import { describe, expect, it } from "vitest";

import {
  RANGE_OPTIONS,
  daysInRange,
  granularityFor,
  isValidRange,
  previousPeriod,
  resolveRange,
  shiftDate,
  shopToday,
} from "./date-ranges";

const TODAY = "2026-08-22";

describe("shopToday", () => {
  it("reads the shop's calendar, not the browser's", () => {
    // 22:30 UTC is already the 23rd in Kolkata. A shop closing late must not
    // have its takings land on the wrong trading day.
    const instant = new Date("2026-08-22T22:30:00Z");
    expect(shopToday("Asia/Kolkata", instant)).toBe("2026-08-23");
    expect(shopToday("UTC", instant)).toBe("2026-08-22");
  });

  it("handles a timezone behind UTC too", () => {
    const instant = new Date("2026-08-22T02:00:00Z");
    expect(shopToday("America/New_York", instant)).toBe("2026-08-21");
  });
});

describe("shiftDate", () => {
  it("moves whole days", () => {
    expect(shiftDate("2026-08-22", -1)).toBe("2026-08-21");
    expect(shiftDate("2026-08-22", 1)).toBe("2026-08-23");
  });

  it("crosses month and year boundaries", () => {
    expect(shiftDate("2026-03-01", -1)).toBe("2026-02-28");
    expect(shiftDate("2026-01-01", -1)).toBe("2025-12-31");
  });

  it("gets a leap day right", () => {
    expect(shiftDate("2028-03-01", -1)).toBe("2028-02-29");
  });

  it("survives a daylight-saving boundary without repeating a day", () => {
    // 2026-03-08 is the US spring-forward. Local-time arithmetic can land on
    // the same date twice here; UTC arithmetic cannot.
    expect(shiftDate("2026-03-08", -1)).toBe("2026-03-07");
    expect(shiftDate("2026-03-07", 1)).toBe("2026-03-08");
  });
});

describe("daysInRange", () => {
  it("counts both ends", () => {
    expect(daysInRange({ from: TODAY, to: TODAY })).toBe(1);
    expect(daysInRange({ from: "2026-08-16", to: "2026-08-22" })).toBe(7);
  });
});

describe("resolveRange", () => {
  it("makes today a single day", () => {
    const range = resolveRange("today", TODAY);
    expect(range).toMatchObject({ from: TODAY, to: TODAY, granularity: "hour" });
  });

  it("makes yesterday a single day that excludes today", () => {
    const range = resolveRange("yesterday", TODAY);
    expect(range.from).toBe("2026-08-21");
    expect(range.to).toBe("2026-08-21");
  });

  it("ends every rolling window today, including today", () => {
    // "Last 30 days" means up to and including this trading day, not a window
    // that stops at midnight last night.
    for (const key of ["last7", "last30", "last90", "last365"] as const) {
      expect(resolveRange(key, TODAY).to).toBe(TODAY);
    }
  });

  it("counts the rolling windows inclusively", () => {
    expect(daysInRange(resolveRange("last7", TODAY))).toBe(7);
    expect(daysInRange(resolveRange("last30", TODAY))).toBe(30);
    expect(daysInRange(resolveRange("last90", TODAY))).toBe(90);
    expect(daysInRange(resolveRange("last365", TODAY))).toBe(365);
  });

  it("swaps custom dates entered the wrong way round", () => {
    const range = resolveRange("custom", TODAY, { from: "2026-08-20", to: "2026-08-10" });
    expect(range.from).toBe("2026-08-10");
    expect(range.to).toBe("2026-08-20");
  });

  it("falls back to today for a half-filled custom range", () => {
    const range = resolveRange("custom", TODAY, { from: "2026-08-01" });
    expect(range.to).toBe(TODAY);
  });
});

describe("granularityFor", () => {
  it("uses hours for a single day", () => {
    expect(granularityFor({ from: TODAY, to: TODAY })).toBe("hour");
  });

  it("uses days for a month or a quarter", () => {
    expect(granularityFor(resolveRange("last30", TODAY))).toBe("day");
    expect(granularityFor(resolveRange("last90", TODAY))).toBe("day");
  });

  it("switches to months for a year, which 365 bars cannot show", () => {
    expect(granularityFor(resolveRange("last365", TODAY))).toBe("month");
  });
});

describe("previousPeriod", () => {
  it("is the day before, for a single day", () => {
    expect(previousPeriod({ from: TODAY, to: TODAY })).toEqual({
      from: "2026-08-21",
      to: "2026-08-21",
    });
  });

  it("is equally long, so the comparison is not manufactured", () => {
    const current = resolveRange("last30", TODAY);
    const previous = previousPeriod(current);
    expect(daysInRange(previous)).toBe(daysInRange(current));
  });

  it("ends the day before the current window starts, never overlapping it", () => {
    const current = resolveRange("last7", TODAY);
    const previous = previousPeriod(current);
    expect(previous.to).toBe(shiftDate(current.from, -1));
    expect(previous.to < current.from).toBe(true);
  });
});

describe("isValidRange", () => {
  it("accepts a well-formed range", () => {
    expect(isValidRange({ from: "2026-01-01", to: "2026-01-31" })).toBe(true);
  });

  it("rejects a half-filled or malformed one", () => {
    expect(isValidRange({ from: "2026-01-01" })).toBe(false);
    expect(isValidRange({ from: "01/01/2026", to: "2026-01-31" })).toBe(false);
    expect(isValidRange({})).toBe(false);
  });
});

describe("the longer presets", () => {
  it("counts six and twelve months inclusively", () => {
    expect(daysInRange(resolveRange("last180", TODAY))).toBe(180);
    expect(daysInRange(resolveRange("last365", TODAY))).toBe(365);
  });

  it("ends both windows today", () => {
    expect(resolveRange("last180", TODAY).to).toBe(TODAY);
    expect(resolveRange("last365", TODAY).to).toBe(TODAY);
  });

  it("buckets six months by month, not by day", () => {
    // 180 daily bars is not a chart anyone reads.
    expect(resolveRange("last180", TODAY).granularity).toBe("month");
  });
});

describe("all time", () => {
  it("has no start date", () => {
    const range = resolveRange("all", TODAY);
    expect(range.unbounded).toBe(true);
    expect(range.from).toBe("");
    expect(range.to).toBe(TODAY);
  });

  it("offers no comparison, because there is nothing before all of history", () => {
    expect(resolveRange("all", TODAY).comparisonLabel).toBe("");
  });

  it("buckets by month", () => {
    expect(resolveRange("all", TODAY).granularity).toBe("month");
  });

  it("is not a valid bounded range, so callers must omit `from`", () => {
    expect(isValidRange(resolveRange("all", TODAY))).toBe(false);
  });
});

describe("every preset is resolvable", () => {
  it("returns a labelled range ending on or before today for each option", () => {
    // Yesterday is the one that does NOT end today, which is the point of it.
    for (const option of RANGE_OPTIONS) {
      const range = resolveRange(option.key, TODAY);
      expect(range.label).not.toBe("");
      expect(range.to <= TODAY).toBe(true);
      expect(range.to).not.toBe("");
    }
  });
});
