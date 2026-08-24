import { describe, expect, it } from "vitest";

import { canManageWorkspace, canViewCosts } from "./roles";

describe("who may see cost prices", () => {
  // The server gates this on role >= ADMIN and returns null to everyone
  // else — indistinguishable from "no cost recorded". The screen has to know
  // the difference before it nags anyone to fill the field in.
  it("lets an owner and an admin see costs", () => {
    expect(canViewCosts("owner")).toBe(true);
    expect(canViewCosts("admin")).toBe(true);
  });

  it("does not let a cashier or a viewer see costs", () => {
    expect(canViewCosts("staff")).toBe(false);
    expect(canViewCosts("viewer")).toBe(false);
  });

  it("denies a signed-out or unknown role", () => {
    expect(canViewCosts(null)).toBe(false);
  });

  it("tracks the same boundary as workspace management", () => {
    for (const role of ["owner", "admin", "staff", "viewer", null] as const) {
      expect(canViewCosts(role)).toBe(canManageWorkspace(role));
    }
  });
});
