import { describe, expect, it } from "vitest";

import {
  BLANK_TIER,
  PRODUCT_PROFILES,
  cleanTiers,
  labelFor,
  missingRequired,
  priceForQuantity,
  profileById,
  profileForBusinessType,
  shows,
  tierProblem,
  type PriceTier,
} from "./product-profiles";

const general = profileById("general");
const retail = profileById("retail_garment");
const wholesale = profileById("wholesale_garment");

describe("which fields a shop is asked for", () => {
  it("asks a garment shop for colours and a grocer for none", () => {
    expect(shows(retail, "colour")).toBe(true);
    expect(shows(general, "colour")).toBe(false);
  });

  it("asks only the wholesaler for a minimum order and bulk slabs", () => {
    expect(shows(wholesale, "moq")).toBe(true);
    expect(shows(wholesale, "priceTiers")).toBe(true);
    expect(shows(retail, "moq")).toBe(false);
    expect(shows(general, "priceTiers")).toBe(false);
  });

  it("renames a field rather than adding a second one", () => {
    // A garment shop calls it a style, a wholesaler calls it a design. Same
    // column, same data - only the word on screen changes.
    expect(labelFor(retail, "name")).toContain("Style name");
    expect(labelFor(wholesale, "name")).toContain("Design");
    expect(labelFor(general, "name")).toContain("Product name");
  });

  it("marks required fields with an asterisk once, in one place", () => {
    expect(labelFor(general, "name").endsWith(" *")).toBe(true);
    expect(labelFor(general, "barcode").endsWith(" *")).toBe(false);
  });

  it("makes HSN mandatory for a wholesaler and optional for a grocer", () => {
    // A dealer needs a proper GST invoice to claim input credit.
    expect(labelFor(wholesale, "hsn").endsWith(" *")).toBe(true);
    expect(labelFor(general, "hsn").endsWith(" *")).toBe(false);
  });

  it("keeps every profile answering for every field", () => {
    // The reason this is data and not branches in the dialog: a field added
    // to one profile cannot go missing from another.
    const keys = Object.keys(general.fields);
    for (const profile of PRODUCT_PROFILES) {
      expect(Object.keys(profile.fields).sort()).toEqual([...keys].sort());
    }
  });
});

describe("what has to be filled in", () => {
  it("does not demand a field the profile never showed", () => {
    // A wholesaler blocked by a retail requirement they were never shown is a
    // save that cannot be completed and cannot be explained.
    expect(missingRequired(general, { name: "Rice", costPrice: "10", sellPrice: "12" })).toEqual([]);
  });

  it("names each missing field rather than saying 'some fields'", () => {
    const missing = missingRequired(retail, { name: "Shirt", costPrice: "1", sellPrice: "2" });

    expect(missing).toContain("size");
    expect(missing).toContain("colour");
  });

  it("counts whitespace as empty", () => {
    expect(missingRequired(general, { name: "   ", costPrice: "1", sellPrice: "2" })).toContain("name");
  });
});

describe("picking a profile for a shop", () => {
  it("opens a wholesaler on the wholesale form", () => {
    expect(profileForBusinessType("wholesale").id).toBe("wholesale_garment");
  });

  it("falls back to General for a shop type with no special form", () => {
    // grocery, pharmacy and restaurant have no profile yet. They must get the
    // ordinary form, not the nearest-looking one.
    for (const type of ["grocery", "pharmacy", "restaurant", "", null, undefined]) {
      expect(profileForBusinessType(type).id).toBe("general");
    }
  });

  it("falls back to General for an unknown profile id", () => {
    expect(profileById("nonsense").id).toBe("general");
  });
});

describe("bulk price slabs", () => {
  const tiers: PriceTier[] = [
    { min_quantity: "5", price_per_piece: "220" },
    { min_quantity: "1", price_per_piece: "250" },
  ];

  it("orders slabs by quantity whatever order they were typed in", () => {
    expect(cleanTiers(tiers).map((tier) => tier.min_quantity)).toEqual(["1", "5"]);
  });

  it("drops a half-typed row rather than saving it as zero", () => {
    // "From 0 units, ₹0 each" would price an entire lot at nothing.
    expect(cleanTiers([BLANK_TIER, { min_quantity: "5", price_per_piece: "" }])).toEqual([]);
  });

  it("charges the last slab the order has reached", () => {
    expect(priceForQuantity(tiers, 1, 300)).toBe(250);
    expect(priceForQuantity(tiers, 4, 300)).toBe(250);
    expect(priceForQuantity(tiers, 5, 300)).toBe(220);
    expect(priceForQuantity(tiers, 99, 300)).toBe(220);
  });

  it("treats a slab boundary as inclusive", () => {
    // "From 5 dozen" means five qualifies. Off by one here is a discount the
    // dealer was promised and did not get.
    expect(priceForQuantity(tiers, 5, 300)).toBe(220);
  });

  it("falls back to the base price, never to zero", () => {
    // The direction that matters. Falling back to base costs a dealer their
    // discount; falling back to zero gives away the lot.
    expect(priceForQuantity([], 100, 300)).toBe(300);
    expect(priceForQuantity([{ min_quantity: "10", price_per_piece: "9" }], 2, 300)).toBe(300);
  });

  it("agrees with the server's answer at every boundary", () => {
    // The same slabs as the backend's BulkPriceTests. A till and an invoice
    // disagreeing about one line is an argument with a dealer the shop cannot
    // win, so both sides are pinned to the same numbers.
    const shared: PriceTier[] = [
      { min_quantity: "1", price_per_piece: "250" },
      { min_quantity: "5", price_per_piece: "220" },
      { min_quantity: "10", price_per_piece: "205" },
    ];

    expect([1, 4, 5, 9, 10, 40].map((quantity) => priceForQuantity(shared, quantity, 300))).toEqual([
      250, 250, 220, 220, 205, 205,
    ]);
  });

  it("catches a slab that gets more expensive in bulk", () => {
    const wrong: PriceTier[] = [
      { min_quantity: "1", price_per_piece: "200" },
      { min_quantity: "5", price_per_piece: "260" },
    ];

    expect(tierProblem(wrong)).toContain("should not cost more");
  });

  it("catches two slabs starting at the same quantity", () => {
    const clash: PriceTier[] = [
      { min_quantity: "5", price_per_piece: "220" },
      { min_quantity: "5", price_per_piece: "210" },
    ];

    expect(tierProblem(clash)).toContain("Only one price");
  });

  it("says nothing is wrong with slabs that are fine", () => {
    expect(tierProblem(tiers)).toBeNull();
    expect(tierProblem([])).toBeNull();
  });
});
