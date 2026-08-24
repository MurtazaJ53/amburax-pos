import { describe, expect, it } from "vitest";

import { formatQuantity, linesSummary, saleLines } from "./ledger-items";

const line = (over: Partial<Parameters<typeof linesSummary>[0][number]> = {}) => ({
  name: "Rice 5kg",
  quantity: "1",
  unit_price: "80.00",
  line_total: "80.00",
  ...over,
});

describe("saleLines", () => {
  it("returns nothing for an entry with no sale behind it", () => {
    expect(saleLines(null)).toEqual([]);
    expect(saleLines(undefined)).toEqual([]);
  });

  it("returns nothing when the sale carries no items array", () => {
    expect(saleLines({ id: "s1" })).toEqual([]);
  });

  it("drops nameless rows rather than rendering a blank line", () => {
    const lines = saleLines({ id: "s1", items: [line(), line({ name: "" })] });
    expect(lines).toHaveLength(1);
  });

  it("keeps returns, which the caller marks rather than hides", () => {
    const lines = saleLines({ id: "s1", items: [line({ is_return: true })] });
    expect(lines[0].is_return).toBe(true);
  });
});

describe("formatQuantity", () => {
  it("shows whole numbers without decimal noise", () => {
    expect(formatQuantity("2.000")).toBe("2");
  });

  it("keeps a real fractional quantity, since shops sell 1.5 kg", () => {
    expect(formatQuantity("1.500")).toBe("1.5");
  });

  it("never renders NaN", () => {
    expect(formatQuantity("")).toBe("0");
    expect(formatQuantity(null)).toBe("0");
  });
});

describe("linesSummary", () => {
  it("is empty when there is nothing to summarise", () => {
    expect(linesSummary([])).toBe("");
  });

  it("counts lines and units separately", () => {
    expect(linesSummary([line({ quantity: "2" }), line({ quantity: "3" })])).toBe(
      "2 items · 5 units",
    );
  });

  it("uses singulars for a single unit of a single item", () => {
    expect(linesSummary([line({ quantity: "1" })])).toBe("1 item · 1 unit");
  });
});
