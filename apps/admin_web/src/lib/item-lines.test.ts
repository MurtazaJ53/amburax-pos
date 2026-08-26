/** The rules that keep a delivery attached to a product.
 *
 *  Every failure pinned here has the same shape: the bill totals correctly
 *  and the stock does not move, which nobody notices until a count.
 */
import { describe, expect, it } from "vitest";

import {
  BLANK_LINE,
  type DraftLine,
  type StockItem,
  applyPick,
  isBlank,
  isComplete,
  lineTotal,
  linesSubtotal,
  matchesFor,
  readStockItems,
  toPayload,
  toStockItem,
  validateLines,
} from "./item-lines";

function item(over: Partial<StockItem> = {}): StockItem {
  return {
    id: "i1",
    name: "Basmati Rice",
    sku: "RICE-01",
    size: "5kg",
    unit: "kg",
    costPrice: 40,
    stock: 12,
    ...over,
  };
}

function line(over: Partial<DraftLine> = {}): DraftLine {
  return { ...BLANK_LINE, ...over };
}

describe("matchesFor", () => {
  const items = [
    item(),
    item({ id: "i2", name: "Toor Dal", sku: "DAL-01" }),
    item({ id: "i3", name: "Sunflower Oil", sku: "OIL-01" }),
  ];

  it("finds by name and by SKU", () => {
    expect(matchesFor(items, "dal").map((i) => i.id)).toEqual(["i2"]);
    expect(matchesFor(items, "OIL-01").map((i) => i.id)).toEqual(["i3"]);
  });

  it("browses on an empty query rather than showing nothing", () => {
    // A scan matching nothing must select nothing, but a buyer clicking into
    // an empty box is browsing - an empty list would look like an empty shop.
    expect(matchesFor(items, "").map((i) => i.id)).toEqual(["i1", "i2", "i3"]);
  });

  it("caps the list, because this is a picker not the catalogue", () => {
    const many = Array.from({ length: 30 }, (_, n) => item({ id: `x${n}` }));
    expect(matchesFor(many, "")).toHaveLength(8);
    expect(matchesFor(many, "basmati")).toHaveLength(8);
  });

  it("does not fall over on an item with no barcode", () => {
    expect(matchesFor([item()], "rice")).toHaveLength(1);
  });
});

describe("applyPick", () => {
  it("fills the cost it was last bought at", () => {
    expect(applyPick(line(), item()).unitCost).toBe("40");
  });

  it("leaves a cost that was typed by hand, because that is a negotiation", () => {
    expect(applyPick(line({ unitCost: "37.50" }), item()).unitCost).toBe("37.50");
  });

  it("fills nothing when the item was never bought before", () => {
    expect(applyPick(line(), item({ costPrice: null })).unitCost).toBe("");
  });

  it("clears the search text so the chosen name shows", () => {
    expect(applyPick(line({ query: "ric" }), item()).query).toBe("");
  });
});

describe("isComplete and isBlank", () => {
  it("needs both an item and a quantity to move stock", () => {
    expect(isComplete(line({ itemId: "i1", quantity: "5" }))).toBe(true);
    expect(isComplete(line({ quantity: "5" }))).toBe(false);
    expect(isComplete(line({ itemId: "i1" }))).toBe(false);
  });

  it("accepts a cost of nothing, because free stock and samples are real", () => {
    expect(isComplete(line({ itemId: "i1", quantity: "5", unitCost: "0" }))).toBe(true);
  });

  it("separates an untouched row from a half-filled one", () => {
    expect(isBlank(line())).toBe(true);
    expect(isBlank(line({ query: "ric" }))).toBe(false);
  });
});

