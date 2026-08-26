import { describe, expect, it } from "vitest";

import {
  averageMargin,
  mapInventoryRow,
  marginPercent,
  stockFillPercent,
} from "./inventory-rows";
import type { ApiInventoryRow, ProductRow } from "./inventory-rows";

function row(overrides: Partial<ApiInventoryRow> = {}): ApiInventoryRow {
  return { id: "i1", name: "Item", sell_price: "100.00", stock_on_hand: 50, ...overrides };
}

describe("a cost the server would not give us", () => {
  // cost_price comes back null both when nobody has entered one AND when the
  // viewer's role may not see costs. Either way it is not zero.
  it("keeps a null cost as null, not ₹0.00", () => {
    expect(mapInventoryRow(row({ cost_price: null })).cost_price).toBeNull();
  });

  it("keeps an absent cost as null too", () => {
    expect(mapInventoryRow(row({})).cost_price).toBeNull();
  });

  it("still reads a real zero cost as zero", () => {
    expect(mapInventoryRow(row({ cost_price: "0.00" })).cost_price).toBe(0);
  });

  it("reports no margin rather than a 100% one", () => {
    expect(marginPercent(mapInventoryRow(row({ cost_price: null })))).toBeNull();
  });
});

describe("the shop's own reorder level", () => {
  it("uses the level the shopkeeper configured", () => {
    const mapped = mapInventoryRow(row({ reorder_level: 40, stock_on_hand: 30 }));
    expect(mapped.reorder_level).toBe(40);
    expect(mapped.is_low_stock).toBe(true);
  });

  it("does not call an item low just because it is under ten", () => {
    // The old mapping hardcoded 10, so a shop that reorders at 100 was told
    // 30 in stock was healthy.
    const mapped = mapInventoryRow(row({ reorder_level: 100, stock_on_hand: 30 }));
    expect(mapped.is_low_stock).toBe(true);
  });

  it("respects a configured zero as 'never warn me'", () => {
    const mapped = mapInventoryRow(row({ reorder_level: 0, stock_on_hand: 3 }));
    expect(mapped.is_low_stock).toBe(false);
  });

  it("falls back to ten only when no level was set at all", () => {
    expect(mapInventoryRow(row({ stock_on_hand: 8 })).is_low_stock).toBe(true);
    expect(mapInventoryRow(row({ stock_on_hand: 11 })).is_low_stock).toBe(false);
  });

  it("separates out of stock from merely low", () => {
    const empty = mapInventoryRow(row({ stock_on_hand: 0 }));
    expect(empty.is_out_of_stock).toBe(true);
    expect(empty.is_low_stock).toBe(false);
  });
});

describe("the GST rate", () => {
  it("keeps an exempt item at 0%, not the 5% default", () => {
    expect(mapInventoryRow(row({ gst_rate: "0.00" })).tax_rate).toBe(0);
  });

  it("says nothing rather than guessing when the rate is missing", () => {
    expect(mapInventoryRow(row({ gst_rate: null })).tax_rate).toBeNull();
  });
});

describe("margin", () => {
  const item = (cost: string, sell: string): ProductRow =>
    mapInventoryRow(row({ cost_price: cost, sell_price: sell }));

  it("is measured against the selling price, the way a shop quotes it", () => {
    // 155 sell, 128 cost → 27 on 155 = 17.4%
    expect(marginPercent(item("128.00", "155.00"))).toBeCloseTo(17.42, 2);
  });

  it("goes negative when an item sells below cost", () => {
    expect(marginPercent(item("120.00", "100.00"))).toBeCloseTo(-20, 2);
  });

  it("is unknowable on a free item rather than dividing by zero", () => {
    expect(marginPercent(item("10.00", "0.00"))).toBeNull();
  });

  it("averages only over items that have a cost", () => {
    const rows = [item("50.00", "100.00"), mapInventoryRow(row({ cost_price: null }))];
    expect(averageMargin(rows)).toBeCloseTo(50, 2);
  });

  it("has no average when nothing has a cost", () => {
    expect(averageMargin([mapInventoryRow(row({ cost_price: null }))])).toBeNull();
  });
});

describe("the shelf-fill bar", () => {
  it("is empty for an out-of-stock item", () => {
    expect(stockFillPercent(mapInventoryRow(row({ stock_on_hand: 0 })))).toBe(0);
  });

  it("is full at twice the reorder level and never overflows", () => {
    expect(stockFillPercent(mapInventoryRow(row({ reorder_level: 10, stock_on_hand: 20 })))).toBe(100);
    expect(stockFillPercent(mapInventoryRow(row({ reorder_level: 10, stock_on_hand: 900 })))).toBe(100);
  });

  it("sits half way at the reorder level itself", () => {
    expect(stockFillPercent(mapInventoryRow(row({ reorder_level: 10, stock_on_hand: 10 })))).toBe(50);
  });
});

describe("the product photo", () => {
  // The bytes no longer travel with the list - opening Stock, or the till,
  // used to download every photo inside one uncacheable response. All a row
  // carries now is whether there is one to fetch.
  it("says when there is a picture to fetch", () => {
    expect(mapInventoryRow(row({ has_image: true })).has_image).toBe(true);
  });

  it("says there is none when the shop never added one", () => {
    // Null, false and absent all mean "no photo"; the tile falls back to the
    // product's initial rather than requesting a picture that is not there.
    expect(mapInventoryRow(row({ has_image: null })).has_image).toBe(false);
    expect(mapInventoryRow(row({ has_image: false })).has_image).toBe(false);
    expect(mapInventoryRow(row({})).has_image).toBe(false);
  });
});

describe("is_tracked", () => {
  it("takes the server's word when the server says so", () => {
    expect(mapInventoryRow({ id: "1", name: "A", has_stock_history: true }).is_tracked).toBe(
      true,
    );
    expect(
      mapInventoryRow({ id: "1", name: "A", has_stock_history: false }).is_tracked,
    ).toBe(false);
  });

  it("does not call a stocked item untracked just because the API stayed silent", () => {
    // The bug this guards: an older server omits the field, every row reads
    // "Stock not tracked", including one holding 462 units.
    const row = mapInventoryRow({ id: "1", name: "A", stock_on_hand: 462 });
    expect(row.is_tracked).toBe(true);
  });

  it("infers history from a negative balance too, which also needs movements", () => {
    expect(mapInventoryRow({ id: "1", name: "A", stock_on_hand: -3 }).is_tracked).toBe(true);
  });

  it("leaves a silent zero as untracked, which is the honest answer", () => {
    expect(mapInventoryRow({ id: "1", name: "A", stock_on_hand: 0 }).is_tracked).toBe(false);
  });

  it("lets an explicit false win over a non-zero count", () => {
    // Only reachable by selling an item nobody ever stocked. The server knows
    // better than the inference here.
    const row = mapInventoryRow({
      id: "1",
      name: "A",
      stock_on_hand: -3,
      has_stock_history: false,
    });
    expect(row.is_tracked).toBe(false);
  });
});
