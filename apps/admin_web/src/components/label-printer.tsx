"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Minus, Plus, Printer, Search, Wand2, X } from "lucide-react";

import { useServerRefresh } from "@/lib/use-server-refresh";

import { barcodeSvg, canEncode } from "@/lib/barcode";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

type StockItem = {
  id: string;
  name: string;
  sku: string;
  barcode: string;
  size: string;
  sell_price: string | number;
  stock_on_hand: number;
};

/**
 * Label stock, in millimetres.
 *
 * These are the three formats an Indian stationer actually sells: the 65-up
 * and 24-up A4 sticker sheets, and the 50x25 roll a thermal label printer
 * takes. Anything else and the labels land between the die-cuts.
 */
const FORMATS = [
  {
    key: "a4-65",
    label: "A4 sheet · 65 labels (38 × 21 mm)",
    width: 38,
    height: 21,
    columns: 5,
    moduleWidth: 0.26,
    barcodeHeight: 7,
    compact: true,
  },
  {
    key: "a4-24",
    label: "A4 sheet · 24 labels (64 × 34 mm)",
    width: 64,
    height: 34,
    columns: 3,
    moduleWidth: 0.42,
    barcodeHeight: 12,
    compact: false,
  },
  {
    key: "roll-50",
    label: "Label roll · 50 × 25 mm",
    width: 50,
    height: 25,
    columns: 3,
    moduleWidth: 0.34,
    barcodeHeight: 9,
    compact: false,
  },
] as const;

type FormatKey = (typeof FORMATS)[number]["key"];

/** What actually goes in the bars: a real barcode if the item has one, else the SKU. */
function codeFor(item: StockItem): string {
  return (item.barcode || "").trim() || (item.sku || "").trim();
}

function priceOf(item: StockItem): number {
  const n = typeof item.sell_price === "number" ? item.sell_price : parseFloat(String(item.sell_price ?? "0"));
  return Number.isFinite(n) ? n : 0;
}

