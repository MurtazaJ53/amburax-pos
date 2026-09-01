/** Working out what a spreadsheet actually holds, before it is written.
 *
 *  The import screen asks which kind of data a file is and then trusts the
 *  answer. Products and customers each require exactly one column - a name -
 *  so a customer list dropped in with "Products" still selected imports
 *  perfectly: every customer becomes a product with a name, no price and no
 *  stock. Nothing fails, nothing warns, and the catalogue fills up with
 *  people.
 *
 *  So the file gets a vote. Its headers are scored against every schema, and
 *  when they disagree with the choice on screen that is worth stopping for -
 *  it is far likelier that somebody forgot to change the selector than that
 *  they meant to import three hundred customers as stock.
 *
 *  Scoring is by distinctive columns rather than by counting matches. "Name"
 *  appears in all three and proves nothing; "barcode", "opening balance" and
 *  "bill number" each belong to exactly one.
 */
import { type ImportKind, normalizeHeader } from "@/lib/import";


/** The column names that identify a file as one kind and not another.
 *
 *  Listed here rather than derived from the schemas, and that distinction
 *  cost me a round of failing tests. A schema says what CAN BE MAPPED, which
 *  is deliberately generous: a sales register has a customer column, so the
 *  sales schema lists every word for one. Deriving identity from that made
 *  "party name" and "mobile" ambiguous between customers and sales, and a
 *  plain customer list stopped being recognisable at all.
 *
 *  What identifies a file is narrower and different in kind. A sales register
 *  is known by having a bill number and a date. A customer ledger is known by
 *  a balance column. A product list is known by a barcode or a stock count.
 *  Those are the words below.
 */
const SIGNALS: Record<ImportKind, string[]> = {
  products: [
    "barcode", "sku", "stock", "qty", "quantity", "mrp", "hsn", "hsn code",
    "cost price", "cost", "purchase price", "particulars", "item", "item name",
    "category", "gst rate", "tax",
  ],
  customers: [
    "opening balance", "closing balance", "outstanding", "due", "balance",
    "advance", "deposit", "prepaid", "credit", "pending", "whatsapp",
    // A name and a number with nothing else around them is a contact list.
    // A sales register carries these too, but it also carries a bill number
    // and a date, which outweigh them.
    "party name", "customer name", "mobile", "mobile number", "contact number",
  ],
  sales: [
    "bill no", "bill number", "invoice", "invoice no", "invoice number",
    "bill date", "invoice date", "sale date", "grand total", "voucher",
    "receipt no", "bill amount", "sale amount", "net",
  ],
};

const ALL_KINDS: ImportKind[] = ["products", "customers", "sales"];

/** Signal words for one kind that no other kind also claims. */
function distinctiveTerms(kind: ImportKind): Set<string> {
  const mine = new Set(SIGNALS[kind].map(normalizeHeader));
  for (const other of ALL_KINDS) {
    if (other === kind) continue;
    for (const term of SIGNALS[other]) mine.delete(normalizeHeader(term));
  }
  return mine;
}

export type Detection = {
  /** The kind the file looks like, or null when it is genuinely ambiguous. */
  kind: ImportKind | null;
  /** How many distinctive columns pointed at each kind. */
  scores: Record<ImportKind, string[]>;
};

/** What this file looks like, judged only by its column headings.
 *
 *  A clear winner or nothing. Two kinds tied means the headers do not settle
 *  it, and saying so is more use than picking one.
 */
export function detectKind(headers: string[]): Detection {
  const seen = headers.map(normalizeHeader).filter(Boolean);
  const scores = {} as Record<ImportKind, string[]>;
  for (const kind of ALL_KINDS) {
    const terms = distinctiveTerms(kind);
    scores[kind] = seen.filter((h) => terms.has(h));
  }

  const ranked = ALL_KINDS.slice().sort(
    (a, b) => scores[b].length - scores[a].length,
  );
  const best = ranked[0];
  const runnerUp = ranked[1];
  const decided =
    scores[best].length > 0 && scores[best].length > scores[runnerUp].length;

  return { kind: decided ? best : null, scores };
}

/** Whether the file contradicts the kind chosen on screen.
 *
 *  Only when the file points clearly the other way. A file with nothing
 *  distinctive in it - just a column of names - cannot contradict anything,
 *  and stopping on that would make the screen cry wolf.
 */
export function contradicts(chosen: ImportKind, detection: Detection): boolean {
  return detection.kind !== null && detection.kind !== chosen;
}

/** The value a row is identified by, for spotting the same thing twice.
 *
 *  A code first, because that is what a shop means by "the same product".
 *  Falling back to the name is deliberate: most small-shop spreadsheets carry
 *  no codes at all, and two identical names in one file are worth a look
 *  whether or not they turn out to be the same item.
 */
export function identityOf(
  row: Record<string, string>,
  kind: ImportKind,
): string {
  const pick = (...keys: string[]) => {
    for (const key of keys) {
      const value = (row[key] ?? "").trim();
      if (value) return value.toLowerCase();
    }
    return "";
  };
  if (kind === "products") return pick("barcode", "sku", "name");
  if (kind === "sales") {
    // The bill number, and nothing else. Two sales on the same day for the
    // same amount are ordinary trading, not a duplicated row.
    return pick("id");
  }
  return pick("phone", "name");
}

export type DuplicateGroup = {
  /** What they have in common - a code, a number, or a name. */
  value: string;
  /** Row numbers as the reader sees them in the spreadsheet, 1-based. */
  rows: number[];
};

/** Rows in this file that identify the same thing as another row.
 *
 *  Reported rather than removed. Two lines sharing a name can be a genuine
 *  mistake or two real products that happen to share one, and this cannot
 *  tell which - but the person who made the file can, in a second.
 */
export function findDuplicates(
  rows: Record<string, string>[],
  kind: ImportKind,
): DuplicateGroup[] {
  const byIdentity = new Map<string, number[]>();
  rows.forEach((row, index) => {
    const identity = identityOf(row, kind);
    if (!identity) return; // Nothing to match on; the row is its own thing.
    const list = byIdentity.get(identity);
    if (list) list.push(index + 1);
    else byIdentity.set(identity, [index + 1]);
  });

  return [...byIdentity.entries()]
    .filter(([, rowNumbers]) => rowNumbers.length > 1)
    .map(([value, rowNumbers]) => ({ value, rows: rowNumbers }))
    .sort((a, b) => b.rows.length - a.rows.length);
}

/** A short, plain sentence for the confirmation step.
 *
 *  Counted in things a shopkeeper recognises rather than in rows and fields,
 *  because "312 products" is checkable at a glance and "312 records across 9
 *  columns" is not.
 */
export function summarise(
  kind: ImportKind,
  rowCount: number,
  duplicates: DuplicateGroup[],
  alreadyHere: DuplicateGroup[],
): string {
  const noun =
    kind === "products" ? "product" : kind === "sales" ? "past sale" : "customer";
  const parts = [`${rowCount} ${noun}${rowCount === 1 ? "" : "s"}`];
  if (duplicates.length) parts.push(`${duplicates.length} repeated in the file`);
  if (alreadyHere.length) parts.push(`${alreadyHere.length} already in your shop`);
  return parts.join(" · ");
}
