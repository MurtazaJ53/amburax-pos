import { describe, expect, it } from "vitest";

import {
  ALL_EXPENSE_CATEGORIES,
  EXPENSE_CATEGORIES,
  QUICK_EXPENSE_CATEGORIES,
  groupFor,
  isValidCategory,
} from "./expense-categories";

describe("the category list", () => {
  it("covers a real month rather than eight guesses", () => {
    expect(ALL_EXPENSE_CATEGORIES.length).toBeGreaterThan(25);
  });

  it("includes the ones a shop actually pays and the old list missed", () => {
    for (const needed of ["GST payment", "Bank charges", "Repairs & maintenance", "Loan repayment"]) {
      expect(ALL_EXPENSE_CATEGORIES).toContain(needed);
    }
  });

  it("has no duplicates, which would render two identical options", () => {
    expect(new Set(ALL_EXPENSE_CATEGORIES).size).toBe(ALL_EXPENSE_CATEGORIES.length);
  });

  it("names every group", () => {
    for (const group of EXPENSE_CATEGORIES) {
      expect(group.group.trim()).not.toBe("");
      expect(group.items.length).toBeGreaterThan(0);
    }
  });

  it("offers every quick pick from the full list too", () => {
    // A quick pick that is not in the dropdown cannot be edited back to.
    for (const quick of QUICK_EXPENSE_CATEGORIES) {
      expect(ALL_EXPENSE_CATEGORIES).toContain(quick);
    }
  });
});

describe("groupFor", () => {
  it("finds the group a known category belongs to", () => {
    expect(groupFor("Rent")).toBe("Premises");
    expect(groupFor("GST payment")).toBe("Statutory & finance");
  });

  it("ignores case and stray spacing", () => {
    expect(groupFor("  rENT ")).toBe("Premises");
  });

  it("does not guess a group for a shop's own wording", () => {
    expect(groupFor("Temple donation for Diwali")).toBe("Other");
  });
});

describe("isValidCategory", () => {
  it("accepts a category this list never imagined", () => {
    // A shop that spends on something unusual must still be able to record it.
    expect(isValidCategory("Bullock cart hire")).toBe(true);
  });

  it("refuses only emptiness", () => {
    expect(isValidCategory("")).toBe(false);
    expect(isValidCategory("   ")).toBe(false);
  });
});
