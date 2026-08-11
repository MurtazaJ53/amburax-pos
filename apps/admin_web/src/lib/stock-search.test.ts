import { describe, expect, it } from "vitest";

import { resolveScan, searchItems } from "./stock-search";

const items = [
  { id: "1", name: "Cotton Shirt", sku: "SH-01", barcode: "8901234567890" },
  { id: "2", name: "Cotton Trouser", sku: "TR-01", barcode: "8901234567891" },
  // A name that literally contains another item's barcode. Rare, but a shop
  // that puts codes in item names will hit it, and it must not beat the scan.
  { id: "3", name: "Bundle 8901234567890", sku: "BN-01", barcode: "8909999999999" },
];

describe("searchItems", () => {
  it("matches on name, sku or barcode, case-insensitively", () => {
    expect(searchItems(items, "cotton").map((i) => i.id)).toEqual(["1", "2"]);
    expect(searchItems(items, "tr-01").map((i) => i.id)).toEqual(["2"]);
    expect(searchItems(items, "8901234567891").map((i) => i.id)).toEqual(["2"]);
  });

  it("matches nothing on an empty or blank query", () => {
    // Otherwise the suggestion list would show a slice of the whole catalogue
    // the moment the field is cleared.
    expect(searchItems(items, "")).toEqual([]);
    expect(searchItems(items, "   ")).toEqual([]);
  });

  it("caps how many suggestions come back", () => {
    const many = Array.from({ length: 30 }, (_, n) => ({
      id: String(n),
      name: `Cotton ${n}`,
      sku: "",
      barcode: "",
    }));
    expect(searchItems(many, "cotton")).toHaveLength(8);
  });
});

describe("resolveScan", () => {
  it("takes an exact barcode even when another item's name contains it", () => {
    // Two items match the substring search; without the exact-barcode rule
    // this would be ambiguous and the scan would do nothing.
    expect(searchItems(items, "8901234567890")).toHaveLength(2);
    expect(resolveScan(items, "8901234567890")?.id).toBe("1");
  });

  it("takes an exact SKU", () => {
    expect(resolveScan(items, "TR-01")?.id).toBe("2");
  });

  it("takes a single fuzzy match", () => {
    expect(resolveScan(items, "trouser")?.id).toBe("2");
  });

  it("refuses to guess between several matches", () => {
    // "cotton" hits both garments. Picking the first would record a count
    // against an item nobody chose.
    expect(resolveScan(items, "cotton")).toBeNull();
  });

  it("returns nothing for no match or a blank query", () => {
    expect(resolveScan(items, "saree")).toBeNull();
    expect(resolveScan(items, "  ")).toBeNull();
  });
});
