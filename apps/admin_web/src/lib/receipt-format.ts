/** How a receipt is laid out and worded, by region.
 *
 *  The receipt was built for one country. It printed "GST" on every line and
 *  titled itself TAX INVOICE or BILL OF SUPPLY - terms from the Indian GST
 *  rules that mean nothing on a UK till roll, where the tax is VAT and the
 *  document is simply an invoice or a receipt.
 *
 *  Paper differs too. 76mm is the common Indian thermal roll; 80mm is the
 *  usual one in the UK. Printing 76mm content on 80mm paper wastes a strip
 *  down the side, and the other way round clips it.
 */

export type RegionCode = "IN" | "UK";

export type ReceiptFormat = {
  /** Physical paper width, as a CSS length. */
  paperWidth: string;
  /** What the tax is called on this shop's receipts. */
  taxLabel: string;
  /** The tax number's name, for the header line. */
  taxIdLabel: string;
  /** What the document calls itself. */
  title: string;
  /** Buyer's tax number label, printed on a B2B bill. */
  buyerTaxIdLabel: string;
};

export type GstRegistration = "regular" | "composition" | "unregistered" | string;

export function normaliseRegion(raw: string | null | undefined): RegionCode {
  return String(raw ?? "").trim().toUpperCase() === "UK" ? "UK" : "IN";
}

/** Millimetres of paper, by region. */
export function paperWidthFor(region: RegionCode): string {
  return region === "UK" ? "80mm" : "76mm";
}

export function receiptFormat(
  regionRaw: string | null | undefined,
  registration: GstRegistration = "regular",
): ReceiptFormat {
  const region = normaliseRegion(regionRaw);

  if (region === "UK") {
    return {
      paperWidth: paperWidthFor(region),
      taxLabel: "VAT",
      taxIdLabel: "VAT no.",
      buyerTaxIdLabel: "Customer VAT no.",
      // A UK shop issues a VAT invoice when it is registered and a plain
      // receipt when it is not. There is no equivalent of a Bill of Supply.
      title: registration === "unregistered" ? "RECEIPT" : "VAT INVOICE",
    };
  }

  return {
    paperWidth: paperWidthFor(region),
    taxLabel: "GST",
    taxIdLabel: "GSTIN",
    buyerTaxIdLabel: "Buyer GSTIN",
    title:
      registration === "composition"
        ? "BILL OF SUPPLY"
        : registration === "unregistered"
          ? "CASH MEMO"
          : "TAX INVOICE",
  };
}

/** Is the composition wording required? Only ever in India. */
export function needsCompositionNotice(
  regionRaw: string | null | undefined,
  registration: GstRegistration,
): boolean {
  return normaliseRegion(regionRaw) === "IN" && registration === "composition";
}

/** A brand colour the receipt may actually use.
 *
 *  Anything that is not a plain hex is dropped rather than passed through:
 *  this value reaches a style attribute on a document that gets printed and
 *  emailed, and "red; background:url(...)" is not a colour.
 */
export function safeBrandColor(raw: string | null | undefined): string | null {
  const value = String(raw ?? "").trim();
  return /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(value) ? value : null;
}

/** A logo the receipt may actually render. */
export function safeLogo(raw: string | null | undefined): string | null {
  const value = String(raw ?? "").trim();
  return value.startsWith("data:image/") ? value : null;
}
