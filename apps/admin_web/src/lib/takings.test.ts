import { describe, expect, it } from "vitest";

import {
  axisLabel,
  EMPTY_TAKINGS,
  peakLabel,
  peakPoint,
  percentChange,
  readTakings,
} from "./takings";

describe("readTakings", () => {
  it("reads a well-formed payload", () => {
    const takings = readTakings({
      from: "2026-08-22",
      to: "2026-08-22",
      days: 1,
      total: "1405.00",
      bill_count: 3,
      average_bill: "468.33",
      previous_total: "1200.00",
      granularity: "hour",
      series: [{ label: "09:00", amount: "405.00" }],
      mix: [{ key: "CASH", label: "Cash", amount: "1405.00" }],
    });
    expect(takings.total).toBe(1405);
    expect(takings.billCount).toBe(3);
    expect(takings.series).toEqual([{ label: "09:00", amount: 405 }]);
    expect(takings.mix[0].label).toBe("Cash");
  });

  it("yields empty figures for a malformed payload, never partial ones", () => {
    // A headline total with a series that failed to parse is a chart that
    // contradicts the number printed above it.
    expect(readTakings(null)).toEqual(EMPTY_TAKINGS);
    expect(readTakings("nonsense")).toEqual(EMPTY_TAKINGS);
  });

  it("drops zero slices so the mix bar has no invisible segments", () => {
    const takings = readTakings({
      mix: [
        { key: "CASH", label: "Cash", amount: "0" },
        { key: "UPI", label: "UPI", amount: "50" },
      ],
    });
    expect(takings.mix).toHaveLength(1);
  });

  it("keeps zero points in the series, which are real quiet periods", () => {
    const takings = readTakings({
      series: [{ label: "09:00", amount: "0" }, { label: "10:00", amount: "5" }],
    });
    expect(takings.series).toHaveLength(2);
  });

  it("falls back to hourly rather than trusting an unknown granularity", () => {
    expect(readTakings({ granularity: "fortnight" }).granularity).toBe("hour");
  });
});

describe("axisLabel", () => {
  it("leaves an hour alone", () => {
    expect(axisLabel("09:00", "hour")).toBe("09:00");
  });

  it("reads a day the way a person says it", () => {
    expect(axisLabel("2026-08-22", "day")).toBe("22 Aug");
  });

  it("names a month with its year, so a 12-month chart cannot ambiguate", () => {
    expect(axisLabel("2026-08", "month")).toBe("Aug 26");
  });

  it("returns the raw label rather than inventing a month for bad input", () => {
    expect(axisLabel("2026-13", "month")).toBe("2026-13");
    expect(axisLabel("rubbish", "day")).toBe("rubbish");
  });
});

describe("peakPoint", () => {
  it("finds the busiest bucket", () => {
    const peak = peakPoint([
      { label: "09:00", amount: 100 },
      { label: "10:00", amount: 400 },
    ]);
    expect(peak?.label).toBe("10:00");
  });

  it("is null when nothing was taken, rather than naming a zero hour as best", () => {
    expect(peakPoint([{ label: "09:00", amount: 0 }])).toBeNull();
    expect(peakPoint([])).toBeNull();
  });
});

describe("percentChange", () => {
  it("computes a rise and a fall", () => {
    expect(percentChange(120, 100)).toBe(20);
    expect(percentChange(80, 100)).toBe(-20);
  });

  it("is null when the previous period took nothing", () => {
    // Every figure is infinitely more than zero. "+100%" would read as a
    // real comparison against a period that had no trading at all.
    expect(percentChange(500, 0)).toBeNull();
  });

  it("is null for unusable numbers", () => {
    expect(percentChange(Number.NaN, 100)).toBeNull();
  });
});

describe("peakLabel", () => {
  it("names the bucket the chart is actually showing", () => {
    expect(peakLabel("hour")).toBe("Best hour");
    expect(peakLabel("day")).toBe("Best day");
    expect(peakLabel("month")).toBe("Best month");
  });
});