describe("validateLines", () => {
  it("refuses a form with nothing on it", () => {
    expect(validateLines([line()])).toBe("Add at least one item.");
  });

  it("refuses a typed name that was never picked from stock", () => {
    // The whole point: an unpicked line books money owed and moves no stock.
    expect(validateLines([line({ query: "Basmati", quantity: "5" })])).toMatch(
      /Choose each item from stock/,
    );
  });

  it("refuses a picked item with no quantity", () => {
    expect(validateLines([line({ itemId: "i1" })])).toMatch(/how many/);
  });

  it("refuses the same item twice, which would be counted twice", () => {
    expect(
      validateLines([
        line({ itemId: "i1", quantity: "5" }),
        line({ itemId: "i1", quantity: "3" }),
      ]),
    ).toMatch(/two lines/);
  });

  it("ignores the spare row at the bottom of the form", () => {
    expect(validateLines([line({ itemId: "i1", quantity: "5" }), line()])).toBeNull();
  });

  it("does not silently drop a half-filled line", () => {
    // Dropping it books a bill whose total is right and whose stock is short.
    expect(
      validateLines([line({ itemId: "i1", quantity: "5" }), line({ query: "Dal" })]),
    ).not.toBeNull();
  });
});

describe("totals", () => {
  it("multiplies quantity by cost", () => {
    expect(lineTotal(line({ quantity: "50", unitCost: "40" }))).toBe(2000);
  });

  it("sums only the lines that will actually be sent", () => {
    expect(
      linesSubtotal([
        line({ itemId: "i1", quantity: "50", unitCost: "40" }),
        line({ quantity: "9", unitCost: "9" }),
      ]),
    ).toBe(2000);
  });

  it("treats an unreadable number as nothing rather than NaN", () => {
    expect(lineTotal(line({ quantity: "abc", unitCost: "40" }))).toBe(0);
  });
});

describe("toPayload", () => {
  const items = [item(), item({ id: "i2", name: "Toor Dal", sku: "DAL-01" })];

  it("sends the item id, which is what moves stock", () => {
    const [row] = toPayload([line({ itemId: "i1", quantity: "50", unitCost: "40" })], items);
    expect(row.inventory_item_id).toBe("i1");
  });

  it("snapshots the name and SKU so a later rename does not rewrite the bill", () => {
    const [row] = toPayload([line({ itemId: "i2", quantity: "1", unitCost: "9" })], items);
    expect(row.name).toBe("Toor Dal");
    expect(row.sku).toBe("DAL-01");
  });

  it("sends the cost to two places, as money", () => {
    const [row] = toPayload([line({ itemId: "i1", quantity: "3", unitCost: "40" })], items);
    expect(row.unit_cost).toBe("40.00");
  });

  it("keeps a fractional quantity, for goods sold by weight", () => {
    const [row] = toPayload([line({ itemId: "i1", quantity: "2.5", unitCost: "40" })], items);
    expect(row.quantity).toBe("2.5");
  });

  it("leaves out rows that carry nothing", () => {
    expect(toPayload([line({ itemId: "i1", quantity: "1" }), line()], items)).toHaveLength(1);
  });
});

describe("reading the inventory payload", () => {
  it("keeps a missing cost as null, never as zero", () => {
    // A zero here becomes the suggested cost, and the first receipt that
    // accepts it writes zero as the item's cost price - which then reads as
    // pure profit on every report that item appears in.
    expect(toStockItem({ id: "i1", name: "Rice" }).costPrice).toBeNull();
    expect(toStockItem({ id: "i1", cost_price: null }).costPrice).toBeNull();
  });

  it("keeps a real zero cost, because free stock exists", () => {
    expect(toStockItem({ id: "i1", cost_price: 0 }).costPrice).toBe(0);
  });

  it("treats an item that was never counted as none in stock", () => {
    expect(toStockItem({ id: "i1" }).stock).toBe(0);
  });

  it("reads both shapes the inventory endpoint comes back in", () => {
    const raw = [{ id: "i1", name: "Rice" }];
    expect(readStockItems(raw)).toHaveLength(1);
    expect(readStockItems({ items: raw, summary: {} })).toHaveLength(1);
  });

  it("returns nothing rather than throwing on an unexpected payload", () => {
    // An empty picker with no message is how the purchase-order screen sat
    // unusable, so this must not be an exception swallowed by a catch.
    expect(readStockItems(null)).toEqual([]);
    expect(readStockItems({ error: "nope" })).toEqual([]);
  });
});
