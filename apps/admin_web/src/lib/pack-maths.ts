/** Turning "two bags of 50kg at 2,000 a bag" into what the app stores.
 *
 *  The product holds ONE unit per item - kg, or pieces, or metres - and every
 *  figure is in it: stock, sales, purchases. There is no pack size anywhere,
 *  which means a delivery has to be entered in the selling unit or the
 *  numbers go wrong in a way nothing catches.
 *
 *  The trap: a 50kg bag of rice, sold loose by the kilo. Enter quantity 1 and
 *  the bag price, and stock rises by 1 - so the shop believes it has one
 *  kilo, the reorder list screams, and the first customer to buy two kilos
 *  drives it to minus one. The right entry is 50 and the price per kilo.
 *
 *  Nobody should have to do that division at a counter with a delivery man
 *  waiting, so this does it. Storage stays in the selling unit; only the
 *  entry changes.
 */

export type PackEntry = {
  /** How many packs arrived. */
  packs: string;
  /** How many selling units are in one pack. */
  unitsPerPack: string;
  /** What one PACK cost. */
  packCost: string;
};

function toNumber(value: string | number | null | undefined): number {
  const parsed = Number(String(value ?? "").trim());
  return Number.isFinite(parsed) ? parsed : 0;
}

/** Total selling units: packs x units per pack. */
export function packsToUnits(entry: PackEntry): number {
  const packs = toNumber(entry.packs);
  const per = toNumber(entry.unitsPerPack);
  if (packs <= 0 || per <= 0) return 0;
  return round3(packs * per);
}

/** Cost of ONE selling unit: pack cost / units per pack.
 *
 *  Null rather than zero when it cannot be worked out. A zero unit cost
 *  becomes the item's cost price and every margin computed from it, so a
 *  guess here is worse than an empty field.
 */
export function packToUnitCost(entry: PackEntry): number | null {
  const per = toNumber(entry.unitsPerPack);
  const cost = toNumber(entry.packCost);
  if (per <= 0 || cost <= 0) return null;
  return round2(cost / per);
}

/** Is there enough here to convert? */
export function packIsComplete(entry: PackEntry): boolean {
  return packsToUnits(entry) > 0 && packToUnitCost(entry) !== null;
}

/** What the line will actually record, in words, so it can be checked before
 *  it is saved rather than discovered in the stock figures afterwards. */
export function packSummary(entry: PackEntry, unit: string): string {
  if (!packIsComplete(entry)) return "";
  const units = packsToUnits(entry);
  const cost = packToUnitCost(entry);
  const label = unit.trim() || "units";
  return `${units} ${label} at ${cost} each`;
}

/** Line total, which is the figure a delivery note is checked against. */
export function lineTotal(quantity: string | number, unitCost: string | number): number {
  return round2(toNumber(quantity) * toNumber(unitCost));
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function round3(value: number): number {
  return Math.round(value * 1000) / 1000;
}
