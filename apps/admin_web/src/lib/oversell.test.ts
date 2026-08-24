import { describe, expect, it } from "vitest";

import {
  isOversell,
  oversellLines,
  oversellSummary,
  resultingStock,
  unrecordedUnits,
} from "./oversell";

describe("resultingStock", () => {
  it("is what the shelf reads after the line", () => {
    expect(resultingStock({ available_stock: 5, quantity: 2 })).toBe(3);
  });

  it("goes negative when more is sold than was recorded", () => {
    expect(resultingStock({ available_stock: 0, quantity: 3 })).toBe(-3);
  });

  it("keeps going down from an already-negative count", () => {
    expect(resultingStock({ available_stock: -2, quantity: 1 })).toBe(-3);
  });

  it("treats unreadable figures as zero rather than NaN", () => {
    expect(resultingStock({ available_stock: NaN, quantity: 2 })).toBe(-2);
  });
});

describe("isOversell", () => {
  it("is false when the shelf exactly empties", () => {
    // Selling the last one is a normal sale, not a problem to flag.
    expect(isOversell({ available_stock: 3, quantity: 3 })).toBe(false);
  });

  it("is true one unit past that", () => {
    expect(isOversell({ available_stock: 3, quantity: 4 })).toBe(true);
  });
});

describe("unrecordedUnits", () => {
  it("counts only the units that were never recorded as bought", () => {
    expect(unrecordedUnits({ available_stock: 2, quantity: 5 })).toBe(3);
  });

  it("is zero for a sale that stays within the count", () => {
    expect(unrecordedUnits({ available_stock: 9, quantity: 1 })).toBe(0);
  });
});

describe("oversellSummary", () => {
  it("says nothing when the cart is within stock", () => {
    expect(oversellSummary([{ available_stock: 5, quantity: 1 }])).toBe("");
  });

  it("never frames a completed sale as an error", () => {
    const message = oversellSummary([{ available_stock: 0, quantity: 1 }]);
    expect(message).toContain("Sale still goes through");
    expect(message.toLowerCase()).not.toContain("error");
    expect(message.toLowerCase()).not.toContain("cannot");
  });

  it("counts the lines, not the units", () => {
    const message = oversellSummary([
      { available_stock: 0, quantity: 9 },
      { available_stock: 0, quantity: 4 },
      { available_stock: 50, quantity: 1 },
    ]);
    expect(message.startsWith("2 items")).toBe(true);
  });

  it("uses the singular for one line", () => {
    expect(oversellSummary([{ available_stock: 0, quantity: 1 }]).startsWith("1 item ")).toBe(
      true,
    );
  });
});

describe("oversellLines", () => {
  it("returns only the offending lines, keeping their own shape", () => {
    const cart = [
      { available_stock: 0, quantity: 2, name: "Socks" },
      { available_stock: 10, quantity: 2, name: "Caps" },
    ];
    expect(oversellLines(cart).map((l) => l.name)).toEqual(["Socks"]);
  });

  it("is empty for an empty cart", () => {
    expect(oversellLines([])).toEqual([]);
  });
});

describe("untracked items never raise a shortfall", () => {
  it("stays silent for an item that was never given stock", () => {
    // "Will go to -1" against a count nobody ever made is a warning about
    // nothing, and it trains the cashier to ignore the real ones.
    expect(isOversell({ available_stock: 0, quantity: 1, is_tracked: false })).toBe(false);
  });

  it("still warns for a tracked item", () => {
    expect(isOversell({ available_stock: 0, quantity: 1, is_tracked: true })).toBe(true);
  });

  it("warns when tracking is unknown, rather than going quiet by default", () => {
    // Absent means "not told". Silence would hide real shortfalls on any
    // caller that has not been updated yet.
    expect(isOversell({ available_stock: 0, quantity: 1 })).toBe(true);
  });

  it("keeps untracked lines out of the cart summary", () => {
    const message = oversellSummary([
      { available_stock: 0, quantity: 3, is_tracked: false },
      { available_stock: 1, quantity: 4, is_tracked: true },
    ]);
    expect(message.startsWith("1 item ")).toBe(true);
  });

  it("says nothing at all when every oversold line is untracked", () => {
    expect(
      oversellSummary([{ available_stock: 0, quantity: 3, is_tracked: false }]),
    ).toBe("");
  });
});
