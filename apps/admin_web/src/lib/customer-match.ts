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
