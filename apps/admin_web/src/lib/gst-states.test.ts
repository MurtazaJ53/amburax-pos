import { describe, expect, it } from "vitest";

import { GST_STATES, gstinStateMismatch, stateCodeFromGstin } from "./gst-states";

/**
 * The GST state code decides CGST+SGST versus IGST on every bill a shop
 * issues. A wrong value does not error — it mis-files invoices quietly, which
 * is why the form now offers names and cross-checks the GSTIN.
 */
describe("GST_STATES", () => {
  it("keeps the leading zero, because the field is two characters", () => {
    // "7" instead of "07" was one of the two mistakes the old text box invited.
    for (const s of GST_STATES) expect(s.code).toMatch(/^\d{2}$/);
  });

  it("has no duplicate codes", () => {
    const codes = GST_STATES.map((s) => s.code);
    expect(new Set(codes).size).toBe(codes.length);
  });

  it("includes the states this product actually ships to", () => {
    const byCode = Object.fromEntries(GST_STATES.map((s) => [s.code, s.name]));
    expect(byCode["24"]).toBe("Gujarat");
    expect(byCode["27"]).toBe("Maharashtra");
    expect(byCode["07"]).toBe("Delhi");
  });

  it("omits codes that were never assigned", () => {
    // 25 and 28 were merged away. Offering them would let a shopkeeper pick a
    // state that no GSTIN can ever match.
    const codes = GST_STATES.map((s) => s.code);
    expect(codes).not.toContain("25");
    expect(codes).not.toContain("28");
  });
});

describe("stateCodeFromGstin", () => {
  it("reads the state from the first two digits", () => {
    expect(stateCodeFromGstin("24AAAAA0000A1Z5")).toBe("24");
  });

  it("returns nothing for a prefix that is not a state", () => {
    expect(stateCodeFromGstin("99AAAAA0000A1Z5")).toBe("");
    expect(stateCodeFromGstin("")).toBe("");
    expect(stateCodeFromGstin("2")).toBe("");
  });
});

describe("gstinStateMismatch", () => {
  it("says nothing when they agree", () => {
    expect(gstinStateMismatch("24", "24AAAAA0000A1Z5")).toBeNull();
  });

  it("names the state the GSTIN actually belongs to", () => {
    // Telling them "mismatch" is useless; telling them the GSTIN says
    // Maharashtra lets them work out which of the two is the typo.
    expect(gstinStateMismatch("24", "27AAAAA0000A1Z5")).toContain("Maharashtra");
  });

  it("stays quiet while either field is still empty", () => {
    // Warning mid-typing would flag every GSTIN before its second character.
    expect(gstinStateMismatch("24", "")).toBeNull();
    expect(gstinStateMismatch("", "27AAAAA0000A1Z5")).toBeNull();
  });

  it("stays quiet for a GSTIN whose prefix is not a state at all", () => {
    // That is a malformed GSTIN, not a state disagreement, and claiming
    // otherwise would send the shopkeeper to fix the wrong field.
    expect(gstinStateMismatch("24", "99AAAAA0000A1Z5")).toBeNull();
  });
});
