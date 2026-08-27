/**
 * Spreadsheet import: read a file exported from almost anywhere, then map its
 * columns onto our canonical fields by fuzzy header matching.
 *
 * Port of `apps/mobile_flutter/lib/core/import/universal_import.dart`. The
 * field keys, synonyms and normalisation must match, or the same file would
 * import differently on the phone and on the web.
 *
 * Pure and UI-free so it can be tested; the page adds file picking, a mapping
 * preview the shopkeeper can override, and the upload.
 */

export type ImportKind = "products" | "customers" | "sales";

export type ImportField = {
  key: string;
  label: string;
  synonyms?: string[];
  required?: boolean;
  type?: "text" | "number";
};

/** Order matters: an earlier field wins a contested column. */
export const IMPORT_SCHEMAS: Record<ImportKind, ImportField[]> = {
  products: [
    {
      key: "name",
      label: "Item name",
      required: true,
      synonyms: ["item", "product", "product name", "title", "description", "particulars"],
    },
    {
      key: "price",
      label: "Price",
      type: "number",
      synonyms: ["mrp", "rate", "selling price", "sale price", "sell price", "unit price", "amount"],
    },
    {
      key: "costPrice",
      label: "Cost price",
      type: "number",
      synonyms: ["cost", "purchase price", "buy price", "cp", "purchase rate"],
    },
    {
      key: "stock",
      label: "Stock",
      type: "number",
      synonyms: ["qty", "quantity", "on hand", "available", "stock on hand", "opening stock", "inventory", "in stock"],
    },
    { key: "sku", label: "SKU", synonyms: ["code", "item code", "product code"] },
    { key: "barcode", label: "Barcode", synonyms: ["ean", "upc", "qr"] },
    { key: "category", label: "Category", synonyms: ["cat", "group", "department", "type"] },
    { key: "hsnCode", label: "HSN", synonyms: ["hsn code", "hsn/sac", "sac"] },
    {
      key: "gstRate",
      label: "GST rate",
      type: "number",
      synonyms: ["gst", "tax", "tax rate", "gst %", "gst percent"],
    },
  ],
  customers: [
    {
      key: "name",
      label: "Name",
      required: true,
      synonyms: ["customer", "customer name", "client", "client name", "party", "party name"],
    },
    {
      key: "phone",
      label: "Phone",
      synonyms: ["mobile", "contact", "number", "phone number", "mobile number", "whatsapp", "contact number"],
    },
    { key: "email", label: "Email", synonyms: ["email id", "e-mail", "mail"] },
    {
      key: "amountDue",
      label: "Amount due",
      type: "number",
      synonyms: ["balance", "due", "outstanding", "credit", "pending", "closing balance", "opening balance"],
    },
    {
      key: "advance",
      label: "Advance",
      type: "number",
      synonyms: ["amount held", "deposit", "prepaid", "advance paid"],
    },
  ],
  sales: [
    {
      key: "date",
      label: "Date",
      required: true,
      synonyms: ["bill date", "invoice date", "sale date", "day", "dt"],
    },
    {
      key: "total",
      label: "Bill total",
      type: "number",
      required: true,
      synonyms: ["amount", "grand total", "net", "value", "bill amount", "sale amount"],
    },
    {
      key: "id",
      label: "Bill number",
      synonyms: ["invoice", "invoice no", "bill no", "receipt", "receipt no", "voucher"],
    },
    {
      key: "payment_mode",
      label: "Paid by",
      synonyms: ["mode", "payment", "type", "tender", "paid via"],
    },
    {
      key: "customer_name",
      label: "Customer",
      synonyms: ["party", "party name", "client", "buyer", "name"],
    },
    {
      key: "customer_phone",
      label: "Customer phone",
      synonyms: ["mobile", "contact", "phone number"],
    },
    {
      key: "discount",
      label: "Discount",
      type: "number",
      synonyms: ["disc", "less", "rebate"],
    },
  ],
};

/**
 * Lowercase and strip everything but a-z0-9, so "Item Name", "item_name" and
 * "ITEM-NAME" all collapse to "itemname".
 */
export function normalizeHeader(header: string): string {
  return header.toLowerCase().replace(/[^a-z0-9]/g, "");
}

export type ParsedTable = {
  headers: string[];
  rows: string[][];
};

/**
 * Parse CSV, honouring quoted fields that contain commas, quotes or newlines —
 * an address column breaks a naive split on every real export.
 */
