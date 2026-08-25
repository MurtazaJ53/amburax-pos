import { describe, expect, it } from "vitest";

import {
  needsCompositionNotice,
  normaliseRegion,
  paperWidthFor,
  receiptFormat,
  safeBrandColor,
  safeLogo,
} from "./receipt-format";

describe("normaliseRegion", () => {
  it("recognises the UK however it is written", () => {
    expect(normaliseRegion("uk")).toBe("UK");
    expect(normaliseRegion(" UK ")).toBe("UK");
  });

  it("defaults to India, which is what most shops are", () => {
    expect(normaliseRegion("IN")).toBe("IN");
    expect(normaliseRegion("")).toBe("IN");
    expect(normaliseRegion(null)).toBe("IN");
    expect(normaliseRegion("ZZ")).toBe("IN");
  });
});

describe("paperWidthFor", () => {
  it("uses the roll each country actually sells", () => {
    // 76mm content on 80mm paper wastes a strip; the other way clips it.
    expect(paperWidthFor("IN")).toBe("76mm");
    expect(paperWidthFor("UK")).toBe("80mm");
  });
});

describe("receiptFormat", () => {
  it("calls the tax what the country calls it", () => {
    expect(receiptFormat("IN").taxLabel).toBe("GST");
    expect(receiptFormat("UK").taxLabel).toBe("VAT");
    expect(receiptFormat("IN").taxIdLabel).toBe("GSTIN");
    expect(receiptFormat("UK").taxIdLabel).toBe("VAT no.");
  });

  it("titles an Indian document by its registration", () => {
    expect(receiptFormat("IN", "regular").title).toBe("TAX INVOICE");
    expect(receiptFormat("IN", "composition").title).toBe("BILL OF SUPPLY");
    expect(receiptFormat("IN", "unregistered").title).toBe("CASH MEMO");
  });

  it("never prints an Indian document title on a UK receipt", () => {
    // Bill of Supply is a GST term. It means nothing on a UK till roll.
    for (const registration of ["regular", "composition", "unregistered"]) {
      expect(receiptFormat("UK", registration).title).not.toContain("SUPPLY");
      expect(receiptFormat("UK", registration).title).not.toContain("CASH MEMO");
    }
  });

  it("gives an unregistered UK shop a plain receipt, not a VAT invoice", () => {
    expect(receiptFormat("UK", "unregistered").title).toBe("RECEIPT");
    expect(receiptFormat("UK", "regular").title).toBe("VAT INVOICE");
  });
});

describe("needsCompositionNotice", () => {
  it("is required for an Indian composition dealer", () => {
    expect(needsCompositionNotice("IN", "composition")).toBe(true);
  });

  it("never applies outside India", () => {
    expect(needsCompositionNotice("UK", "composition")).toBe(false);
  });

  it("does not apply to other Indian registrations", () => {
    expect(needsCompositionNotice("IN", "regular")).toBe(false);
  });
});

describe("safeBrandColor", () => {
  it("accepts both hex forms", () => {
    expect(safeBrandColor("#0369A1")).toBe("#0369A1");
    expect(safeBrandColor("#0af")).toBe("#0af");
  });

  it("drops anything that is not a colour", () => {
    // It reaches a style attribute on a document that gets printed and emailed.
    for (const bad of ["red", "0369A1", "#12345", "red; background:url(x)", ""]) {
      expect(safeBrandColor(bad)).toBeNull();
    }
    expect(safeBrandColor(null)).toBeNull();
  });
});

describe("safeLogo", () => {
  it("accepts an inline image", () => {
    expect(safeLogo("data:image/png;base64,AAAA")).toBe("data:image/png;base64,AAAA");
  });

  it("refuses a URL, which a print dialog may not be online to fetch", () => {
    expect(safeLogo("https://example.com/logo.png")).toBeNull();
  });

  it("refuses a data URI that is not an image", () => {
    expect(safeLogo("data:text/html,<script>alert(1)</script>")).toBeNull();
  });
});
