import { describe, expect, it } from "vitest";

import { EWAY_THRESHOLD, ewayReminder, needsEwayBill } from "./eway";

/** A consignment above the threshold needs an e-way bill before it moves.
 *
 *  The rule under test is mostly about when to STAY QUIET. A reminder on every
 *  large bill trains a shopkeeper to dismiss it, and the one they dismiss is
 *  the one that gets their lorry stopped.
 */
describe("when to ask about an e-way bill", () => {
  it("asks about a large consignment being dispatched", () => {
    expect(needsEwayBill(90000, true)).toBe(true);
  });

  it("stays quiet about a large bill the customer carries out themselves", () => {
    // A shopper leaving with their own shopping is not a consignment in
    // transit. Warning here is how the warning stops being read.
    expect(needsEwayBill(90000, false)).toBe(false);
  });

  it("stays quiet below the threshold", () => {
    expect(needsEwayBill(10000, true)).toBe(false);
  });

  it("treats the threshold itself as below the line", () => {
    // The rule is "above", so exactly fifty thousand does not trigger it.
    expect(needsEwayBill(EWAY_THRESHOLD, true)).toBe(false);
    expect(needsEwayBill(EWAY_THRESHOLD + 1, true)).toBe(true);
  });

  it("stays quiet on a total that is not a number", () => {
    expect(needsEwayBill(Number.NaN, true)).toBe(false);
  });
});

describe("what the reminder says", () => {
  it("asks rather than instructs", () => {
    // The shop knows its own state's threshold and this software does not.
    // Telling them what the law requires would be inventing authority.
    expect(ewayReminder()).toContain("?");
  });

  it("admits the software cannot generate one", () => {
    // The important sentence. A control that looked like it filed the return
    // would be worse than no control: the shopkeeper would stop checking, and
    // find out at a checkpoint.
    expect(ewayReminder()).toContain("cannot create one");
  });

  it("names the threshold it is talking about", () => {
    expect(ewayReminder()).toContain("50,000");
  });
});
