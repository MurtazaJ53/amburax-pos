import { describe, expect, it } from "vitest";

import {
  lineTotal,
  packIsComplete,
  packSummary,
  packToUnitCost,
  packsToUnits,
} from "./pack-maths";

const entry = (over: Partial<Parameters<typeof packsToUnits>[0]> = {}) => ({
  packs: "2",
  unitsPerPack: "50",
  packCost: "2000",
  ...over,
});

describe("packsToUnits", () => {
  it("turns two bags of fifty into a hundred", () => {
    expect(packsToUnits(entry())).toBe(100);
  });

  it("handles a fractional pack, because half a sack is a real delivery", () => {
    expect(packsToUnits(entry({ packs: "1.5" }))).toBe(75);
  });

  it("is zero until both halves are given, never a partial guess", () => {
    expect(packsToUnits(entry({ unitsPerPack: "" }))).toBe(0);
    expect(packsToUnits(entry({ packs: "" }))).toBe(0);
  });

  it("refuses nonsense rather than producing NaN", () => {
    expect(packsToUnits(entry({ packs: "two" }))).toBe(0);
    expect(packsToUnits(entry({ packs: "-3" }))).toBe(0);
  });
});

describe("packToUnitCost", () => {
  it("divides the pack price by what is in the pack", () => {
    expect(packToUnitCost(entry())).toBe(40);
  });

  it("rounds to paise", () => {
    expect(packToUnitCost(entry({ unitsPerPack: "3", packCost: "100" }))).toBe(33.33);
  });

  it("is null when it cannot be worked out, never zero", () => {
    // A zero unit cost becomes the item's cost price and every margin built
    // on it. An empty field is recoverable; a confident zero is not.
    expect(packToUnitCost(entry({ packCost: "" }))).toBeNull();
    expect(packToUnitCost(entry({ unitsPerPack: "0" }))).toBeNull();
  });
});

describe("packIsComplete", () => {
  it("needs a quantity and a cost", () => {
    expect(packIsComplete(entry())).toBe(true);
    expect(packIsComplete(entry({ packCost: "" }))).toBe(false);
  });
});

describe("packSummary", () => {
  it("says what the line will record, in the item's own unit", () => {
    expect(packSummary(entry(), "kg")).toBe("100 kg at 40 each");
  });

  it("falls back to a word rather than printing nothing", () => {
    expect(packSummary(entry(), "")).toBe("100 units at 40 each");
  });

  it("says nothing while the entry is half-typed", () => {
    expect(packSummary(entry({ packCost: "" }), "kg")).toBe("");
  });
});

describe("lineTotal", () => {
  it("is what the delivery note is checked against", () => {
    expect(lineTotal("100", "40")).toBe(4000);
  });

  it("copes with a fractional quantity", () => {
    expect(lineTotal("2.5", "40")).toBe(100);
  });

  it("is zero for an empty line rather than NaN", () => {
    expect(lineTotal("", "")).toBe(0);
  });
});
