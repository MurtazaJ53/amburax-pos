/** When a bill needs an e-way bill, and what this system will not pretend.
 *
 *  Goods moving above a threshold value need an e-way bill generated on the
 *  government portal before they leave. Miss it and the consignment can be
 *  detained in transit, with the penalty falling on the shop rather than the
 *  transporter.
 *
 *  What this file does NOT do, deliberately: generate one. Business Hub has no
 *  connection to the e-way portal. Anything here that looked like it filed the
 *  return would be far worse than nothing - a shopkeeper would stop checking,
 *  and find out at a checkpoint.
 *
 *  So this reminds, at the one moment somebody can still act on it, and the
 *  number the portal gives back is recorded against the bill so the paperwork
 *  and the sale can be matched afterwards.
 */

/** The value above which a consignment needs an e-way bill.
 *
 *  Fifty thousand rupees is the common national figure. States set their own
 *  for movement inside one state - some lower, a few higher - so this is a
 *  prompt to check, never an assertion about the law.
 */
export const EWAY_THRESHOLD = 50000;

/** Should this bill make somebody think about an e-way bill?
 *
 *  Only for goods actually being sent somewhere. A customer carrying their own
 *  shopping out of the shop is not a consignment in transit, and warning on
 *  every large retail bill would train the shopkeeper to dismiss the one that
 *  mattered.
 */
export function needsEwayBill(total: number, beingDispatched: boolean): boolean {
  return beingDispatched && Number.isFinite(total) && total > EWAY_THRESHOLD;
}

/** The reminder, worded as a question rather than an instruction.
 *
 *  The shop knows its own state's rules and this software does not, so telling
 *  them what the law requires would be inventing authority. Asking whether it
 *  has been done is true in every state.
 */
export function ewayReminder(): string {
  return (
    `This consignment is over ₹${EWAY_THRESHOLD.toLocaleString("en-IN")}. ` +
    `Has the e-way bill been generated? Business Hub cannot create one — ` +
    `record the number here once you have it.`
  );
}
