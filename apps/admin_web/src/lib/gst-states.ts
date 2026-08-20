/**
 * India's GST state codes.
 *
 * The registration form asked for this as a bare two-digit box labelled "State
 * Code". Nobody knows their state code by heart, so the field invited a state
 * name, or "7" where the field means "07" — and nothing rejected either. The
 * consequence is silent: this code decides whether a bill is taxed CGST+SGST
 * or IGST, so a wrong value mis-files every invoice the shop ever issues.
 *
 * The codes are the first two digits of a GSTIN, which is the check a
 * shopkeeper can actually perform on themselves.
 */
export type GstState = { code: string; name: string };

export const GST_STATES: readonly GstState[] = [
  { code: "01", name: "Jammu & Kashmir" },
  { code: "02", name: "Himachal Pradesh" },
  { code: "03", name: "Punjab" },
  { code: "04", name: "Chandigarh" },
  { code: "05", name: "Uttarakhand" },
  { code: "06", name: "Haryana" },
  { code: "07", name: "Delhi" },
  { code: "08", name: "Rajasthan" },
  { code: "09", name: "Uttar Pradesh" },
  { code: "10", name: "Bihar" },
  { code: "11", name: "Sikkim" },
  { code: "12", name: "Arunachal Pradesh" },
  { code: "13", name: "Nagaland" },
  { code: "14", name: "Manipur" },
  { code: "15", name: "Mizoram" },
  { code: "16", name: "Tripura" },
  { code: "17", name: "Meghalaya" },
  { code: "18", name: "Assam" },
  { code: "19", name: "West Bengal" },
  { code: "20", name: "Jharkhand" },
  { code: "21", name: "Odisha" },
  { code: "22", name: "Chhattisgarh" },
  { code: "23", name: "Madhya Pradesh" },
  { code: "24", name: "Gujarat" },
  { code: "26", name: "Dadra & Nagar Haveli and Daman & Diu" },
  { code: "27", name: "Maharashtra" },
  { code: "29", name: "Karnataka" },
  { code: "30", name: "Goa" },
  { code: "31", name: "Lakshadweep" },
  { code: "32", name: "Kerala" },
  { code: "33", name: "Tamil Nadu" },
  { code: "34", name: "Puducherry" },
  { code: "35", name: "Andaman & Nicobar Islands" },
  { code: "36", name: "Telangana" },
  { code: "37", name: "Andhra Pradesh" },
  { code: "38", name: "Ladakh" },
  { code: "97", name: "Other Territory" },
];

/** The state code a GSTIN belongs to — its first two digits — or "". */
export function stateCodeFromGstin(gstin: string): string {
  const trimmed = (gstin || "").trim();
  if (trimmed.length < 2) return "";
  const prefix = trimmed.slice(0, 2);
  return GST_STATES.some((s) => s.code === prefix) ? prefix : "";
}

/**
 * Why a chosen state and a typed GSTIN disagree, or null when they agree.
 *
 * Worth surfacing rather than silently trusting one: a GSTIN whose prefix is
 * not the selected state means one of the two is a typo, and the shopkeeper is
 * the only person who knows which.
 */
export function gstinStateMismatch(
  stateCode: string,
  gstin: string,
): string | null {
  const fromGstin = stateCodeFromGstin(gstin);
  if (!fromGstin || !stateCode || fromGstin === stateCode) return null;
  const named = GST_STATES.find((s) => s.code === fromGstin);
  return named
    ? `This GSTIN starts ${fromGstin}, which is ${named.name}.`
    : `This GSTIN starts ${fromGstin}, which is not a state code.`;
}

/** The 15-character GSTIN shape: 2 state digits, 10-char PAN, entity digit,
 *  'Z', checksum.
 *
 *  Kept identical to GSTIN_PATTERN in shops/settings_views.py. Validating in
 *  the browser is a courtesy — the server rejects a bad one regardless — but a
 *  cashier who only finds out after pressing Pay has already made the customer
 *  wait, and on a B2B bill the GSTIN is the reason the customer came here.
 */
export const GSTIN_PATTERN = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$/;

export function isValidGstin(value: string): boolean {
  return GSTIN_PATTERN.test(value.trim().toUpperCase());
}
