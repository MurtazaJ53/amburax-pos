import { describe, expect, it } from "vitest";

import {
  applyFilters,
  DEFAULT_FILTERS,
  filterCounts,
  hasActiveFilters,
  matchesSearch,
  matchesStockFilter,
  categoryFacets,
  matchesCategory,
  rowMargin,
  shelfValue,
  stockFacets,
  UNCATEGORISED,
  type FilterableRow,
} from "./inventory-filters";

function row(over: Partial<FilterableRow> = {}): FilterableRow {
  return {
    name: "Rice 5kg",
    sku: "RICE-5",
    barcode: "8901234567890",
    category: "Grocery",
    cost_price: 60,
    selling_price: 100,
    current_stock: 12,
    hsn_code: "1006",
    is_low_stock: false,
    is_out_of_stock: false,
    is_tracked: true,
    updated_at: "2026-08-20T10:00:00Z",
    ...over,
  };
}

describe("matchesStockFilter", () => {
  it("counts a zero-stock item as out, not in", () => {
    const empty = row({ current_stock: 0, is_out_of_stock: true });
    expect(matchesStockFilter(empty, "out")).toBe(true);
    expect(matchesStockFilter(empty, "in")).toBe(false);
  });

  it("treats a real zero cost as known, not as missing", () => {
    // A free sample priced at 0 is a claim someone made. Sweeping it into
    // "no cost price" would send the owner to fix data that is already right.
    expect(matchesStockFilter(row({ cost_price: 0 }), "nocost")).toBe(false);
    expect(matchesStockFilter(row({ cost_price: null }), "nocost")).toBe(true);
  });

  it("finds items the counter cannot scan", () => {
    expect(matchesStockFilter(row({ barcode: "" }), "nobarcode")).toBe(true);
    expect(matchesStockFilter(row({ barcode: "   " }), "nobarcode")).toBe(true);
    expect(matchesStockFilter(row(), "nobarcode")).toBe(false);
  });

  it("finds items that would fail a GST return", () => {
    expect(matchesStockFilter(row({ hsn_code: "" }), "nohsn")).toBe(true);
    expect(matchesStockFilter(row(), "nohsn")).toBe(false);
  });

  it("lets everything through on 'all'", () => {
    expect(matchesStockFilter(row({ cost_price: null, barcode: "" }), "all")).toBe(true);
  });
});

describe("matchesSearch", () => {
  it("matches on name, SKU and barcode", () => {
    expect(matchesSearch(row(), "rice")).toBe(true);
    expect(matchesSearch(row(), "RICE-5")).toBe(true);
    expect(matchesSearch(row(), "8901234567890")).toBe(true);
  });

  it("ignores case and surrounding space, which a scanner can add", () => {
    expect(matchesSearch(row(), "  RiCe  ")).toBe(true);
  });

  it("matches everything when the box is empty", () => {
    expect(matchesSearch(row(), "")).toBe(true);
  });

  it("does not match an unrelated term", () => {
    expect(matchesSearch(row(), "jacket")).toBe(false);
  });
});

describe("rowMargin", () => {
  it("is a fraction of the selling price", () => {
    expect(rowMargin(row())).toBeCloseTo(0.4);
  });

  it("is unknown rather than zero when the cost was never entered", () => {
    expect(rowMargin(row({ cost_price: null }))).toBeNull();
  });

  it("is unknown for a free item rather than dividing by zero", () => {
    expect(rowMargin(row({ selling_price: 0 }))).toBeNull();
  });
});