export function LabelPrinter({ shopName }: { shopName: string }) {
  const [items, setItems] = useState<StockItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [formatKey, setFormatKey] = useState<FormatKey>("a4-65");
  const [showPrice, setShowPrice] = useState(true);
  const [showShopName, setShowShopName] = useState(false);
  /** item id -> how many stickers of it to print. */
  const [counts, setCounts] = useState<Record<string, number>>({});

  const format = FORMATS.find((f) => f.key === formatKey) ?? FORMATS[0];

  const refreshServerData = useServerRefresh();

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/inventory");
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || `Could not load items (${res.status})`);
      }
      const payload = await res.json();
      const rows: StockItem[] = (payload.items ?? payload ?? []).map(
        (raw: Record<string, unknown>) => ({
          id: String(raw.id),
          name: String(raw.name ?? ""),
          sku: String(raw.sku ?? ""),
          barcode: String(raw.barcode ?? ""),
          size: String(raw.size ?? ""),
          sell_price: (raw.sell_price as string | number) ?? 0,
          stock_on_hand: Number(raw.stock_on_hand ?? 0),
        }),
      );
      setItems(rows);
    } catch (err) {
      setError(errorMessage(err, "Something went wrong loading your items."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items.slice(0, 60);
    return items
      .filter(
        (i) =>
          i.name.toLowerCase().includes(q) ||
          i.sku.toLowerCase().includes(q) ||
          i.barcode.toLowerCase().includes(q),
      )
      .slice(0, 60);
  }, [items, query]);

  /** One entry per sticker, so 3 of an item become 3 labels. */
  const sheet = useMemo(() => {
    const out: StockItem[] = [];
    for (const item of items) {
      const count = counts[item.id] ?? 0;
      for (let i = 0; i < count; i += 1) out.push(item);
    }
    return out;
  }, [items, counts]);

  const setCount = (id: string, next: number) =>
    setCounts((prev) => {
      const copy = { ...prev };
      if (next <= 0) delete copy[id];
      else copy[id] = Math.min(next, 500);
      return copy;
    });

  /** Every product in the shop that cannot be printed at all.
   *
   *  Distinct from `unprintable`, which counts only what is selected. This is
   *  the number that decides whether the screen can do anything useful yet:
   *  a catalogue imported from a spreadsheet arrives with no codes, and the
   *  screen's only response was to say so once per product.
   */
  const withoutCode = useMemo(
    () => items.filter((item) => !codeFor(item)).length,
    [items],
  );

  const [generating, setGenerating] = useState(false);
  const [generated, setGenerated] = useState<number | null>(null);

  const generateSkus = async () => {
    setGenerating(true);
    setError(null);
    setGenerated(null);
    try {
      const res = await fetch("/api/inventory/generate-skus", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(body?.detail || body?.error || `Could not create codes (${res.status})`);
      }
      setGenerated(Number(body?.assigned_count ?? 0));
      // The codes are on the products now, so every other screen that shows a
      // SKU is out of date as well.
      await load();
      refreshServerData();
    } catch (err) {
      setError(errorMessage(err, "Could not create codes for those products."));
    } finally {
      setGenerating(false);
    }
  };

  const unprintable = useMemo(
    () => Object.keys(counts).filter((id) => {
      const item = items.find((i) => i.id === id);
      if (!item) return false;
      const code = codeFor(item);
      return !code || !canEncode(code);
    }),
    [counts, items],
  );

  return (
    <div className="space-y-6">
      {/* --- controls (hidden when printing) ------------------------------ */}
      <div className="space-y-6 print:hidden">
        {error && (
          <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
            {error}
          </div>
        )}

        <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 sm:p-6 shadow-sm space-y-4">
          <div>
            <label
              htmlFor="label-format"
              className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mb-1.5"
            >
              Label size
            </label>
            <select
              id="label-format"
              value={formatKey}
              onChange={(e) => setFormatKey(e.target.value as FormatKey)}
              className="w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-3 text-sm font-bold text-[var(--text-primary)]"
            >
              {FORMATS.map((f) => (
                <option key={f.key} value={f.key}>
                  {f.label}
                </option>
              ))}
            </select>
            <p className="mt-1.5 text-[11px] font-semibold text-[var(--text-secondary)]">
              Print at 100% scale with margins off, or the bars land between the
              die-cuts and nothing scans.
            </p>
          </div>

          <div className="flex flex-wrap gap-4">
            <label className="inline-flex items-center gap-2 text-xs font-bold text-[var(--text-secondary)]">
              <input
                type="checkbox"
                checked={showPrice}
                onChange={(e) => setShowPrice(e.target.checked)}
                className="w-4 h-4 accent-[var(--primary)]"
              />
              Show price
            </label>
            <label className="inline-flex items-center gap-2 text-xs font-bold text-[var(--text-secondary)]">
              <input
                type="checkbox"
                checked={showShopName}
                onChange={(e) => setShowShopName(e.target.checked)}
                className="w-4 h-4 accent-[var(--primary)]"
              />
              Show shop name
            </label>
          </div>
        </div>

        {/* --- picking what to print -------------------------------------- */}
        <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 sm:p-6 shadow-sm space-y-4">
          {/* A label needs something to encode. Saying "NEEDS A SKU" once per
              product, a few hundred times, states the problem and offers no
              way out of it - so the way out lives here. */}
          {withoutCode > 0 && (
            <div className="flex flex-col gap-3 rounded-[16px] border border-[var(--warning)]/30 bg-[var(--warning)]/10 p-4 sm:flex-row sm:items-center sm:justify-between">
              <div className="min-w-0">
                <p className="m-0 text-[13px] font-extrabold text-[var(--warning-strong)]">
                  {withoutCode} product{withoutCode === 1 ? "" : "s"} cannot be
                  printed yet
                </p>
                <p className="m-0 mt-1 max-w-[62ch] text-[12px] font-semibold leading-relaxed text-[var(--text-secondary)]">
                  A barcode has to encode something, and these have neither a
                  barcode nor a SKU. Give them one and they become printable
                  and scannable at the till.
                </p>
              </div>
              <button
                type="button"
                onClick={() => void generateSkus()}
                disabled={generating}
                className="focus-ring inline-flex shrink-0 cursor-pointer items-center justify-center gap-2 rounded-[12px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-4 py-2.5 text-[12px] font-extrabold text-[var(--primary-dark)] transition-colors duration-200 hover:bg-[var(--primary)]/20 disabled:cursor-not-allowed disabled:opacity-60"
              >
                <Wand2 className={`h-3.5 w-3.5 ${generating ? "motion-safe:animate-pulse" : ""}`} />
                {generating ? "Creating codes…" : "Create codes for all"}
              </button>
            </div>
          )}

          {generated !== null && (
            <p className="m-0 rounded-[16px] border border-[var(--success)]/30 bg-[var(--success)]/10 px-4 py-3 text-[12px] font-extrabold text-[var(--success-strong)]">
              {generated === 0
                ? "Every product already had a code."
                : `Gave ${generated} product${generated === 1 ? "" : "s"} a code. They can be printed now.`}
            </p>
          )}

          <div className="relative">
            <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--text-tertiary)]" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search by name, SKU or barcode…"
              className="w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] pl-11 pr-4 py-3 text-sm font-semibold text-[var(--text-primary)]"
            />
          </div>

          {loading ? (
            <div className="py-10 text-center text-xs font-bold text-[var(--text-tertiary)]">
              Loading items…
            </div>
          ) : visible.length === 0 ? (
            <div className="py-10 text-center text-xs font-bold text-[var(--text-tertiary)]">
              No items match that search.
            </div>
          ) : (
            <div className="space-y-2">
              {visible.map((item) => {
                const code = codeFor(item);
                const printable = Boolean(code) && canEncode(code);
                const count = counts[item.id] ?? 0;
                return (
                  <div
                    key={item.id}
                    className="flex items-center justify-between gap-3 rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] px-4 py-3 transition-colors duration-200 hover:border-[var(--border)]"
                  >
                    <div className="min-w-0">
                      <span className="block text-xs font-extrabold text-[var(--text-primary)] truncate">
                        {item.name}
                        {item.size && (
                          <span className="text-[var(--text-tertiary)]"> ({item.size})</span>
                        )}
                      </span>
                      <span className="block text-[10px] font-bold text-[var(--text-tertiary)] mt-0.5 font-mono">
                        {code || "no barcode or SKU"}
                      </span>
                    </div>

                    {printable ? (
                      <div className="flex items-center gap-1.5 shrink-0">
                        <button
                          type="button"
                          aria-label={`One fewer label for ${item.name}`}
                          onClick={() => setCount(item.id, count - 1)}
                          disabled={count === 0}
                          className="p-2 rounded-xl border border-[var(--border)] text-[var(--text-secondary)] hover:border-[var(--primary)] disabled:opacity-40"
                        >
                          <Minus className="w-3.5 h-3.5" />
                        </button>
                        <input
                          aria-label={`Labels for ${item.name}`}
                          type="number"
                          min="0"
                          value={count || ""}
                          placeholder="0"
                          onChange={(e) => setCount(item.id, Number(e.target.value) || 0)}
                          className="w-14 text-center rounded-xl border border-[var(--border)] bg-[var(--surface)] px-2 py-2 text-xs font-extrabold text-[var(--text-primary)]"
                        />
                        <button
                          type="button"
                          aria-label={`One more label for ${item.name}`}
                          onClick={() => setCount(item.id, count + 1)}
                          className="p-2 rounded-xl border border-[var(--border)] text-[var(--text-secondary)] hover:border-[var(--primary)]"
                        >
                          <Plus className="w-3.5 h-3.5" />
                        </button>
                        <button
                          type="button"
                          onClick={() =>
                            setCount(item.id, Math.max(1, Math.floor(item.stock_on_hand)))
                          }
                          className="ml-1 text-[10px] font-extrabold text-[var(--primary)] hover:underline whitespace-nowrap"
                        >
                          one each
                        </button>
                      </div>
                    ) : (
                      <span className="shrink-0 inline-flex items-center gap-1.5 text-[10px] font-extrabold text-[var(--warning-strong)]">
                        <AlertTriangle className="w-3.5 h-3.5" />
                        NEEDS A SKU
                      </span>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {unprintable.length > 0 && (
          <div className="rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-5 py-4 text-xs font-bold text-[var(--warning-strong)]">
            {unprintable.length} selected item(s) have no barcode or SKU that can
            be encoded, and will be skipped. A barcode can only carry letters,
            numbers and basic punctuation — not Hindi or Gujarati text.
          </div>
        )}

        <div className="flex flex-wrap items-center justify-between gap-3">
          <span className="text-xs font-extrabold text-[var(--text-secondary)]">
            {sheet.length} label{sheet.length === 1 ? "" : "s"} ready
          </span>
          <div className="flex items-center gap-2">
            {sheet.length > 0 && (
              <button
                type="button"
                onClick={() => setCounts({})}
                className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--border)] px-4 py-2.5 text-xs font-extrabold text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
              >
                <X className="w-3.5 h-3.5" />
                Clear
              </button>
            )}
            <button
              type="button"
              onClick={() => window.print()}
              disabled={sheet.length === 0}
              className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-6 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] disabled:opacity-50 border border-[var(--primary)]/25"
            >
              <Printer className="w-3.5 h-3.5" />
              Print labels
            </button>
          </div>
        </div>
      </div>

      {/* --- the sheet itself --------------------------------------------
          Also shown on screen as a preview. Sizes are in millimetres so what
          prints is the physical size the label stock expects, independent of
          screen resolution. */}
      {sheet.length > 0 && (
        <div className="print:hidden">
          <h3 className="text-xs font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mb-3">
            Preview
          </h3>
        </div>
      )}

      <div
        id="barcode-label-print-area"
        style={{
          display: "grid",
          gridTemplateColumns: `repeat(${format.columns}, ${format.width}mm)`,
          gap: "0mm",
        }}
      >
        {sheet.map((item, index) => {
          const code = codeFor(item);
          if (!code || !canEncode(code)) return null;
          return (
            <div
              key={`${item.id}-${index}`}
              style={{
                width: `${format.width}mm`,
                height: `${format.height}mm`,
                padding: "1mm",
                boxSizing: "border-box",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                overflow: "hidden",
                background: "#fff",
                color: "#000",
                textAlign: "center",
              }}
            >
              {showShopName && !format.compact && (
                <span style={{ fontSize: "1.6mm", fontWeight: 700, lineHeight: 1.1 }}>
                  {shopName}
                </span>
              )}
              <span
                style={{
                  fontSize: format.compact ? "1.8mm" : "2.4mm",
                  fontWeight: 700,
                  lineHeight: 1.15,
                  maxWidth: "100%",
                  overflow: "hidden",
                  whiteSpace: "nowrap",
                  textOverflow: "ellipsis",
                }}
              >
                {item.name}
                {item.size ? ` · ${item.size}` : ""}
              </span>

              <div
                style={{ marginTop: "0.5mm", lineHeight: 0 }}
                // The SVG is built locally from the item's own code; there is
                // no external input and no script in it.
                dangerouslySetInnerHTML={{
                  __html: barcodeSvg(code, {
                    moduleWidth: format.moduleWidth,
                    height: format.barcodeHeight,
                  }).replace(
                    "<svg",
                    `<svg style="max-width:${format.width - 3}mm;height:${format.barcodeHeight}mm"`,
                  ),
                }}
              />

              <span
                style={{
                  fontSize: format.compact ? "1.5mm" : "1.9mm",
                  fontFamily: "monospace",
                  letterSpacing: "0.02em",
                  lineHeight: 1.2,
                }}
              >
                {code}
              </span>

              {showPrice && (
                <span
                  style={{
                    fontSize: format.compact ? "2.2mm" : "3mm",
                    fontWeight: 800,
                    lineHeight: 1.1,
                  }}
                >
                  ₹{priceOf(item).toFixed(2)}
                </span>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