export function parseCsv(text: string): ParsedTable {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;

  // Strip a UTF-8 BOM; Excel writes one and it corrupts the first header.
  const input = text.replace(/^﻿/, "");

  for (let i = 0; i < input.length; i += 1) {
    const char = input[i];

    if (inQuotes) {
      if (char === '"') {
        if (input[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += char;
      }
      continue;
    }

    if (char === '"') {
      inQuotes = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n" || char === "\r") {
      // Treat \r\n as one break.
      if (char === "\r" && input[i + 1] === "\n") i += 1;
      row.push(field);
      field = "";
      rows.push(row);
      row = [];
    } else {
      field += char;
    }
  }
  // Whatever is left when the file ends without a trailing newline.
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  const cleaned = rows.filter((r) => r.some((cell) => cell.trim() !== ""));
  if (cleaned.length === 0) return { headers: [], rows: [] };

  return {
    headers: cleaned[0].map((h) => h.trim()),
    rows: cleaned.slice(1),
  };
}

export type FieldMapping = Record<string, number>;

/**
 * Match the file's headers to a kind's canonical fields.
 *
 * Two passes, mirroring the Dart version: exact normalised equality first, so
 * a column literally called "Price" cannot be stolen by a fuzzy match, then
 * substring matching for the rest.
 */
export function autoMap(headers: string[], kind: ImportKind): FieldMapping {
  const fields = IMPORT_SCHEMAS[kind];
  const normalised = headers.map(normalizeHeader);
  const mapping: FieldMapping = {};
  const taken = new Set<number>();

  const needles = (field: ImportField) =>
    [field.key, field.label, ...(field.synonyms ?? [])].map(normalizeHeader);

  // Pass 1: exact. Iterate the NEEDLES in priority order (key, then label,
  // then synonyms) rather than the headers, so a column literally called
  // "Price" beats one called "Selling Price". The Dart version does the same,
  // and a divergence here would map the same file differently on each surface.
  for (const field of fields) {
    for (const needle of needles(field)) {
      const index = normalised.findIndex((h, i) => !taken.has(i) && h === needle);
      if (index !== -1) {
        mapping[field.key] = index;
        taken.add(index);
        break;
      }
    }
  }

  // Pass 2: substring, for headers like "Selling Price (INR)".
  for (const field of fields) {
    if (field.key in mapping) continue;
    const wanted = needles(field).filter((n) => n.length >= 3);
    const index = normalised.findIndex(
      (h, i) => !taken.has(i) && h.length > 0 && wanted.some((n) => h.includes(n) || n.includes(h))
    );
    if (index !== -1) {
      mapping[field.key] = index;
      taken.add(index);
    }
  }

  return mapping;
}

/** Numbers from a spreadsheet arrive as "1,234.50", "₹1234", "(50)" or "". */
export function parseNumber(raw: string | undefined): number {
  if (!raw) return 0;
  let text = raw.trim();
  if (!text) return 0;
  // Accounting negatives: (50) means -50.
  const bracketed = /^\((.*)\)$/.exec(text);
  if (bracketed) text = `-${bracketed[1]}`;
  const cleaned = text.replace(/[^0-9.-]/g, "");
  const value = parseFloat(cleaned);
  return Number.isFinite(value) ? value : 0;
}

export type MappedRow = Record<string, string>;

/** Apply a mapping to the raw rows, dropping ones with no required value. */
export function applyMapping(
  table: ParsedTable,
  kind: ImportKind,
  mapping: FieldMapping
): { rows: MappedRow[]; skipped: number } {
  const fields = IMPORT_SCHEMAS[kind];
  const required = fields.filter((f) => f.required).map((f) => f.key);

  const rows: MappedRow[] = [];
  let skipped = 0;

  for (const raw of table.rows) {
    const mapped: MappedRow = {};
    for (const [key, column] of Object.entries(mapping)) {
      mapped[key] = (raw[column] ?? "").trim();
    }
    // A row with no name is a spacer or a totals line, not a product.
    if (required.some((key) => !mapped[key])) {
      skipped += 1;
      continue;
    }
    rows.push(mapped);
  }

  return { rows, skipped };
}

/** Shape a mapped row into the payload the bulk endpoint expects. */
export function toInventoryPayload(row: MappedRow): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    name: row.name,
    sell_price: parseNumber(row.price).toFixed(2),
    opening_stock: parseNumber(row.stock),
    sku: row.sku ?? "",
    barcode: row.barcode ?? "",
    category: (row.category ?? "").trim() || "General",
    hsn_code: row.hsnCode ?? "",
    gst_rate: parseNumber(row.gstRate).toFixed(2),
    status: "active",
  };
  // Only send a cost when the sheet had one: 0.00 means "not recorded", and
  // the reports treat those differently.
  if (row.costPrice && parseNumber(row.costPrice) > 0) {
    payload.private_cost_price = parseNumber(row.costPrice).toFixed(2);
  }
  return payload;
}

export function toCustomerPayload(row: MappedRow): Record<string, unknown> {
  // A sheet can carry either a due or an advance. An advance is money the shop
  // holds, so it is a negative balance.
  const due = parseNumber(row.amountDue);
  const advance = parseNumber(row.advance);
  const balance = due > 0 ? due : -advance;
  return {
    name: row.name,
    phone: row.phone ?? "",
    email: row.email ?? "",
    opening_balance: balance.toFixed(2),
  };
}


/** One past bill, as the history importer takes it.
 *
 *  `id` is the bill number from the old system and doubles as the key that
 *  stops a re-import creating a second copy - so a file with no bill numbers
 *  gets one derived from the row, which is stable for that file but will not
 *  recognise the same bill arriving under a different name later.
 */
export function toSalePayload(row: MappedRow, index: number): Record<string, unknown> {
  const billNumber = (row.id ?? "").trim();
  return {
    id: billNumber || `row-${index + 1}-${(row.date ?? "").trim()}`,
    date: (row.date ?? "").trim(),
    total: parseNumber(row.total),
    discount: parseNumber(row.discount),
    payment_mode: (row.payment_mode ?? "").trim().toUpperCase(),
    customer_name: (row.customer_name ?? "").trim(),
    customer_phone: (row.customer_phone ?? "").trim(),
  };
}