describe("applyFilters", () => {
  const rows = [
    row({ name: "Zebra Pen", current_stock: 2, selling_price: 10, cost_price: 9 }),
    row({ name: "Atta 10kg", current_stock: 40, selling_price: 400, cost_price: 200 }),
    row({ name: "Mango", current_stock: 0, is_out_of_stock: true, cost_price: null }),
  ];

  it("sorts by name by default, case-insensitively", () => {
    const out = applyFilters(rows, DEFAULT_FILTERS);
    expect(out.map((r) => r.name)).toEqual(["Atta 10kg", "Mango", "Zebra Pen"]);
  });

  it("puts the emptiest shelves first when sorting by stock", () => {
    const out = applyFilters(rows, { ...DEFAULT_FILTERS, sort: "stock-low" });
    expect(out.map((r) => r.current_stock)).toEqual([0, 2, 40]);
  });

  it("ranks by money sitting on the shelf, not by unit price", () => {
    const out = applyFilters(rows, { ...DEFAULT_FILTERS, sort: "value-high" });
    expect(out[0].name).toBe("Atta 10kg");
    expect(shelfValue(out[0])).toBe(16000);
  });

  it("sorts unknown margins last rather than as the worst performers", () => {
    const out = applyFilters(rows, { ...DEFAULT_FILTERS, sort: "margin-low" });
    expect(out[0].name).toBe("Zebra Pen");
    expect(out[out.length - 1].name).toBe("Mango");
  });

  it("combines a slice with a search rather than letting one win", () => {
    const out = applyFilters(rows, {
      ...DEFAULT_FILTERS,
      stock: "out",
      search: "mango",
    });
    expect(out).toHaveLength(1);
  });

  it("returns nothing when the two narrowings do not overlap", () => {
    const out = applyFilters(rows, { ...DEFAULT_FILTERS, stock: "out", search: "atta" });
    expect(out).toEqual([]);
  });

  it("never reorders the caller's own array", () => {
    const original = [...rows];
    applyFilters(rows, { ...DEFAULT_FILTERS, sort: "value-high" });
    expect(rows).toEqual(original);
  });
});

describe("filterCounts", () => {
  it("counts each slice independently, so the chips can be trusted", () => {
    const counts = filterCounts([
      row({ is_out_of_stock: true, current_stock: 0 }),
      row({ is_low_stock: true, current_stock: 1 }),
      row({ cost_price: null }),
      row({ barcode: "" }),
      row({ hsn_code: "" }),
    ]);
    expect(counts.all).toBe(5);
    expect(counts.out).toBe(1);
    expect(counts.in).toBe(4);
    expect(counts.low).toBe(1);
    expect(counts.nocost).toBe(1);
    expect(counts.nobarcode).toBe(1);
    expect(counts.nohsn).toBe(1);
  });
});

describe("hasActiveFilters", () => {
  it("is false for an untouched screen", () => {
    expect(hasActiveFilters(DEFAULT_FILTERS)).toBe(false);
  });

  it("is true once anything narrows the list", () => {
    expect(hasActiveFilters({ ...DEFAULT_FILTERS, stock: "low" })).toBe(true);
    expect(hasActiveFilters({ ...DEFAULT_FILTERS, category: "Grocery" })).toBe(true);
    expect(hasActiveFilters({ ...DEFAULT_FILTERS, search: "rice" })).toBe(true);
  });

  it("ignores sort, which reorders but hides nothing", () => {
    expect(hasActiveFilters({ ...DEFAULT_FILTERS, sort: "recent" })).toBe(false);
  });
});

describe("matchesCategory", () => {
  it("lets everything through on 'all'", () => {
    expect(matchesCategory(row({ category: "Vests" }), "all")).toBe(true);
  });

  it("matches an exact category", () => {
    expect(matchesCategory(row({ category: "Vests" }), "Vests")).toBe(true);
    expect(matchesCategory(row({ category: "Kids" }), "Vests")).toBe(false);
  });

  it("gives unfiled items a bucket instead of losing them", () => {
    expect(matchesCategory(row({ category: "" }), UNCATEGORISED)).toBe(true);
    expect(matchesCategory(row({ category: "  " }), UNCATEGORISED)).toBe(true);
    expect(matchesCategory(row({ category: "Vests" }), UNCATEGORISED)).toBe(false);
  });
});

