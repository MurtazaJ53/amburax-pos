/** What the product form asks for, per kind of shop.
 *
 *  A kirana selling loose dal, a garment retailer stocking one shirt in four
 *  sizes and three colours, and a garment wholesaler selling that shirt by the
 *  dozen are not filling in the same form. Asking a grocer for a size ratio is
 *  noise; not asking a wholesaler for a minimum order quantity means the order
 *  cannot be priced at all.
 *
 *  So the form is described here as DATA rather than written as branches
 *  inside the dialog. Adding a business type - pharmacy with batch and expiry,
 *  restaurant with a recipe - is adding an entry to this file. Nobody has to
 *  find their way through a two-thousand-line component, and nobody can add a
 *  field to one profile while forgetting it exists in another.
 *
 *  Two rules hold across every profile:
 *
 *  1. A hidden field is not a cleared field. Switching profile changes what is
 *     ASKED, never what is stored. A wholesaler who fills in a fabric and then
 *     switches to General keeps the fabric - it is still true of the product.
 *  2. Nothing here is a permission. These are defaults for a shopkeeper who
 *     chose their shop type in the first thirty seconds they ever spent with
 *     the product, long before they knew what the words meant. Any profile can
 *     be picked for any product at any time.
 */

/** Every field the product form knows how to draw. */
export type ProductFieldKey =
  | "name"
  | "sku"
  | "barcode"
  | "category"
  | "photo"
  | "size"
  | "colour"
  | "fabric"
  | "season"
  | "hsn"
  | "gstRate"
  | "costPrice"
  | "sellPrice"
  | "sellingUnit"
  | "piecesPerUnit"
  | "moq"
  | "priceTiers"
  | "stock"
  | "reorderLevel";

export type FieldRule = {
  /** Drawn at all. */
  show: boolean;
  /** Refuses to save while empty. */
  required?: boolean;
  /** Replaces the default label - a garment shop says "Style name". */
  label?: string;
  /** The grey text inside an empty input. */
  placeholder?: string;
  /** One line under the field. Say why it is asked, not what it is. */
  hint?: string;
};

export type ProductProfile = {
  id: string;
  /** What the dropdown shows. The shopkeeper's words, not ours. */
  label: string;
  /** One line under the dropdown, saying what this changes. */
  summary: string;
  /** The shop-level business type this belongs to, matching the server's own
   *  list: retail, wholesale, service, restaurant, pharmacy, grocery, other.
   *  Used only to pick a sensible default. */
  businessType: string;
  fields: Record<ProductFieldKey, FieldRule>;
};

/** The form as it has always been. Every other profile starts here and changes
 *  only what its trade genuinely needs differently. */
const GENERAL: Record<ProductFieldKey, FieldRule> = {
  name: { show: true, required: true, label: "Product name", placeholder: "e.g. Organic Mustard Oil 1L" },
  sku: { show: true, label: "SKU code", placeholder: "e.g. OIL-MUST-1L" },
  barcode: { show: true, label: "Barcode (EAN/UPC)", placeholder: "e.g. 8901234567890" },
  category: { show: true, label: "Category" },
  photo: { show: true, label: "Product photo" },
  size: { show: true, label: "Size / pack", placeholder: "e.g. 1L, 500g" },
  colour: { show: false },
  fabric: { show: false },
  season: { show: false },
  hsn: {
    show: true,
    label: "HSN / SAC code",
    placeholder: "e.g. 1512",
    hint: "Required on a GST invoice. Four digits is enough below ₹5 crore turnover.",
  },
  gstRate: { show: true, label: "GST tax slab" },
  costPrice: { show: true, required: true, label: "Cost / buying price (₹)" },
  sellPrice: { show: true, required: true, label: "Selling price (₹)" },
  sellingUnit: { show: true, label: "Sold by" },
  piecesPerUnit: { show: false },
  moq: { show: false },
  priceTiers: { show: false },
  stock: { show: true, label: "Opening stock" },
  reorderLevel: { show: true, label: "Reorder level" },
};

const from = (
  overrides: Partial<Record<ProductFieldKey, FieldRule>>,
): Record<ProductFieldKey, FieldRule> => ({ ...GENERAL, ...overrides });

