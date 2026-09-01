import { describe, expect, it } from "vitest";

import {
  belowMinimum,
  lineTotalAt,
  piecePriceAt,
  pricingFor,
  sellsInPacks,
  slabApplied,
  unitPriceAt,
} from "./line-pricing";

/** A garment wholesaler: dozens of shirts, 250 a piece, 220 past five dozen. */
const wholesale = pricingFor(
  {
    pieces_per_unit: "12",
    moq: "2",
    price_tiers: [
      { min_quantity: "1", price_per_piece: "250" },
      { min_quantity: "5", price_per_piece: "220" },
    ],
  },
  250,
  "dozen",
);

/** An ordinary shop product: one piece, one price, no attributes at all. */
const retail = pricingFor(null, 150, "piece");

describe("a line that is sold by the dozen", () => {
  it("charges for the pieces inside the pack, not for the pack", () => {
    // The defect. Three dozen at 250 a piece is 9,000; the till billed 750,
    // and every number on screen multiplied correctly.
    expect(lineTotalAt(wholesale, 3)).toBe(9000);
  });

  it("prices one unit as a whole dozen", () => {
    expect(unitPriceAt(wholesale, 1)).toBe(3000);
  });

  it("keeps quoting the price per piece, which is what a dealer asks for", () => {
    expect(piecePriceAt(wholesale, 1)).toBe(250);
  });

  it("applies the bulk slab as the order grows", () => {
    // Five dozen at 220 a piece: 5 x 12 x 220.
    expect(lineTotalAt(wholesale, 5)).toBe(13200);
  });

  it("does not apply the slab before the order reaches it", () => {
    expect(piecePriceAt(wholesale, 4)).toBe(250);
    expect(piecePriceAt(wholesale, 5)).toBe(220);
  });

  it("knows it is selling packs rather than pieces", () => {
    expect(sellsInPacks(wholesale)).toBe(true);
    expect(sellsInPacks(retail)).toBe(false);
  });
});

describe("an ordinary product is untouched", () => {
  it("prices exactly as it always did", () => {
    // Every product in every existing shop has no attributes. They must price
    // identically to before this existed, or the change is a silent repricing
    // of an entire catalogue.
    expect(lineTotalAt(retail, 4)).toBe(600);
    expect(unitPriceAt(retail, 4)).toBe(150);
  });

  it("has no minimum order", () => {
    expect(belowMinimum(retail, 1)).toBe(0);
  });
});

describe("explaining a price that moved", () => {
  it("says when a slab is bringing the price down, and by how much", () => {
    const slab = slabApplied(wholesale, 5);

    expect(slab.applied).toBe(true);
    expect(slab.piecePrice).toBe(220);
    expect(slab.savedPerPiece).toBe(30);
  });

  it("says nothing when no slab has been reached", () => {
    expect(slabApplied(wholesale, 1).applied).toBe(false);
  });

  it("says nothing for a product with no slabs at all", () => {
    expect(slabApplied(retail, 100).applied).toBe(false);
  });
});

describe("the minimum order", () => {
  it("reports how far short a line is", () => {
    expect(belowMinimum(wholesale, 1)).toBe(1);
  });

  it("is satisfied exactly at the minimum", () => {
    expect(belowMinimum(wholesale, 2)).toBe(0);
  });

  it("reports rather than refuses", () => {
    // Never blocks. A wholesaler letting one dealer take half a carton is
    // making a commercial decision, and a till that refuses it is a till they
    // work around. The line still prices.
    expect(lineTotalAt(wholesale, 1)).toBe(3000);
  });
});

describe("rules that arrive broken", () => {
  it("treats a missing pieces-per-unit as one piece", () => {
    const pricing = pricingFor({ price_tiers: [] }, 150, "piece");

    expect(lineTotalAt(pricing, 3)).toBe(450);
  });

  it("never lets a zero or negative pack size make an order free", () => {
    for (const pieces of ["0", "-12", "", "abc", null]) {
      const pricing = pricingFor({ pieces_per_unit: pieces }, 150, "dozen");
      expect(lineTotalAt(pricing, 2)).toBe(300);
    }
  });

  it("never puts NaN on a receipt", () => {
    const pricing = pricingFor({ pieces_per_unit: "nonsense" }, 150, "dozen");

    expect(Number.isFinite(lineTotalAt(pricing, 2))).toBe(true);
  });

  it("ignores tiers that are not a list", () => {
    const pricing = pricingFor({ price_tiers: "nope" }, 150, "piece");

    expect(piecePriceAt(pricing, 50)).toBe(150);
  });

  it("falls back to the base price rather than to zero", () => {
    // The direction that matters everywhere in this product: a missing rule
    // costs a dealer their discount, it does not give away the lot.
    const pricing = pricingFor(
      { price_tiers: [{ min_quantity: "", price_per_piece: "" }] },
      150,
      "piece",
    );

    expect(piecePriceAt(pricing, 999)).toBe(150);
  });
});
