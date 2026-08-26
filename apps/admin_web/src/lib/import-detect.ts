/** Working out what a spreadsheet actually holds, before it is written.
 *
 *  The import screen asks which kind of data a file is and then trusts the
 *  answer. Both kinds require exactly one column - a name - so a customer
 *  list dropped in with "Products" still selected imports perfectly: every
 *  customer becomes a product with a name, no price and no stock. Nothing
 *  fails, nothing warns, and the catalogue fills up with people.
 *
 *  So the file gets a vote. The headers are scored against both schemas, and
 *  when the file disagrees with the choice on screen, that is worth stopping
 *  for - it is far likelier that somebody forgot to change the selector than
 *  that they meant to import three hundred customers as stock.
 *
 *  Scoring is by distinctive columns rather than by counting matches. "Name"
 *  appears in both and proves nothing; "barcode" and "opening balance" each
 *  belong to exactly one.
 */
import { IMPORT_SCHEMAS, type ImportKind, normalizeHeader } from "@/lib/import";

function termsFor(field: {
  key: string;
  label: string;
  synonyms?: string[];
}): string[] {
  return [field.key, field.label, ...(field.synonyms ?? [])].map(normalizeHeader);
}

/** Columns that belong to one kind and never the other.
 *
 *  Derived from the schemas rather than listed by hand, so a field added
 *  there is taken into account here without anybody remembering to.
 */
function distinctiveTerms(kind: ImportKind): Set<string> {
  const other: ImportKind = kind === "products" ? "customers" : "products";
  const mine = new Set(IMPORT_SCHEMAS[kind].flatMap(termsFor));
  for (const term of IMPORT_SCHEMAS[other].flatMap(termsFor)) mine.delete(term);
  return mine;
}

export type Detection = {
  /** The kind the file looks like, or null when it is genuinely ambiguous. */
  kind: ImportKind | null;
  /** Distinctive headers that pointed each way, for showing the reader. */
  productSignals: string[];
  customerSignals: string[];
};

/** What this file looks like, judged only by its column headings. */
export function detectKind(headers: string[]): Detection {
  const seen = headers.map(normalizeHeader).filter(Boolean);
  const productTerms = distinctiveTerms("products");
  const customerTerms = distinctiveTerms("customers");

  const productSignals = seen.filter((h) => productTerms.has(h));
  const customerSignals = seen.filter((h) => customerTerms.has(h));

  let kind: ImportKind | null = null;
  if (productSignals.length > customerSignals.length) kind = "products";
  else if (customerSignals.length > productSignals.length) kind = "customers";

  return { kind, productSignals, customerSignals };
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
  return kind === "products" ? pick("barcode", "sku", "name") : pick("phone", "name");
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

/** Rows whose identity already exists in the shop.
 *
 *  Separate from findDuplicates because the two need different words: one is
 *  "your file repeats itself", the other is "this is already in your shop",
 *  and only the second risks a second copy of something real.
 */
export function findExisting(
  rows: Record<string, string>[],
  kind: ImportKind,
  existing: Iterable<string>,
): DuplicateGroup[] {
  const known = new Set(
    [...existing].map((value) => (value ?? "").trim().toLowerCase()).filter(Boolean),
  );
  if (known.size === 0) return [];

  const hits = new Map<string, number[]>();
  rows.forEach((row, index) => {
    const identity = identityOf(row, kind);
    if (!identity || !known.has(identity)) return;
    const list = hits.get(identity);
    if (list) list.push(index + 1);
    else hits.set(identity, [index + 1]);
  });

  return [...hits.entries()].map(([value, rowNumbers]) => ({
    value,
    rows: rowNumbers,
  }));
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
  const noun = kind === "products" ? "product" : "customer";
  const parts = [`${rowCount} ${noun}${rowCount === 1 ? "" : "s"}`];
  if (duplicates.length) parts.push(`${duplicates.length} repeated in the file`);
  if (alreadyHere.length) parts.push(`${alreadyHere.length} already in your shop`);
  return parts.join(" · ");
}
