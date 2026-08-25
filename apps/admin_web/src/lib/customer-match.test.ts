import { describe, expect, it } from "vitest";

import {
  canIdentifyCustomer,
  canOpenKhataAccount,
  customerRequired,
  findExistingCustomer,
  missingForKhata,
  nameKey,
  phoneKey,
} from "./customer-match";
import type { Customer } from "./types";

function cust(overrides: Partial<Customer>): Customer {
  return { id: "c1", name: "Murtaza Ravan", phone: "+919586585392", ...overrides } as Customer;
}

const BOOK = [
  cust({ id: "c1", name: "Murtaza Ravan", phone: "+919586585392" }),
  cust({ id: "c2", name: "Karan", phone: "9098368468" }),
  cust({ id: "c3", name: "Raj Bhai", phone: "" }),
];

describe("the comparable part of a phone number", () => {
  it("ignores the country code, so +91 and bare digits are one person", () => {
    expect(phoneKey("+919586585392")).toBe(phoneKey("9586585392"));
  });

  it("ignores spaces, dashes and brackets", () => {
    expect(phoneKey("+91 95865-85392")).toBe("9586585392");
  });

  it("keeps a short number as typed rather than inventing digits", () => {
    expect(phoneKey("12345")).toBe("12345");
  });

  it("treats nothing as nothing", () => {
    expect(phoneKey(null)).toBe("");
    expect(phoneKey(undefined)).toBe("");
  });
});

describe("matching someone already on the books", () => {
  // The whole point: one person, one khata. A second account splits their
  // balance and neither figure is what they owe.
  it("finds an existing customer typed without the country code", () => {
    expect(findExistingCustomer(BOOK, "", "9586585392")?.id).toBe("c1");
  });

  it("finds them when typed with it", () => {
    expect(findExistingCustomer(BOOK, "", "+91 9098368468")?.id).toBe("c2");
  });

  it("matches on name when no phone was given at all", () => {
    expect(findExistingCustomer(BOOK, "raj bhai", "")?.id).toBe("c3");
  });

  it("ignores case and extra spaces in a name", () => {
    expect(findExistingCustomer(BOOK, "  MURTAZA   RAVAN ", "")?.id).toBe("c1");
  });

  it("does NOT match by name when a different phone was typed", () => {
    // Two people can share a name. Attaching the wrong one would bill a
    // stranger's khata, so a supplied number that matches nobody means new.
    expect(findExistingCustomer(BOOK, "Karan", "9999900000")).toBeNull();
  });

  it("returns null when nothing was typed", () => {
    expect(findExistingCustomer(BOOK, "", "")).toBeNull();
  });

  it("returns null against an empty book", () => {
    expect(findExistingCustomer([], "Karan", "9098368468")).toBeNull();
  });
});

describe("when a customer is actually required", () => {
  it("is required as soon as any of the bill goes on khata", () => {
    expect(customerRequired(1)).toBe(true);
  });

  it("is not required for a fully paid bill", () => {
    // A walk-in paying cash must never be interrogated for a name.
    expect(customerRequired(0)).toBe(false);
  });
});

describe("having enough to open an account", () => {
  it("accepts a name alone", () => {
    expect(canIdentifyCustomer("Karan", "")).toBe(true);
  });

  it("accepts a full phone number alone", () => {
    expect(canIdentifyCustomer("", "9586585392")).toBe(true);
  });

  it("rejects blanks and half-typed numbers", () => {
    expect(canIdentifyCustomer("", "")).toBe(false);
    expect(canIdentifyCustomer("   ", "98765")).toBe(false);
  });
});

describe("canOpenKhataAccount", () => {
  it("needs both a name and a full phone number", () => {
    expect(canOpenKhataAccount("Raju", "9876543210")).toBe(true);
  });

  it("refuses a name alone, which is not someone you can chase", () => {
    // Two Rajus become one account or two depending on who typed first.
    expect(canOpenKhataAccount("Raju", "")).toBe(false);
  });

  it("refuses a phone alone", () => {
    expect(canOpenKhataAccount("", "9876543210")).toBe(false);
  });

  it("refuses a half-typed number", () => {
    expect(canOpenKhataAccount("Raju", "98765")).toBe(false);
  });

  it("ignores the way a number was written", () => {
    expect(canOpenKhataAccount("Raju", "+91 98765 43210")).toBe(true);
  });

  it("does not accept whitespace as a name", () => {
    expect(canOpenKhataAccount("   ", "9876543210")).toBe(false);
  });
});

describe("missingForKhata", () => {
  it("says nothing when both are there", () => {
    expect(missingForKhata("Raju", "9876543210")).toBe("");
  });

  it("names the one that is missing, not both", () => {
    expect(missingForKhata("Raju", "")).toContain("phone");
    expect(missingForKhata("Raju", "")).not.toContain("Name and");
    expect(missingForKhata("", "9876543210")).toBe("Name needed to open a khata.");
  });

  it("asks for both when neither is given", () => {
    expect(missingForKhata("", "")).toBe("Name and phone number needed to open a khata.");
  });
});
