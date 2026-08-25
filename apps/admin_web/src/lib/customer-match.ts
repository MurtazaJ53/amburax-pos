import type { Customer } from "@/lib/types";

/** Finding the person who is already on the books.
 *
 *  A khata is only worth anything if every bill for one person lands on one
 *  account. Typing "9586585392" at the till when that customer is stored as
 *  "+91 95865 85392" must attach the existing account, not open a second one
 *  — otherwise their balance splits in two and neither figure is what they
 *  actually owe.
 */

/** The comparable part of an Indian phone number.
 *
 *  Country code, spaces, dashes and brackets are presentation. The last ten
 *  digits are the person.
 */
export function phoneKey(raw: string | null | undefined): string {
  const digits = String(raw ?? "").replace(/\D/g, "");
  if (digits.length < 10) return digits;
  return digits.slice(-10);
}

/** Loose name key, so "Murtaza  Ravan" and "murtaza ravan" are one person. */
export function nameKey(raw: string | null | undefined): string {
  return String(raw ?? "").trim().toLowerCase().replace(/\s+/g, " ");
}

/**
 * An existing customer matching what was typed, or null.
 *
 * Phone wins outright: two people can share a name, but a number is theirs.
 * A name match is only trusted when no phone was given at all — otherwise
 * typing a new number for "Raj Bhai" would silently bill the wrong Raj.
 */
export function findExistingCustomer(
  customers: Customer[],
  typedName: string,
  typedPhone: string,
): Customer | null {
  const phone = phoneKey(typedPhone);
  if (phone.length === 10) {
    const byPhone = customers.find((c) => phoneKey(c.phone) === phone);
    if (byPhone) return byPhone;
    // A real number that matches nobody is a genuinely new customer, even if
    // the name happens to collide with someone already on the books.
    return null;
  }

  const name = nameKey(typedName);
  if (!name) return null;
  return customers.find((c) => nameKey(c.name) === name) ?? null;
}

/** Whether the bill can be completed with the customer details given.
 *
 *  Credit needs somebody to collect from later, so a khata amount requires an
 *  identified customer. Cash, card and UPI do not — a walk-in should never be
 *  interrogated for a name to hand over a hundred rupees.
 */
export function customerRequired(khataAmount: number): boolean {
  return khataAmount > 0;
}

/** Enough to open an account with: a name, or a usable phone number. */
export function canIdentifyCustomer(typedName: string, typedPhone: string): boolean {
  return nameKey(typedName).length > 0 || phoneKey(typedPhone).length === 10;
}

/** Optional details a new account can carry, none of which gate the sale. */
export type NewCustomerDetails = {
  address?: string;
  email?: string;
};

/**
 * Is there enough here to OPEN a khata account for someone new?
 *
 * Stricter than `canIdentifyCustomer` on purpose. A name alone is enough to
 * label a paid bill, but a debt has to be collectable: "Raju" is not someone
 * you can chase in three weeks, and two Rajus become one account or two
 * depending on who typed first. A phone number is the one field that makes a
 * khata customer findable again, so a NEW account needs both.
 *
 * An existing customer never goes through this - they already have whatever
 * details were taken when the account was opened.
 */
export function canOpenKhataAccount(typedName: string, typedPhone: string): boolean {
  return nameKey(typedName).length > 0 && phoneKey(typedPhone).length === 10;
}

/** What is still missing before credit can be given to someone new. */
export function missingForKhata(typedName: string, typedPhone: string): string {
  const hasName = nameKey(typedName).length > 0;
  const hasPhone = phoneKey(typedPhone).length === 10;
  if (hasName && hasPhone) return "";
  if (!hasName && !hasPhone) return "Name and phone number needed to open a khata.";
  if (!hasName) return "Name needed to open a khata.";
  return "A 10-digit phone number is needed to open a khata.";
}
