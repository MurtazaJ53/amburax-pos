/** Selling stock the system does not think you have.
 *
 *  A counter must never refuse a sale because a number in a database says
 *  zero. The customer is standing there with cash, and in a real shop the
 *  count is wrong far more often than the shelf is empty — someone took a
 *  delivery and did not enter it, or a stocktake drifted.
 *
 *  So the sale always goes through. What must not happen is it going
 *  unnoticed: an oversell is a *missing purchase entry*, and the only way it
 *  ever gets corrected is if the screen says so at the moment it happens and
 *  the item turns up on a list afterwards.
 */

export type OversellLine = {
  /** Stock the system believed was on the shelf before this line. */
  available_stock: number;
  /** Units being sold on this line. */
  quantity: number;
  /** Whether the item has ever been given stock. When it has not, its count
   *  is not a belief about the shelf and nothing can be short of it. */
  is_tracked?: boolean;
};

/** Where this line leaves the count. Negative means sold past zero. */
export function resultingStock(line: OversellLine): number {
  const available = Number(line.available_stock);
  const quantity = Number(line.quantity);
  return (
    (Number.isFinite(available) ? available : 0) -
    (Number.isFinite(quantity) ? quantity : 0)
  );
}

/** Does this line take a tracked count below zero?
 *
 *  Untracked items are excluded, and this is the whole point of the flag.
 *  Warning that an item nobody ever counted "will go to -1" states a
 *  shortfall against a number that was never a claim about anything. It
 *  teaches the cashier that the warning means nothing, which is worse than
 *  showing no warning at all.
 */
export function isOversell(line: OversellLine): boolean {
  if (line.is_tracked === false) return false;
  return resultingStock(line) < 0;
}

/** How many units of this line were never recorded as bought. */
export function unrecordedUnits(line: OversellLine): number {
  const result = resultingStock(line);
  return result < 0 ? Math.abs(result) : 0;
}

/** Lines in a cart that will take stock negative. */
export function oversellLines<T extends OversellLine>(cart: T[]): T[] {
  return cart.filter(isOversell);
}

/** One sentence for the cart, or "" when nothing is oversold.
 *
 *  Deliberately not phrased as an error. Nothing has gone wrong — the shop
 *  sold something. The message names the consequence and where to fix it.
 */
export function oversellSummary(cart: OversellLine[]): string {
  const lines = oversellLines(cart);
  if (lines.length === 0) return "";
  const noun = lines.length === 1 ? "item" : "items";
  return `${lines.length} ${noun} will go below zero. Sale still goes through — add the missing purchase in Stock.`;
}
