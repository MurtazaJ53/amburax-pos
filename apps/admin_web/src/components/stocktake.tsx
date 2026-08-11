"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ClipboardCheck, Play, Search, TriangleAlert, X } from "lucide-react";

import { resolveScan, searchItems } from "@/lib/stock-search";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

type Line = {
  id: string;
  item_id: string;
  name: string;
  expected: string;
  counted: string;
  variance: string;
  unit_cost: string | null;
  variance_value: string | null;
  counted_at: string;
};

type Stocktake = {
  id: string;
  reference: string;
  status: "open" | "applied" | "cancelled";
  note: string;
  started_at: string;
  applied_at: string | null;
  counted_lines: number;
  missing_count: number;
  extra_count: number;
  matched_count: number;
  /** Null when any varied item has no recorded cost — a partial total would understate the loss. */
  variance_value: string | null;
  lines: Line[];
};

type StockItem = {
  id: string;
  name: string;
  sku: string;
  barcode: string;
  stock_on_hand: number;
};

const num = (v: string | number | null | undefined): number => {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? "0"));
  return Number.isFinite(n) ? n : 0;
};

/** Quantities are sent as fixed-3 strings; parsing drops "10.000" to "10". */
const qty = (v: string | number) => String(num(v));

const money = (v: number, currency = "INR") => {
  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency,
      maximumFractionDigits: 2,
    }).format(v);
  } catch {
    return `₹${v.toFixed(2)}`;
  }
};

/**
 * Counting the shelves.
 *
 * Unlike every other screen here, this one is used standing at a shelf holding
 * a phone in one hand. So: one item in focus at a time, a search field that
 * keeps focus so a USB or camera scanner can fire repeatedly without a tap,
 * and a running list of what has been counted so the counter can see progress
 * without leaving the screen.
 *
 * The expected quantity is deliberately NOT shown before entry. Showing it
 * invites the counter to confirm the book figure rather than count the shelf,
 * which produces a stocktake that always agrees and never finds anything.
 */
