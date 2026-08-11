import { describe, expect, it } from "vitest";

import { spreadsheetRow, toRowError } from "@/lib/import-rows";

const CHUNK = 500; // matches the proxy

describe("locating a rejected import row", () => {
  it("data row 0 is spreadsheet row 2", () => {
    // One for the header, one because spreadsheets count from 1.
    expect(spreadsheetRow(0, 0)).toBe(2);
  });

  it("offsets by the chunk, which is the bug this exists to prevent", () => {
    // The backend restarts its index at 0 for every chunk. Without the offset
    // these two distinct failures both report row 7, and neither can be found.
    const first = spreadsheetRow(0, 5);
    const second = spreadsheetRow(CHUNK, 5);

    expect(first).toBe(7);
    expect(second).toBe(507);
    expect(first).not.toBe(second);
  });

  it("stays correct deep into a large import", () => {
    // Row 1,999 of a 2,000-row sheet: chunk 3, index 499.
    expect(spreadsheetRow(CHUNK * 3, 499)).toBe(2001);
  });

  it("every chunk boundary lands on a distinct row", () => {
    const rows = [0, 1, 2, 3].map((c) => spreadsheetRow(CHUNK * c, 0));
    expect(new Set(rows).size).toBe(rows.length);
    expect(rows).toEqual([2, 502, 1002, 1502]);
  });
});

describe("describing a rejected row", () => {
  it("carries the identity the backend supplied", () => {
    const e = toRowError(CHUNK, {
      index: 3,
      name: "Kurta",
      sku: "K-1",
      message: "sell_price: A valid number is required.",
    });

    expect(e.row).toBe(505);
    expect(e.name).toBe("Kurta");
    expect(e.sku).toBe("K-1");
    expect(e.message).toContain("valid number");
  });

  it("survives a malformed error object rather than rendering undefined", () => {
    // A row that renders "undefined" in the failure table is worse than one
    // that says nothing useful, because it looks like a bug in the import.
    const e = toRowError(0, {});

    expect(e.row).toBe(2);
    expect(e.name).toBe("");
    expect(e.message).toBe("Could not be read.");
  });

  it("survives null", () => {
    expect(() => toRowError(0, null)).not.toThrow();
    expect(toRowError(0, null).message).toBe("Could not be read.");
  });
});