export const PRODUCT_PROFILES: ProductProfile[] = [
  {
    id: "general",
    label: "General",
    summary: "The standard form. One product, one price, one code.",
    businessType: "other",
    fields: GENERAL,
  },

  {
    id: "retail_garment",
    label: "Retail Readymade Garment Store",
    summary: "One style in several sizes and colours, sold a piece at a time over the counter.",
    businessType: "retail",
    fields: from({
      name: { show: true, required: true, label: "Style name", placeholder: "e.g. Cotton Casual Shirt" },
      sku: {
        show: true,
        label: "SKU / style code",
        placeholder: "e.g. SHIRT-CTN-BLU",
        hint: "One code per size and colour, so the right variant leaves the shelf.",
      },
      // Size and colour are the whole stock model here, not a note on the
      // side. A garment shop does not stock "a shirt", it stocks a shirt in
      // medium in blue - and that is the thing that runs out.
      size: {
        show: true,
        required: true,
        label: "Sizes",
        placeholder: "S, M, L, XL",
        hint: "Every size you stock this style in.",
      },
      colour: {
        show: true,
        required: true,
        label: "Colours",
        placeholder: "Blue, White, Black",
        hint: "Every colour you stock this style in.",
      },
      fabric: { show: true, label: "Material / fabric", placeholder: "e.g. 100% cotton" },
      season: {
        show: true,
        label: "Season / collection",
        placeholder: "e.g. Summer 2026",
        hint: "What you will search by when it is time to clear old stock.",
      },
      sellingUnit: { show: true, label: "Sold by", hint: "Retail sells a piece at a time." },
      sellPrice: { show: true, required: true, label: "Retail price per piece (₹)" },
    }),
  },

  {
    id: "wholesale_garment",
    label: "Wholesale (Garment Wholesaler)",
    summary: "Sold by the dozen or carton to dealers, with a minimum order and a price that drops in bulk.",
    businessType: "wholesale",
    fields: from({
      name: { show: true, required: true, label: "Design / style name", placeholder: "e.g. Design 4471 Kurta" },
      sku: {
        show: true,
        label: "Design / lot number",
        placeholder: "e.g. LOT-4471",
        hint: "One code per design or lot, not per piece.",
      },
      category: { show: true, label: "Category / lot group" },
      // A wholesaler does not pick sizes individually. A dozen arrives as a
      // fixed ratio, and that ratio is what the dealer is buying.
      size: {
        show: true,
        required: true,
        label: "Size ratio per pack",
        placeholder: "e.g. 1 dozen = 2S + 4M + 4L + 2XL",
        hint: "How sizes are made up inside one pack. Dealers buy the ratio, not the size.",
      },
      colour: {
        show: true,
        label: "Colour assortment",
        placeholder: "e.g. Assorted — 4 colours per dozen",
        hint: "Wholesale packs are usually assorted rather than single-colour.",
      },
      fabric: {
        show: true,
        label: "Material / fabric",
        placeholder: "e.g. Rayon 140 GSM",
        hint: "Dealers buy on fabric and quality grade, so this is worth filling in.",
      },
      season: {
        show: true,
        label: "Season / lot",
        placeholder: "e.g. Winter 2026 lot 3",
        hint: "Wholesale buying is season-driven. This is how a lot gets found again.",
      },
      photo: { show: true, label: "Photo of the design", hint: "One photo per design is enough." },
      // The structural difference. Stock, pricing and the invoice all count in
      // this unit rather than in pieces.
      sellingUnit: {
        show: true,
        required: true,
        label: "Sold by",
        hint: "The unit a dealer orders in. Stock is counted in it too.",
      },
      // Without this the till multiplies dozens by the PIECE price and bills
      // for three pieces when three dozen left the shop - a bill twelve times
      // too small, with every number on screen multiplying correctly.
      piecesPerUnit: {
        show: true,
        required: true,
        label: "Pieces in one unit",
        placeholder: "e.g. 12",
        hint: "How many sellable pieces are inside one dozen or carton. The price above is per piece.",
      },
      moq: {
        show: true,
        required: true,
        label: "Minimum order quantity",
        placeholder: "e.g. 1",
        hint: "The smallest order you will accept, in the unit above.",
      },
      priceTiers: {
        show: true,
        label: "Bulk price slabs",
        hint: "Price per piece drops as the order grows. Leave empty to charge one price.",
      },
      hsn: {
        show: true,
        required: true,
        label: "HSN code",
        placeholder: "e.g. 6109",
        hint: "Mandatory here — your dealers need a proper GST invoice to claim input credit.",
      },
      sellPrice: { show: true, required: true, label: "Base price per piece (₹)" },
      stock: { show: true, label: "Opening stock", hint: "Counted in the unit you sell by." },
      reorderLevel: { show: true, label: "Reorder level", hint: "Per design or lot." },
    }),
  },
];

export const DEFAULT_PROFILE_ID = "general";

export function profileById(id: string | null | undefined): ProductProfile {
  return (
    PRODUCT_PROFILES.find((profile) => profile.id === id) ??
    PRODUCT_PROFILES.find((profile) => profile.id === DEFAULT_PROFILE_ID)!
  );
}

