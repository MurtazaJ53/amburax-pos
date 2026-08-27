/** Catching an import that would go into the wrong place.
 *
 *  The failure this exists for is silent by construction: both kinds require
 *  only a name, so a customer list imported as products succeeds. Every
 *  customer becomes a product, nothing errors, and the catalogue fills up
 *  with people. The first test here is that exact file.
 */
import { describe, expect, it } from "vitest";

import {
  contradicts,
  detectKind,
  findDuplicates,
  findExisting,
  identityOf,
  summarise,
} from "./import-detect";

describe("detectKind", () => {
  it("recognises a customer list", () => {
    expect(detectKind(["Name", "Mobile", "Opening Balance"]).kind).toBe("customers");
  });

  it("recognises a product list", () => {
    expect(detectKind(["Item Name", "Price", "Barcode", "Stock"]).kind).toBe(
      "products",
    );
  });

  it("says nothing when a file could be either", () => {
    // A single column of names genuinely is ambiguous, and guessing would be
    // worse than admitting it.
    expect(detectKind(["Name"]).kind).toBeNull();
    expect(detectKind([]).kind).toBeNull();
  });

  it("ignores columns both kinds share", () => {
    // "Name" is in all three schemas, so it points nowhere.
    const detection = detectKind(["Name"]);
    expect(detection.scores.products).toEqual([]);
    expect(detection.scores.customers).toEqual([]);
    expect(detection.scores.sales).toEqual([]);
  });

  it("reads the everyday words for a column, not just our own labels", () => {
    // Nobody's spreadsheet says "costPrice". They say mobile, party, HSN.
    expect(detectKind(["Party Name", "Mobile"]).kind).toBe("customers");
    expect(detectKind(["Particulars", "HSN", "Qty"]).kind).toBe("products");
  });

  it("goes with the weight of evidence rather than the first match", () => {
    expect(detectKind(["Name", "Mobile", "Barcode", "Stock", "MRP"]).kind).toBe(
      "products",
    );
  });
});

describe("contradicts", () => {
  it("catches a customer file being imported as products", () => {
    // The whole point. This is the import that silently ruins a catalogue.
    const detection = detectKind(["Customer Name", "Mobile", "Opening Balance"]);
    expect(contradicts("products", detection)).toBe(true);
  });

  it("catches a product file being imported as customers", () => {
    expect(contradicts("customers", detectKind(["Item", "Barcode", "Stock"]))).toBe(
      true,
    );
  });

  it("stays quiet when the choice matches the file", () => {
    expect(contradicts("customers", detectKind(["Name", "Mobile"]))).toBe(false);
    expect(contradicts("products", detectKind(["Item", "Price"]))).toBe(false);
  });

  it("stays quiet on a file that could be either", () => {
    // Crying wolf on an ambiguous file teaches people to click past the
    // warning, which is exactly when it needs to be believed.
    expect(contradicts("products", detectKind(["Name"]))).toBe(false);
  });
});

describe("identityOf", () => {
  it("identifies a product by its code before its name", () => {
    const row = { barcode: "890123", sku: "RICE-01", name: "Rice" };
    expect(identityOf(row, "products")).toBe("890123");
    expect(identityOf({ sku: "RICE-01", name: "Rice" }, "products")).toBe("rice-01");
  });

  it("falls back to the name, because most files have no codes", () => {
    expect(identityOf({ name: "Basmati Rice" }, "products")).toBe("basmati rice");
  });

  it("identifies a customer by phone before name", () => {
    expect(identityOf({ phone: "9876543210", name: "Asha" }, "customers")).toBe(
      "9876543210",
    );
  });

  it("ignores case, so two spellings still match", () => {
    expect(identityOf({ name: "RICE" }, "products")).toBe(
      identityOf({ name: "rice" }, "products"),
    );
  });

  it("treats a blank row as having no identity", () => {
    expect(identityOf({ name: "   " }, "products")).toBe("");
  });
});

