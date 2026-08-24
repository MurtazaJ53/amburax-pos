import { describe, expect, it } from "vitest";

import { formatQuantity } from "./utils";

describe("formatQuantity", () => {
  it("drops the trailing zeros the API sends on whole units", () => {
    // "1.000 left" on the dashboard reads as a machine talking to itself.
    expect(formatQuantity("1.000")).toBe("1");
    expect(formatQuantity("25.000")).toBe("25");
  });

  it("keeps a genuine fraction, because shops sell 1.5 kg", () => {
    expect(formatQuantity("1.500")).toBe("1.5");
    expect(formatQuantity("0.250")).toBe("0.25");
  });

  it("groups large counts the Indian way", () => {
    expect(formatQuantity("100000")).toBe("1,00,000");
  });

  it("never renders NaN at a shopkeeper", () => {
    expect(formatQuantity("")).toBe("0");
    expect(formatQuantity(null)).toBe("0");
    expect(formatQuantity(undefined)).toBe("0");
    expect(formatQuantity("abc")).toBe("0");
  });

  it("shows a negative count rather than hiding an oversold item", () => {
    expect(formatQuantity("-3.000")).toBe("-3");
  });
});
