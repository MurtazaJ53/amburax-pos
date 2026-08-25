/** What a shop's money actually goes on.
 *
 *  The list was eight entries long and missed most of a real month: no GST
 *  payment, no rent deposit, no repairs, no marketing, nothing for the bank
 *  charges that quietly take a few hundred rupees. A category that is not
 *  offered gets typed as "Other" or not recorded at all, and then the register
 *  cannot answer the one question it exists for - where did it go.
 *
 *  Grouped, because a flat list of thirty is not read, it is scrolled past.
 *  The server stores a plain string, so this list can grow without a
 *  migration and a shop's own wording still saves.
 */

export type CategoryGroup = {
  group: string;
  items: string[];
};

export const EXPENSE_CATEGORIES: CategoryGroup[] = [
  {
    group: "Premises",
    items: ["Rent", "Electricity", "Water", "Internet & phone", "Repairs & maintenance", "Cleaning"],
  },
  {
    group: "People",
    items: ["Staff salaries", "Staff advance", "Bonus & incentive", "Tea & refreshments", "Staff welfare"],
  },
  {
    group: "Stock & supply",
    items: ["Packaging", "Freight & transport", "Loading & unloading", "Godown rent", "Wastage & damage"],
  },
  {
    group: "Selling",
    items: ["Marketing & ads", "Printing & stationery", "Shop display", "Delivery charges", "Commission"],
  },
  {
    group: "Statutory & finance",
    items: ["GST payment", "Other taxes", "Licence & renewal", "Bank charges", "Loan repayment", "Interest paid", "Insurance"],
  },
  {
    group: "Other",
    items: ["Professional fees", "Travel", "Donation", "Miscellaneous"],
  },
];

/** Flat list, for validation and for matching what is already stored. */
export const ALL_EXPENSE_CATEGORIES: string[] = EXPENSE_CATEGORIES.flatMap(
  (group) => group.items,
);

/** The handful worth a single tap at the counter. */
export const QUICK_EXPENSE_CATEGORIES = [
  "Rent",
  "Electricity",
  "Staff salaries",
  "Freight & transport",
  "Tea & refreshments",
] as const;

/** Which group a category belongs to, for grouping a list of recorded rows.
 *
 *  A category the shop typed itself is not forced into a group it does not
 *  belong to - it reports "Other" rather than a guess.
 */
export function groupFor(category: string): string {
  const needle = category.trim().toLowerCase();
  for (const group of EXPENSE_CATEGORIES) {
    if (group.items.some((item) => item.toLowerCase() === needle)) return group.group;
  }
  return "Other";
}

/** Is this something the shop can save? Only emptiness is refused: a shop
 *  that spends on something this list never imagined must still record it. */
export function isValidCategory(category: string): boolean {
  return category.trim().length > 0;
}