describe("findDuplicates", () => {
  const rows = [
    { name: "Rice", sku: "R1" },
    { name: "Dal", sku: "D1" },
    { name: "Rice again", sku: "R1" },
    { name: "Oil", sku: "" },
  ];

  it("finds rows that name the same thing", () => {
    const groups = findDuplicates(rows, "products");
    expect(groups).toHaveLength(1);
    expect(groups[0].value).toBe("r1");
  });

  it("gives the row numbers a person can find in their spreadsheet", () => {
    // 1-based, because row 0 does not exist to anybody reading a file.
    expect(findDuplicates(rows, "products")[0].rows).toEqual([1, 3]);
  });

  it("does not treat rows with nothing to match on as duplicates", () => {
    expect(findDuplicates([{ name: "" }, { name: "" }], "products")).toEqual([]);
  });

  it("puts the worst offender first", () => {
    const many = [
      { name: "A" },
      { name: "A" },
      { name: "A" },
      { name: "B" },
      { name: "B" },
    ];
    expect(findDuplicates(many, "products")[0].rows).toHaveLength(3);
  });

  it("finds nothing in a clean file", () => {
    expect(findDuplicates([{ name: "A" }, { name: "B" }], "products")).toEqual([]);
  });
});

describe("findExisting", () => {
  it("flags a row that is already in the shop", () => {
    const groups = findExisting([{ sku: "RICE-01" }], "products", ["rice-01"]);
    expect(groups).toHaveLength(1);
    expect(groups[0].rows).toEqual([1]);
  });

  it("ignores case when comparing", () => {
    expect(findExisting([{ name: "Rice" }], "products", ["RICE"])).toHaveLength(1);
  });

  it("finds nothing when the shop is empty", () => {
    expect(findExisting([{ name: "Rice" }], "products", [])).toEqual([]);
  });

  it("does not flag rows that are genuinely new", () => {
    expect(findExisting([{ name: "Sugar" }], "products", ["rice"])).toEqual([]);
  });
});

describe("summarise", () => {
  it("counts in things a shopkeeper recognises", () => {
    expect(summarise("products", 312, [], [])).toBe("312 products");
    expect(summarise("customers", 1, [], [])).toBe("1 customer");
  });

  it("separates repeats in the file from what is already in the shop", () => {
    // Different problems, different words: one is a bad file, the other risks
    // a second copy of something real.
    const line = summarise(
      "products",
      10,
      [{ value: "a", rows: [1, 2] }],
      [{ value: "b", rows: [3] }],
    );
    expect(line).toContain("1 repeated in the file");
    expect(line).toContain("1 already in your shop");
  });
});


describe("telling past sales apart", () => {
  it("recognises an old sales register", () => {
    expect(detectKind(["Bill No", "Bill Date", "Grand Total"]).kind).toBe("sales");
  });

  it("does not cry wolf when a sales file is imported as sales", () => {
    // The regression this guards: adding a third kind to a two-way check made
    // every sales file look like a customer list, because it has a party name
    // and a mobile number in it.
    const detection = detectKind(["Bill No", "Bill Date", "Total", "Party Name", "Mobile"]);
    expect(contradicts("sales", detection)).toBe(false);
  });

  it("catches a sales file imported as products", () => {
    const detection = detectKind(["Bill No", "Bill Date", "Grand Total"]);
    expect(contradicts("products", detection)).toBe(true);
  });

  it("identifies a sale by its bill number and nothing else", () => {
    // Two sales on the same day for the same amount are ordinary trading.
    // Falling back to a name would call every cash sale a duplicate.
    expect(identityOf({ id: "INV-9", customer_name: "Asha" }, "sales")).toBe("inv-9");
    expect(identityOf({ customer_name: "Asha" }, "sales")).toBe("");
  });

  it("counts past sales in words a shopkeeper uses", () => {
    expect(summarise("sales", 2, [], [])).toBe("2 past sales");
  });
});