/** The profile to open on, for a shop that has told us what it sells.
 *
 *  A guess, not a rule. It saves a wholesaler picking the same option every
 *  time, and costs a retailer one click when the guess is wrong.
 */
export function profileForBusinessType(businessType: string | null | undefined): ProductProfile {
  const candidate = String(businessType ?? "").trim().toLowerCase();
  return (
    PRODUCT_PROFILES.find(
      (profile) => profile.id !== DEFAULT_PROFILE_ID && profile.businessType === candidate,
    ) ?? profileById(DEFAULT_PROFILE_ID)
  );
}

export function ruleFor(profile: ProductProfile, key: ProductFieldKey): FieldRule {
  return profile.fields[key] ?? GENERAL[key];
}

export function shows(profile: ProductProfile, key: ProductFieldKey): boolean {
  return ruleFor(profile, key).show === true;
}

/** A label with its asterisk already decided. */
export function labelFor(profile: ProductProfile, key: ProductFieldKey): string {
  const rule = ruleFor(profile, key);
  const base = rule.label ?? GENERAL[key].label ?? key;
  return rule.required ? `${base} *` : base;
}

/** Which visible, required fields are still empty.
 *
 *  Only VISIBLE ones. A field the profile does not ask for cannot be missing,
 *  and a wholesaler must never be blocked by a retail requirement they were
 *  never shown. Returns keys so the form can mark each field rather than
 *  showing one sentence about "some fields".
 */
export function missingRequired(
  profile: ProductProfile,
  values: Partial<Record<ProductFieldKey, string>>,
): ProductFieldKey[] {
  return (Object.keys(profile.fields) as ProductFieldKey[]).filter((key) => {
    const rule = ruleFor(profile, key);
    if (!rule.show || !rule.required) return false;
    return String(values[key] ?? "").trim() === "";
  });
}

/** Units a product can be sold by. */
export const SELLING_UNITS = [
  { value: "piece", label: "Piece" },
  { value: "dozen", label: "Dozen" },
  { value: "carton", label: "Carton" },
  { value: "set", label: "Set" },
  { value: "pack", label: "Pack" },
  { value: "kg", label: "Kilogram" },
  { value: "litre", label: "Litre" },
  { value: "metre", label: "Metre" },
] as const;

/** One row of bulk pricing.
 *
 *  Keys match the API exactly rather than being camel-cased and mapped back.
 *  A mapping layer between two shapes of the same thing is one more place for
 *  a price to get lost in translation.
 */
export type PriceTier = {
  /** Order size at which this price starts applying, in the selling unit. */
  min_quantity: string;
  /** Price per piece at that size. */
  price_per_piece: string;
};

export const BLANK_TIER: PriceTier = { min_quantity: "", price_per_piece: "" };

/** Tiers that are filled in and make sense, smallest order first.
 *
 *  Half-typed rows are dropped rather than saved as zeroes: a tier reading
 *  "from 0 units, ₹0 each" would quietly price an entire lot at nothing. The
 *  server drops them too - doing it here as well means the shopkeeper sees the
 *  same list they will get back.
 */
export function cleanTiers(tiers: PriceTier[]): PriceTier[] {
  return tiers
    .filter((tier) => Number(tier.min_quantity) > 0 && Number(tier.price_per_piece) > 0)
    .sort((a, b) => Number(a.min_quantity) - Number(b.min_quantity));
}

/** What is wrong with these slabs, in a sentence a shopkeeper can act on.
 *
 *  Bulk pricing that goes UP with quantity is almost always a typo, and it is
 *  the kind that only surfaces as an argument with a dealer.
 */
export function tierProblem(tiers: PriceTier[]): string | null {
  const clean = cleanTiers(tiers);
  for (let index = 1; index < clean.length; index++) {
    if (clean[index].min_quantity === clean[index - 1].min_quantity) {
      return `Two slabs both start at ${clean[index].min_quantity}. Only one price can apply.`;
    }
    if (Number(clean[index].price_per_piece) > Number(clean[index - 1].price_per_piece)) {
      return `A bigger order should not cost more per piece. Check the slab starting at ${clean[index].min_quantity}.`;
    }
  }
  return null;
}

/** The price per piece at this order size.
 *
 *  Mirrors the server's price_for_quantity exactly, including the fallback: a
 *  broken rule falls back to the base price, never to zero. A till showing a
 *  different number from the invoice is an argument with a dealer the shop
 *  cannot win.
 */
export function priceForQuantity(
  tiers: PriceTier[],
  quantity: number,
  basePrice: number,
): number {
  let price = basePrice;
  for (const tier of cleanTiers(tiers)) {
    if (quantity >= Number(tier.min_quantity)) {
      price = Number(tier.price_per_piece);
    }
  }
  return Number.isFinite(price) ? price : basePrice;
}
