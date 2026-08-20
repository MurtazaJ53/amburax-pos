import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import {
  BUSINESS_TYPE_OPTIONS,
  FEATURE_TOGGLES,
  HIDDEN_FEATURE_TOGGLES,
  businessTypeLabel,
  isOfferedBusinessType,
} from "./business-types";

/** These lists are the browser's copy of lists the server owns. Nothing at
 *  runtime checks they agree — the server simply 400s, and the shopkeeper sees
 *  a save that did not work with no idea why. So the agreement is pinned here,
 *  by reading the Python. */
const BACKEND = join(__dirname, "../../../backend/platform_apps/shops");

function readBackend(file: string): string {
  return readFileSync(join(BACKEND, file), "utf8");
}

/** The quoted strings inside a top-level `NAME = (...)` tuple. */
function pythonTuple(source: string, constantName: string): string[] {
  const block = source.split(`${constantName} = (`)[1];
  if (block === undefined) {
    throw new Error(`${constantName} not found — renamed, or no longer a tuple?`);
  }
  return [...block.split(")")[0].matchAll(/"([a-z_]+)"/g)].map((m) => m[1]);
}

/** The dict keys returned by a `def NAME(...)` that ends in a dict literal. */
function pythonDictKeys(source: string, functionName: string): string[] {
  const block = source.split(`def ${functionName}(`)[1];
  if (block === undefined) {
    throw new Error(`${functionName} not found — has it been renamed?`);
  }
  return [...block.split("\n\n")[0].matchAll(/^\s+"([a-z_]+)":/gm)].map((m) => m[1]);
}

describe("the parsers themselves", () => {
  // A regex that silently matches nothing would make every test below pass
  // while checking absolutely nothing.
  it("finds the server's lists", () => {
    expect(pythonTuple(readBackend("plans.py"), "BUSINESS_TYPES").length).toBeGreaterThan(3);
    expect(
      pythonTuple(readBackend("settings_views.py"), "FEATURE_TOGGLE_FIELDS").length
    ).toBeGreaterThan(0);
    expect(pythonDictKeys(readBackend("plans.py"), "build_plan_features").length).toBeGreaterThan(3);
  });

  it("fails loudly when a constant is renamed", () => {
    expect(() => pythonTuple("x = 1", "MISSING")).toThrow(/MISSING/);
  });
});

describe("business type options", () => {
  it("only offers types the server will accept", () => {
    const serverTypes = pythonTuple(readBackend("plans.py"), "BUSINESS_TYPES");
    for (const option of BUSINESS_TYPE_OPTIONS) {
      expect(serverTypes).toContain(option.value);
    }
  });

  it("does not offer the deferred types", () => {
    // Pharmacy and restaurant remain valid stored values, so this cannot be
    // asserted against the server's list — only against what we choose to show.
    const offered = BUSINESS_TYPE_OPTIONS.map((option) => option.value);
    expect(offered).not.toContain("pharmacy");
    expect(offered).not.toContain("restaurant");
  });

  it("labels a deferred type a shop still carries", () => {
    expect(businessTypeLabel("pharmacy")).toBe("Pharmacy");
    expect(isOfferedBusinessType("pharmacy")).toBe(false);
    expect(isOfferedBusinessType("retail")).toBe(true);
  });

  it("falls back to Other for a missing type rather than an empty label", () => {
    expect(businessTypeLabel("")).toBe("Other");
  });
});

describe("feature toggles", () => {
  it("only shows switches the settings endpoint will actually write", () => {
    const editable = pythonTuple(readBackend("settings_views.py"), "FEATURE_TOGGLE_FIELDS");
    for (const key of FEATURE_TOGGLES.map((t) => t.key)) {
      // A shown switch the server rejects is a 400 the shopkeeper cannot act on.
      expect(editable).toContain(key);
    }
  });

  it("accounts for every editable flag as either shown or deliberately hidden", () => {
    const editable = pythonTuple(readBackend("settings_views.py"), "FEATURE_TOGGLE_FIELDS");
    const accounted = [
      ...FEATURE_TOGGLES.map((t) => t.key),
      ...HIDDEN_FEATURE_TOGGLES,
    ];
    for (const key of editable) {
      // Not an exact match, because hiding a half-built toggle is legitimate —
      // but it has to be a decision someone wrote down, not a key that fell out
      // of the UI unnoticed.
      expect(accounted).toContain(key);
    }
  });

  it("does not both show and hide the same flag", () => {
    for (const hidden of HIDDEN_FEATURE_TOGGLES) {
      expect(FEATURE_TOGGLES.map((t) => t.key)).not.toContain(hidden);
    }
  });

  it("never offers a plan-gated feature as a shop setting", () => {
    // The free upgrade. The server refuses it too, but a switch that always
    // errors is its own bug.
    const planKeys = pythonDictKeys(readBackend("plans.py"), "build_plan_features");
    for (const toggle of FEATURE_TOGGLES) {
      expect(planKeys).not.toContain(toggle.key);
    }
  });

  it("explains each switch in terms of the counter, not the schema", () => {
    for (const toggle of FEATURE_TOGGLES) {
      expect(toggle.hint.length).toBeGreaterThan(20);
      expect(toggle.label).not.toMatch(/_/);
    }
  });
});
