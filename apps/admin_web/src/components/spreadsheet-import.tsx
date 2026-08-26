"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, Download, FileUp, Loader2, Upload } from "lucide-react";

import { readXlsx, looksLikeXlsx, type XlsxSheet } from "@/lib/xlsx";
import {
  applyMapping,
  autoMap,
  IMPORT_SCHEMAS,
  parseCsv,
  toCustomerPayload,
  toInventoryPayload,
  type FieldMapping,
  type ImportKind,
  type ParsedTable,
} from "@/lib/import";
import { useServerRefresh } from "@/lib/use-server-refresh";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

/** A rejected row, described so it can be found in the original spreadsheet. */
type RowError = {
  /** 1-based row number as it appears in Excel, header included. */
  row: number;
  name: string;
  sku: string;
  message: string;
};

type ImportResult = {
  created: number;
  updated: number;
  skipped: number;
  errors: RowError[];
  /** Total rejected, which can exceed errors.length — that list is capped. */
  errorCount?: number;
};

/**
 * The rejected rows as a spreadsheet the shop can work through.
 *
 * Fifty rows in a scrolling panel is fine to glance at and hopeless to fix
 * from — the person correcting them is in Excel, and needs the list beside the
 * file rather than in a browser tab.
 *
 * utf-8-sig, like the data export: without the byte-order mark Excel on
 * Windows renders Hindi and Gujarati product names as mojibake.
 */
