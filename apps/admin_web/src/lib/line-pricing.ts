/** What one line of a bill costs, when the shop does not sell in ones.
 *
 *  Retail sells a piece and charges the piece price, so a line is quantity
 *  times price and nothing here matters. Wholesale is structurally different
 *  in two ways at once, and the till got both wrong:
 *
 *  1. The quantity is in DOZENS or CARTONS, not pieces.
 *  2. The price is quoted PER PIECE - "250 a piece for one dozen" - and it
 *     DROPS as the order grows.
 *
 *  So three dozen at 250 a piece is 3 x 12 x 250 = 9,000, and the till billed
 *  3 x 250 = 750. Nothing on screen looked wrong: a quantity of three, a price
 *  of 250, a total that multiplies correctly. Only the unit was missing, and
 *  the unit is the whole difference.
 *
 *  Every consumer - the cart, the checkout total, the printed receipt - uses
 *  this one function. A till and an invoice disagreeing about a line is an
 *  argument with a dealer that the shop cannot win.
 */

import { cleanTiers, priceForQuantity, type PriceTier } from "@/lib/product-profiles";

/** The pricing rules carried by a product, in the shape the API stores them. */
export type LinePricing = {
  /** Price per piece before any bulk slab applies. */
  basePrice: number;
  /** Sellable pieces inside one ordered unit. One for anything sold singly. */
  piecesPerUnit: number;
  /** Bulk slabs, keyed on the ordered quantity in units. */
  tiers: PriceTier[];
  /** Smallest order the shop will accept, in units. Zero means no minimum. */
  minimumOrder: number;
  /** What one unit is called on screen: piece, dozen, carton. */
  unit: string;
};

/** A positive number, or the fallback. Never NaN, never negative.
 *
 *  Attributes arrive as strings from the API and as whatever a shopkeeper
 *  typed into the form. A NaN reaching the arithmetic turns a line total into
 *  "NaN" on a receipt; a zero pieces-per-unit makes an entire wholesale order
 *  free.
 */
function positive(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

/** Read the pricing rules off a product's attributes.
 *
 *  The defaults are deliberately the retail ones, so a product with no
 *  attributes at all - which is every product in every existing shop - prices
 *  exactly as it always did.
 */
export function pricingFor(
  attributes: Record<string, unknown> | null | undefined,
  basePrice: number,
  unit: string,
): LinePricing {
  const source = attributes ?? {};
  return {
    basePrice,
    piecesPerUnit: positive(source.pieces_per_unit, 1),
    tiers: Array.isArray(source.price_tiers) ? (source.price_tiers as PriceTier[]) : [],
    minimumOrder: positive(source.moq, 0),
    unit: unit || "piece",
  };
}

/** The price of ONE PIECE at this order size, after bulk slabs. */
export function piecePriceAt(pricing: LinePricing, quantity: number): number {
  return priceForQuantity(pricing.tiers, quantity, pricing.basePrice);
}

/** What the till charges for one unit at this order size.
 *
 *  This is the number the cart shows against the line, because the cart shows
 *  a quantity in units. Twelve pieces at 250 is 3,000 for one dozen.
 */
export function unitPriceAt(pricing: LinePricing, quantity: number): number {
  return piecePriceAt(pricing, quantity) * pricing.piecesPerUnit;
}

/** The whole line, before any manual discount. */
export function lineTotalAt(pricing: LinePricing, quantity: number): number {
  return unitPriceAt(pricing, quantity) * quantity;
}

/** Does this product sell in anything other than single pieces? */
export function sellsInPacks(pricing: LinePricing): boolean {
  return pricing.piecesPerUnit > 1;
}

/** Whether a bulk slab is currently reducing the price, and by how much.
 *
 *  Shown on the line so a cashier can tell a dealer why the price moved when
 *  they added one more dozen. A price that changes with no explanation reads
 *  as the till making things up.
 */
export function slabApplied(
  pricing: LinePricing,
  quantity: number,
): { applied: boolean; piecePrice: number; savedPerPiece: number } {
  const piecePrice = piecePriceAt(pricing, quantity);
  const saved = pricing.basePrice - piecePrice;
  return {
    applied: cleanTiers(pricing.tiers).length > 0 && saved > 0,
    piecePrice,
    savedPerPiece: saved > 0 ? saved : 0,
  };
}

/** How far below the minimum order this line is, in units. Zero when fine.
 *
 *  Reported rather than enforced. The rule belongs to the shop, not to the
 *  software: a wholesaler letting one dealer take half a carton is making a
 *  commercial decision, and a till that refuses it is a till they work around.
 *  So the number is surfaced and the sale is never blocked - the same
 *  reasoning that lets this product oversell.
 */
export function belowMinimum(pricing: LinePricing, quantity: number): number {
  if (pricing.minimumOrder <= 0) return 0;
  const short = pricing.minimumOrder - quantity;
  return short > 0 ? short : 0;
}
