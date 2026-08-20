/** The kinds of shop we offer at signup, and what choosing one turns on.
 *
 *  One list, imported by both the signup form and the settings page. They used
 *  to be two copies of the same five options, which is the kind of duplication
 *  that stays correct until the day someone adds a type to one of them.
 */

/** Types offered in a dropdown.
 *
 *  Pharmacy and restaurant are deliberately absent. Both remain valid *stored*
 *  values — a shop already carrying one keeps it, and the settings page adds it
 *  back as an option so saving never silently rewrites their type — but neither
 *  is offered, because the app does not yet do what choosing them implies:
 *  batch and expiry tracking for a pharmacy (a licensing matter, not a
 *  convenience), and tables and orders for a restaurant. Both are planned.
 */
export const BUSINESS_TYPE_OPTIONS = [
  { value: "retail", label: "Retail" },
  { value: "wholesale", label: "Wholesale" },
  { value: "grocery", label: "Grocery" },
  { value: "service", label: "Service" },
  { value: "other", label: "Other" },
] as const;

export type BusinessTypeValue = (typeof BUSINESS_TYPE_OPTIONS)[number]["value"];

/** The only feature flags the settings endpoint will accept.
 *
 *  The server rejects any other key with a 400, on purpose: the plan's flags
 *  are decided by what has been paid for, and a settings toggle that could
 *  write them would be a free upgrade for every workspace. So this list must
 *  never grow without FEATURE_TOGGLE_FIELDS in settings_views.py agreeing.
 *
 *  Hints are written for a shopkeeper, not for us. "Product variants" means
 *  nothing until you know it is the reason one shirt can be four sizes.
 */
export const FEATURE_TOGGLES = [
  {
    key: "weight_selling",
    label: "Sell things by weight",
    hint: "Weigh loose items at the counter and price them per kilo.",
  },
  {
    key: "product_variants",
    label: "One product, many sizes or colours",
    hint: "Keep a shirt as a single item with its own count for each size.",
  },
  {
    key: "gstin_on_every_bill",
    label: "Ask for the buyer's GSTIN on every bill",
    hint: "For selling to other businesses, who need it to claim input credit.",
  },
] as const;

/** A label for a stored type, including the ones no longer offered. */
export function businessTypeLabel(value: string): string {
  const known = BUSINESS_TYPE_OPTIONS.find((option) => option.value === value);
  if (known) return known.label;
  if (!value) return "Other";
  return value.charAt(0).toUpperCase() + value.slice(1);
}

/** Whether a stored type is one the dropdown still offers. */
export function isOfferedBusinessType(value: string): boolean {
  return BUSINESS_TYPE_OPTIONS.some((option) => option.value === value);
}