function downloadErrorReport(errors: RowError[]) {
  const escape = (value: string) => `"${String(value ?? "").replace(/"/g, '""')}"`;
  const csv = [
    "row,item,sku,problem",
    ...errors.map((e) =>
      [e.row, escape(e.name), escape(e.sku), escape(e.message)].join(","),
    ),
  ].join("\r\n");

  const blob = new Blob([new Uint8Array([0xef, 0xbb, 0xbf]), csv], {
    type: "text/csv;charset=utf-8",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `import-errors-${new Date().toISOString().slice(0, 10)}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

const KINDS: { key: ImportKind; label: string; hint: string }[] = [
  { key: "products", label: "Products", hint: "Your stock list — names, prices, quantities" },
  { key: "customers", label: "Customers", hint: "Names, numbers and any opening balances" },
];

export function SpreadsheetImport() {
  const refreshServerData = useServerRefresh();
  const [kind, setKind] = useState<ImportKind>("products");
  const [fileName, setFileName] = useState<string | null>(null);
  const [table, setTable] = useState<ParsedTable | null>(null);
  const [sheets, setSheets] = useState<XlsxSheet[]>([]);
  const [activeSheet, setActiveSheet] = useState<string | null>(null);
  const [mapping, setMapping] = useState<FieldMapping>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<ImportResult | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const fields = IMPORT_SCHEMAS[kind];

  const reset = () => {
    setTable(null);
    setSheets([]);
    setActiveSheet(null);
    setMapping({});
    setFileName(null);
    setResult(null);
    setError(null);
    if (inputRef.current) inputRef.current.value = "";
  };

  const applySheet = useCallback(
    (sheet: XlsxSheet, forKind: ImportKind) => {
      // A sheet's first row is its header, matching the CSV path.
      const rows = sheet.rows.filter((r) => r.some((cell) => cell.trim() !== ""));
      if (rows.length === 0) throw new Error(`Sheet "${sheet.name}" is empty.`);
      const parsed = { headers: rows[0].map((h) => h.trim()), rows: rows.slice(1) };
      setTable(parsed);
      setMapping(autoMap(parsed.headers, forKind));
      setActiveSheet(sheet.name);
    },
    []
  );

  const readFile = useCallback(
    async (file: File, forKind: ImportKind) => {
      setError(null);
      setResult(null);
      try {
        if (/\.xlsx$/i.test(file.name)) {
          const bytes = new Uint8Array(await file.arrayBuffer());
          if (!looksLikeXlsx(bytes)) {
            throw new Error(
              "That looks like an old .xls file. Open it in Excel and save as .xlsx or .csv."
            );
          }
          const parsedSheets = (await readXlsx(bytes)).filter((s) => s.rows.length > 0);
          if (parsedSheets.length === 0) throw new Error("That workbook has no readable rows.");
          setSheets(parsedSheets);
          applySheet(parsedSheets[0], forKind);
        } else {
          const text = await file.text();
          const parsed = parseCsv(text);
          if (parsed.headers.length === 0) {
            throw new Error("That file has no readable rows.");
          }
          setSheets([]);
          setActiveSheet(null);
          setTable(parsed);
          setMapping(autoMap(parsed.headers, forKind));
        }
        setFileName(file.name);
      } catch (err) {
        setTable(null);
        setSheets([]);
        setError(errorMessage(err, "Could not read that file."));
      }
    },
    [applySheet]
  );

  const onPick = async (file: File | undefined) => {
    if (!file) return;
    if (!/\.(csv|xlsx)$/i.test(file.name)) {
      setError("Choose a .xlsx or .csv file.");
      return;
    }
    await readFile(file, kind);
  };

  const changeKind = async (next: ImportKind) => {
    setKind(next);
    // Re-map against the new schema rather than carrying over columns that
    // meant something else.
    if (table) setMapping(autoMap(table.headers, next));
  };

  const preview = useMemo(() => {
    if (!table) return null;
    return applyMapping(table, kind, mapping);
  }, [table, kind, mapping]);

  const missingRequired = fields
    .filter((f) => f.required && !(f.key in mapping))
    .map((f) => f.label);

  const runImport = async () => {
    if (!preview || preview.rows.length === 0) return;
    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const shape = kind === "products" ? toInventoryPayload : toCustomerPayload;
      const res = await fetch("/api/import", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind, rows: preview.rows.map(shape) }),
      });
      const body = await res.json();
      if (!res.ok) {
        throw new Error(typeof body?.error === "string" ? body.error : `Import failed (${res.status})`);
      }
      setResult(body);
      // The rows went straight into stock and customers.
      refreshServerData();
    } catch (err) {
      setError(errorMessage(err, "Could not import that file."));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-6">
      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {result && (
        <div className="rounded-[28px] border border-[var(--success)]/30 bg-[var(--success)]/10 p-6">
          <div className="flex items-start gap-3">
            <CheckCircle2 className="w-6 h-6 shrink-0 text-[var(--success-strong)]" />
            <div>
              <p className="text-sm font-black text-text-primary">Import finished</p>
              <p className="mt-1 text-xs font-semibold text-text-secondary">
                {result.created} added &middot; {result.updated} updated &middot;{" "}
                {result.skipped} skipped
              </p>
              {result.updated > 0 && (
                <p className="mt-1.5 text-[11px] font-semibold text-text-tertiary">
                  Rows matching an existing SKU or name were updated rather than
                  duplicated, so re-importing the same sheet is safe.
                </p>
              )}

              {/* Until now the rejected rows were counted and then discarded.
                  A count is unusable: it tells a shop that 340 of 2,000
                  products did not import and nothing about which ones. */}
              {result.errors?.length > 0 && (
                <div className="mt-4 rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 p-4">
                  <p className="text-xs font-black text-[var(--warning-strong)]">
                    {result.errorCount ?? result.errors.length} row
                    {(result.errorCount ?? result.errors.length) === 1 ? "" : "s"} could not be imported
                    {result.errorCount && result.errorCount > result.errors.length
                      ? ` — showing the first ${result.errors.length}`
                      : ""}
                  </p>
                  <p className="mt-1 text-[11px] font-semibold text-text-secondary">
                    Row numbers match your spreadsheet. Fix these rows and import
                    the same file again — rows that already landed will be
                    updated, not duplicated.
                  </p>
                  <div className="mt-3 max-h-56 overflow-y-auto">
                    <table className="w-full text-left">
                      <thead>
                        <tr className="text-[10px] font-extrabold uppercase tracking-wider text-text-tertiary">
                          <th className="pb-1.5 pr-3">Row</th>
                          <th className="pb-1.5 pr-3">Item</th>
                          <th className="pb-1.5">Problem</th>
                        </tr>
                      </thead>
                      <tbody>
                        {result.errors.map((e, i) => (
                          <tr key={`${e.row}-${i}`} className="align-top">
                            <td className="py-1 pr-3 font-mono text-[11px] font-bold text-text-primary tabular-nums">
                              {e.row}
                            </td>
                            <td className="py-1 pr-3 text-[11px] font-semibold text-text-primary">
                              {e.name || e.sku || <span className="text-text-tertiary">(blank)</span>}
                            </td>
                            <td className="py-1 text-[11px] font-medium text-text-secondary">
                              {e.message}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  <button
                    type="button"
                    onClick={() => downloadErrorReport(result.errors)}
                    className="mt-3 inline-flex items-center gap-1.5 rounded-xl border border-[var(--border)] px-3.5 py-2 text-[11px] font-extrabold text-text-secondary hover:text-text-primary"
                  >
                    <Download className="w-3.5 h-3.5" />
                    Download as CSV
                  </button>
                </div>
              )}
              <button
                type="button"
                onClick={reset}
                className="mt-3 rounded-xl border border-border-soft bg-surface px-4 py-2 text-xs font-extrabold text-text-primary"
              >
                Import another file
              </button>
            </div>
          </div>
        </div>
      )}

      {/* What to import */}
      <div>
        <p className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
          What are you importing?
        </p>
        <div className="mt-2 flex flex-wrap gap-2">
          {KINDS.map((k) => (
            <button
              key={k.key}
              type="button"
              onClick={() => void changeKind(k.key)}
              className={`rounded-2xl border px-4 py-2.5 text-xs font-extrabold transition-colors ${
                kind === k.key
                  ? "border-[var(--primary)] bg-[var(--primary)]/10 text-[var(--primary-hover)]"
                  : "border-border-soft bg-surface text-text-secondary hover:text-text-primary"
              }`}
            >
              {k.label}
            </button>
          ))}
        </div>
        <p className="mt-2 text-xs font-semibold text-text-secondary">
          {KINDS.find((k) => k.key === kind)?.hint}
        </p>
      </div>

      {/* File */}
      <div className="rounded-[28px] border border-dashed border-border bg-surface p-8 text-center">
        <FileUp className="w-8 h-8 mx-auto text-text-tertiary" />
        <p className="mt-3 text-sm font-bold text-text-primary">
          {fileName ?? "Choose an Excel or CSV file"}
        </p>
        <p className="mt-1 text-xs font-semibold text-text-secondary">
          Any column order works — we match your headings automatically and show
          you the result before anything is saved.
        </p>
        <input
          ref={inputRef}
          type="file"
          accept=".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          onChange={(e) => void onPick(e.target.files?.[0])}
          className="hidden"
        />
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="mt-4 inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-5 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] border border-[var(--primary)]/25"
        >
          <Upload className="w-3.5 h-3.5" />
          Choose file
        </button>
        <p className="mt-3 text-[11px] font-semibold text-text-tertiary">
          Excel (.xlsx) and CSV both work.
        </p>
      </div>

      {/* Sheet picker: a workbook often carries products and customers on
          separate sheets, so let the shopkeeper choose which one to read. */}
      {sheets.length > 1 && (
        <div>
          <p className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
            Which sheet?
          </p>
          <div className="mt-2 flex flex-wrap gap-2">
            {sheets.map((sheet) => (
              <button
                key={sheet.name}
                type="button"
                onClick={() => {
                  try {
                    applySheet(sheet, kind);
                    setError(null);
                  } catch (err) {
                    setError(errorMessage(err, "Could not read that sheet."));
                  }
                }}
                className={`rounded-2xl border px-4 py-2 text-xs font-extrabold transition-colors ${
                  activeSheet === sheet.name
                    ? "border-[var(--primary)] bg-[var(--primary)]/10 text-[var(--primary-hover)]"
                    : "border-border-soft bg-surface text-text-secondary hover:text-text-primary"
                }`}
              >
                {sheet.name}
                <span className="ml-1.5 font-semibold text-text-tertiary">
                  {Math.max(0, sheet.rows.length - 1)}
                </span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Mapping */}
      {table && (
        <div className="rounded-[28px] border border-border-soft bg-surface overflow-hidden">
          <div className="px-6 py-5 border-b border-border-soft">
            <h2 className="text-sm font-black text-text-primary uppercase tracking-wide">
              Check the columns
            </h2>
            <p className="mt-1 text-xs font-semibold text-text-secondary">
              We guessed these from your headings. Change anything that looks wrong
              — a mis-matched column would price every product incorrectly.
            </p>
          </div>

          <div className="p-6 grid grid-cols-1 sm:grid-cols-2 gap-4">
            {fields.map((field) => (
              <label key={field.key} className="block">
                <span className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
                  {field.label}
                  {field.required && <span className="text-[var(--error-strong)]"> *</span>}
                </span>
                <select
                  value={mapping[field.key] ?? -1}
                  onChange={(e) => {
                    const column = Number(e.target.value);
                    setMapping((prev) => {
                      const next = { ...prev };
                      if (column < 0) delete next[field.key];
                      else next[field.key] = column;
                      return next;
                    });
                  }}
                  className="mt-1.5 w-full rounded-xl border border-border-soft bg-bg-base px-3 py-2.5 text-sm font-bold text-text-primary"
                >
                  <option value={-1}>— not in my file —</option>
                  {table.headers.map((header, index) => (
                    <option key={index} value={index}>
                      {header || `Column ${index + 1}`}
                    </option>
                  ))}
                </select>
              </label>
            ))}
          </div>

          {missingRequired.length > 0 && (
            <div className="mx-6 mb-6 rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-4 py-3 text-xs font-semibold text-text-secondary">
              <AlertTriangle className="inline w-3.5 h-3.5 mr-1.5 text-[var(--warning-strong)]" />
              Pick a column for: {missingRequired.join(", ")}
            </div>
          )}

          {/* Preview */}
          {preview && preview.rows.length > 0 && (
            <div className="border-t border-border-soft">
              <p className="px-6 pt-5 text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
                First few rows, as they will be saved
              </p>
              <div className="overflow-x-auto px-6 pb-5">
                <table className="mt-2 min-w-full border-collapse">
                  <thead>
                    <tr className="border-b border-border-soft text-left text-[11px] uppercase tracking-wider text-text-tertiary">
                      {fields
                        .filter((f) => f.key in mapping)
                        .map((f) => (
                          <th key={f.key} className="py-2 pr-6 font-extrabold">
                            {f.label}
                          </th>
                        ))}
                    </tr>
                  </thead>
                  <tbody>
                    {preview.rows.slice(0, 5).map((row, index) => (
                      <tr key={index} className="border-b border-border-soft/60 last:border-0">
                        {fields
                          .filter((f) => f.key in mapping)
                          .map((f) => (
                            <td
                              key={f.key}
                              className="py-2.5 pr-6 text-sm font-semibold text-text-primary whitespace-nowrap"
                            >
                              {row[f.key] || "—"}
                            </td>
                          ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          <div className="px-6 py-5 border-t border-border-soft flex flex-wrap items-center justify-between gap-3">
            <p className="text-xs font-semibold text-text-secondary">
              {preview?.rows.length ?? 0} row{preview?.rows.length === 1 ? "" : "s"} ready
              {preview && preview.skipped > 0 && (
                <span className="text-text-tertiary">
                  {" "}
                  &middot; {preview.skipped} skipped (no{" "}
                  {fields.find((f) => f.required)?.label.toLowerCase()})
                </span>
              )}
            </p>
            <button
              type="button"
              onClick={() => void runImport()}
              disabled={busy || missingRequired.length > 0 || (preview?.rows.length ?? 0) === 0}
              className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-5 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] disabled:opacity-50 border border-[var(--primary)]/25"
            >
              {busy && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
              {busy ? "Importing…" : `Import ${preview?.rows.length ?? 0} rows`}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