describe("categoryFacets", () => {
  const shelf = [
    row({ category: "Vests" }),
    row({ category: "Vests" }),
    row({ category: "Vests", is_out_of_stock: true }),
    row({ category: "Kids" }),
    row({ category: "" }),
  ];

  it("puts the busiest category first, not the alphabetically first", () => {
    const facets = categoryFacets(shelf);
    expect(facets[0]).toEqual({ key: "Vests", label: "Vests", count: 3 });
  });

  it("breaks a tie alphabetically so the order is stable", () => {
    const facets = categoryFacets([row({ category: "Zebra" }), row({ category: "Apple" })]);
    expect(facets.map((f) => f.key)).toEqual(["Apple", "Zebra"]);
  });

  it("gives unfiled items a named bucket rather than dropping them", () => {
    expect(categoryFacets(shelf).some((f) => f.key === UNCATEGORISED)).toBe(true);
  });

  it("narrows by the stock slice, so the counts match what a click returns", () => {
    const facets = categoryFacets(shelf, "out");
    expect(facets).toEqual([{ key: "Vests", label: "Vests", count: 1 }]);
  });

  it("narrows by the search too", () => {
    const facets = categoryFacets(
      [row({ category: "Vests", name: "Dollar Vest" }), row({ category: "Kids", name: "Cap" })],
      "all",
      "vest",
    );
    expect(facets).toEqual([{ key: "Vests", label: "Vests", count: 1 }]);
  });
});

describe("stockFacets", () => {
  const shelf = [
    row({ category: "Vests", is_out_of_stock: true }),
    row({ category: "Vests" }),
    row({ category: "Kids", is_out_of_stock: true }),
    row({ category: "Kids", is_out_of_stock: true }),
  ];

  it("counts within the chosen category, not across the whole shop", () => {
    // Globally 3 are out. Promising 3 while Vests is selected and then showing
    // one is the chip lying about what a click does.
    expect(stockFacets(shelf, "Vests").out).toBe(1);
    expect(stockFacets(shelf, "Vests").all).toBe(2);
  });

  it("counts everything when no category is chosen", () => {
    expect(stockFacets(shelf, "all").out).toBe(3);
  });
});

describe("the oversold slice", () => {
  it("finds stock that went below zero at the counter", () => {
    // Selling past zero is allowed on purpose - the customer is standing
    // there with cash. What must never happen is it going unnoticed.
    expect(matchesStockFilter(row({ current_stock: -3 }), "oversold")).toBe(true);
  });

  it("ignores an item nobody ever counted", () => {
    // -3 on an untracked item is not a shortfall. There was no count to fall
    // short of, and listing it would bury the real ones.
    expect(
      matchesStockFilter(row({ current_stock: -3, is_tracked: false }), "oversold"),
    ).toBe(false);
  });

  it("does not confuse an empty shelf with an oversold one", () => {
    // Zero means "we sold the last one". Negative means "we sold stock the
    // system never knew we had" - a missing purchase entry, not an empty shelf.
    expect(matchesStockFilter(row({ current_stock: 0 }), "oversold")).toBe(false);
  });

  it("does not sweep in a healthy shelf", () => {
    expect(matchesStockFilter(row({ current_stock: 12 }), "oversold")).toBe(false);
  });

  it("is counted for the chip", () => {
    const counts = filterCounts([
      row({ current_stock: -2, is_out_of_stock: true }),
      row({ current_stock: 0, is_out_of_stock: true }),
      row({ current_stock: 5 }),
    ]);
    expect(counts.oversold).toBe(1);
    expect(counts.out).toBe(2);
  });
});

describe("the untracked slice", () => {
  it("finds items that were never given stock", () => {
    expect(matchesStockFilter(row({ is_tracked: false }), "untracked")).toBe(true);
  });

  it("leaves a tracked item alone even when its shelf is empty", () => {
    expect(
      matchesStockFilter(row({ is_tracked: true, current_stock: 0 }), "untracked"),
    ).toBe(false);
  });

  it("separates the two zero-stock populations in the counts", () => {
    const counts = filterCounts([
      row({ current_stock: 0, is_out_of_stock: true, is_tracked: true }),
      row({ current_stock: 0, is_out_of_stock: true, is_tracked: false }),
      row({ current_stock: -4, is_out_of_stock: true, is_tracked: true }),
      row({ current_stock: -4, is_out_of_stock: true, is_tracked: false }),
    ]);
    expect(counts.out).toBe(4);
    expect(counts.untracked).toBe(2);
    // Only the tracked negative is a real shortfall.
    expect(counts.oversold).toBe(1);
  });
});