export function StocktakeScreen({
  canApply,
  currencyCode = "INR",
}: {
  canApply: boolean;
  currencyCode?: string;
}) {
  const [current, setCurrent] = useState<Stocktake | null>(null);
  const [history, setHistory] = useState<Stocktake[]>([]);
  const [items, setItems] = useState<StockItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<StockItem | null>(null);
  const [counted, setCounted] = useState("");
  const [revealExpected, setRevealExpected] = useState(false);

  const searchRef = useRef<HTMLInputElement | null>(null);
  const countRef = useRef<HTMLInputElement | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [takesRes, itemsRes] = await Promise.all([
        fetch("/api/stocktakes"),
        fetch("/api/inventory"),
      ]);
      if (!takesRes.ok) {
        const body = await takesRes.json().catch(() => ({}));
        throw new Error(body.error || "Could not load stocktakes.");
      }
      const takes = await takesRes.json();
      const all: Stocktake[] = takes.stocktakes ?? [];
      setCurrent(all.find((t) => t.status === "open") ?? null);
      setHistory(all.filter((t) => t.status !== "open"));

      if (itemsRes.ok) {
        const payload = await itemsRes.json();
        setItems(
          (payload.items ?? payload ?? []).map((r: Record<string, unknown>) => ({
            id: String(r.id),
            name: String(r.name ?? ""),
            sku: String(r.sku ?? ""),
            barcode: String(r.barcode ?? ""),
            stock_on_hand: Number(r.stock_on_hand ?? 0),
          })),
        );
      }
    } catch (err) {
      setError(errorMessage(err, "Could not load stocktakes."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const countedIds = useMemo(
    () => new Set((current?.lines ?? []).map((l) => l.item_id)),
    [current],
  );

  const matches = useMemo(() => searchItems(items, query), [items, query]);

  /** A scanner types the whole barcode then Enter; see resolveScan for the rule. */
  const onSearchKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== "Enter") return;
    e.preventDefault();
    const pick = resolveScan(items, query);
    if (pick) choose(pick);
  };

  const choose = (item: StockItem) => {
    setSelected(item);
    setQuery("");
    setCounted("");
    setRevealExpected(false);
    setTimeout(() => countRef.current?.focus(), 0);
  };

  const post = async (path: string, body?: unknown) => {
    const res = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body ?? {}),
    });
    const payload = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(payload.error || "That did not work.");
    return payload;
  };

  const start = async () => {
    setBusy(true);
    setError(null);
    try {
      await post("/api/stocktakes");
      await load();
    } catch (err) {
      setError(errorMessage(err, "Could not start a stocktake."));
    } finally {
      setBusy(false);
    }
  };

  const record = async () => {
    if (!current || !selected) return;
    if (counted.trim() === "") {
      setError("Enter how many are on the shelf. Zero is a valid answer.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await post(`/api/stocktakes/${current.id}/count`, {
        item_id: selected.id,
        counted_quantity: counted.trim(),
      });
      setSelected(null);
      setCounted("");
      await load();
      // Straight back to search so the next scan needs no tap.
      setTimeout(() => searchRef.current?.focus(), 0);
    } catch (err) {
      setError(errorMessage(err, "Could not record that count."));
    } finally {
      setBusy(false);
    }
  };

  const apply = async () => {
    if (!current) return;
    setBusy(true);
    setError(null);
    try {
      await post(`/api/stocktakes/${current.id}/apply`);
      await load();
    } catch (err) {
      setError(errorMessage(err, "Could not apply this stocktake."));
    } finally {
      setBusy(false);
    }
  };

  const cancel = async () => {
    if (!current) return;
    setBusy(true);
    setError(null);
    try {
      await post(`/api/stocktakes/${current.id}/cancel`);
      await load();
    } catch (err) {
      setError(errorMessage(err, "Could not cancel this stocktake."));
    } finally {
      setBusy(false);
    }
  };

  if (loading) {
    return (
      <p className="py-14 text-center text-xs font-bold text-[var(--text-tertiary)]">
        Loading…
      </p>
    );
  }

  return (
    <div className="space-y-5">
      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-3 text-xs font-bold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {!current ? (
        <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-6">
          <h3 className="text-base font-extrabold text-[var(--text-primary)]">
            Count the shelves
          </h3>
          <p className="mt-1.5 max-w-prose text-xs font-semibold text-[var(--text-secondary)]">
            Walk the shop, scan or search each item, and enter what is actually
            there. Nothing changes until you apply the count — and applying
            posts the difference, so anything sold while you count is not
            undone.
          </p>
          <button
            type="button"
            onClick={() => void start()}
            disabled={busy}
            className="mt-4 inline-flex items-center gap-2 rounded-2xl bg-[var(--primary)] px-5 py-3 text-xs font-extrabold text-white hover:bg-[var(--primary-hover)] disabled:opacity-50"
          >
            <Play className="w-4 h-4" />
            Start a stocktake
          </button>
        </div>
      ) : (
        <>
          {/* --- counting ------------------------------------------------- */}
          <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <span className="font-mono text-xs font-extrabold text-[var(--text-primary)]">
                  {current.reference}
                </span>
                <span className="ml-2 text-[11px] font-bold text-[var(--text-tertiary)]">
                  {current.counted_lines} counted
                </span>
              </div>
              <button
                type="button"
                onClick={() => void cancel()}
                disabled={busy}
                className="text-[11px] font-extrabold text-[var(--text-tertiary)] hover:underline"
              >
                Cancel count
              </button>
            </div>

            {!selected ? (
              <div className="relative mt-4">
                <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--text-tertiary)]" />
                <input
                  ref={searchRef}
                  autoFocus
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  onKeyDown={onSearchKey}
                  placeholder="Scan a barcode, or search by name or SKU…"
                  className="w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] pl-11 pr-4 py-3.5 text-sm font-semibold text-[var(--text-primary)]"
                />
                {matches.length > 0 && (
                  <div className="mt-2 overflow-hidden rounded-2xl border border-[var(--border-soft)]">
                    {matches.map((m) => (
                      <button
                        key={m.id}
                        type="button"
                        onClick={() => choose(m)}
                        className="flex w-full items-center justify-between gap-3 border-b border-[var(--border-soft)] bg-[var(--surface)] px-4 py-3 text-left last:border-0 hover:bg-[var(--bg-base)]"
                      >
                        <span className="min-w-0">
                          <span className="block truncate text-xs font-extrabold text-[var(--text-primary)]">
                            {m.name}
                          </span>
                          {m.sku && (
                            <span className="block font-mono text-[10px] text-[var(--text-tertiary)]">
                              {m.sku}
                            </span>
                          )}
                        </span>
                        {countedIds.has(m.id) && (
                          <span className="shrink-0 rounded-full bg-[var(--success)]/10 px-2 py-0.5 text-[10px] font-extrabold text-[var(--success-strong)]">
                            counted
                          </span>
                        )}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            ) : (
              <div className="mt-4 rounded-2xl border border-[var(--primary)]/30 bg-[var(--primary)]/5 p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="text-sm font-extrabold text-[var(--text-primary)]">
                      {selected.name}
                    </p>
                    {selected.sku && (
                      <p className="font-mono text-[10px] text-[var(--text-tertiary)]">
                        {selected.sku}
                      </p>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => setSelected(null)}
                    aria-label="Choose a different item"
                    className="p-1.5 text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
                  >
                    <X className="w-4 h-4" />
                  </button>
                </div>

                <label
                  htmlFor="counted-qty"
                  className="mt-3 block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]"
                >
                  How many are on the shelf?
                </label>
                <input
                  id="counted-qty"
                  ref={countRef}
                  type="number"
                  min="0"
                  step="any"
                  inputMode="decimal"
                  value={counted}
                  onChange={(e) => setCounted(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      void record();
                    }
                  }}
                  placeholder="0"
                  className="mt-1.5 w-full rounded-2xl border border-[var(--border)] bg-[var(--surface)] px-4 py-4 text-center text-2xl font-black text-[var(--text-primary)]"
                />

                {/* Hidden by default on purpose: showing the book figure
                    invites confirming it instead of counting the shelf, and a
                    stocktake that always agrees never finds anything. */}
                {revealExpected ? (
                  <p className="mt-2 text-center text-[11px] font-bold text-[var(--text-secondary)]">
                    The books say {qty(selected.stock_on_hand)}
                  </p>
                ) : (
                  <button
                    type="button"
                    onClick={() => setRevealExpected(true)}
                    className="mt-2 block w-full text-center text-[11px] font-semibold text-[var(--text-tertiary)] hover:underline"
                  >
                    Show what the books say
                  </button>
                )}

                <button
                  type="button"
                  onClick={() => void record()}
                  disabled={busy}
                  className="mt-3 w-full rounded-2xl bg-[var(--primary)] px-5 py-3 text-xs font-extrabold text-white hover:bg-[var(--primary-hover)] disabled:opacity-50"
                >
                  {busy ? "Saving…" : "Record count"}
                </button>
              </div>
            )}
          </div>

          {/* --- what has been counted ------------------------------------ */}
          {current.lines.length > 0 && (
            <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
              <div className="flex flex-wrap items-center gap-3">
                <Tally label="Missing" value={current.missing_count} tone="bad" />
                <Tally label="Extra" value={current.extra_count} tone="warn" />
                <Tally label="Matched" value={current.matched_count} tone="good" />
              </div>

              <div className="mt-4 max-h-72 overflow-y-auto">
                <table className="w-full text-left">
                  <thead>
                    <tr className="text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
                      <th className="pb-1.5 pr-3">Item</th>
                      <th className="pb-1.5 pr-3 text-right">Books</th>
                      <th className="pb-1.5 pr-3 text-right">Counted</th>
                      <th className="pb-1.5 text-right">Difference</th>
                    </tr>
                  </thead>
                  <tbody>
                    {current.lines.map((line) => {
                      const v = num(line.variance);
                      return (
                        <tr key={line.id} className="border-t border-[var(--border-soft)]">
                          <td className="py-1.5 pr-3 text-xs font-bold text-[var(--text-primary)]">
                            {line.name}
                          </td>
                          <td className="py-1.5 pr-3 text-right text-xs tabular-nums text-[var(--text-secondary)]">
                            {qty(line.expected)}
                          </td>
                          <td className="py-1.5 pr-3 text-right text-xs font-bold tabular-nums text-[var(--text-primary)]">
                            {qty(line.counted)}
                          </td>
                          <td
                            className={`py-1.5 text-right text-xs font-extrabold tabular-nums ${
                              v < 0
                                ? "text-[var(--error-strong)]"
                                : v > 0
                                  ? "text-[var(--warning-strong)]"
                                  : "text-[var(--text-tertiary)]"
                            }`}
                          >
                            {v > 0 ? "+" : ""}
                            {qty(line.variance)}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              <div className="mt-4 rounded-2xl bg-[var(--bg-base)] px-4 py-3">
                <div className="flex items-center justify-between gap-3">
                  <span className="text-xs font-bold text-[var(--text-secondary)]">
                    Value of the difference
                  </span>
                  <span className="text-sm font-black tabular-nums text-[var(--text-primary)]">
                    {current.variance_value === null
                      ? "Unknown"
                      : money(num(current.variance_value), currencyCode)}
                  </span>
                </div>
                {current.variance_value === null && (
                  <p className="mt-1 text-[11px] font-semibold text-[var(--text-tertiary)]">
                    Some counted items have no recorded cost price, so the total
                    would understate the loss.
                  </p>
                )}
              </div>

              {canApply ? (
                <button
                  type="button"
                  onClick={() => void apply()}
                  disabled={busy}
                  className="mt-4 w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-[var(--primary)] px-6 py-3.5 text-sm font-extrabold text-white hover:bg-[var(--primary-hover)] disabled:opacity-50"
                >
                  <ClipboardCheck className="w-4 h-4" />
                  {busy ? "Applying…" : "Apply the count to stock"}
                </button>
              ) : (
                <p className="mt-4 flex items-start gap-2 rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-4 py-3 text-[11px] font-bold text-[var(--warning-strong)]">
                  <TriangleAlert className="w-3.5 h-3.5 shrink-0 mt-0.5" />
                  Counting is saved. A manager or owner applies it to stock.
                </p>
              )}
            </div>
          )}
        </>
      )}

      {/* --- earlier counts ---------------------------------------------- */}
      {history.length > 0 && (
        <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
          <h3 className="text-xs font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
            Earlier counts
          </h3>
          <div className="mt-3 space-y-2">
            {history.slice(0, 10).map((t) => (
              <div
                key={t.id}
                className="flex flex-wrap items-center justify-between gap-2 rounded-2xl bg-[var(--bg-base)] px-4 py-2.5"
              >
                <span className="font-mono text-[11px] font-bold text-[var(--text-primary)]">
                  {t.reference}
                </span>
                <span className="text-[11px] font-semibold text-[var(--text-secondary)]">
                  {t.counted_lines} counted · {t.missing_count} missing
                  {t.variance_value !== null &&
                    ` · ${money(num(t.variance_value), currencyCode)}`}
                </span>
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-extrabold uppercase ${
                    t.status === "applied"
                      ? "bg-[var(--success)]/10 text-[var(--success-strong)]"
                      : "bg-[var(--text-tertiary)]/10 text-[var(--text-tertiary)]"
                  }`}
                >
                  {t.status}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function Tally({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone: "good" | "warn" | "bad";
}) {
  const colour =
    tone === "bad"
      ? "text-[var(--error-strong)]"
      : tone === "warn"
        ? "text-[var(--warning-strong)]"
        : "text-[var(--success-strong)]";
  return (
    <div className="rounded-2xl bg-[var(--bg-base)] px-4 py-2">
      <span className={`text-lg font-black tabular-nums ${colour}`}>{value}</span>
      <span className="ml-2 text-[10px] font-extrabold uppercase tracking-wide text-[var(--text-tertiary)]">
        {label}
      </span>
    </div>
  );
}
