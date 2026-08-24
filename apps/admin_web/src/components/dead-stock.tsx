"use client";

import { useCallback, useEffect, useState } from "react";
import { CheckCircle2, RefreshCw } from "lucide-react";

import { formatCurrency } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



type DeadStockItem = {
  id: string;
  name: string;
  category: string;
  stock: string;
  sell_price: string;
  cost_price: string | null;
  tied_up_value: string;
  /** "cost" when a real cost price was known, otherwise "sale_price". */
  valued_at: "cost" | "sale_price";
  last_sold_at: string | null;
  never_sold: boolean;
};

type DeadStockPayload = {
  days: number;
  tied_up_total: string;
  never_sold_count: number;
  items: DeadStockItem[];
};

const WINDOWS = [30, 90, 180] as const;

function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatQty(value: string | number): string {
  const n = num(value);
  return Number.isInteger(n) ? String(n) : n.toFixed(3).replace(/0+$/, "").replace(/\.$/, "");
}

function lastSoldLabel(item: DeadStockItem): string {
  if (item.never_sold) return "NEVER SOLD";
  if (!item.last_sold_at) return "NOT SOLD RECENTLY";
  const then = new Date(item.last_sold_at);
  if (Number.isNaN(then.getTime())) return "NOT SOLD RECENTLY";
  const days = Math.floor((Date.now() - then.getTime()) / 86_400_000);
  if (days >= 365) {
    const years = Math.floor(days / 365);
    return `${years} YEAR${years === 1 ? "" : "S"} AGO`;
  }
  if (days >= 30) {
    const months = Math.floor(days / 30);
    return `${months} MONTH${months === 1 ? "" : "S"} AGO`;
  }
  return `${days} DAY${days === 1 ? "" : "S"} AGO`;
}

/** What money is sitting on the shelf not moving. */
export function DeadStock() {
  const [days, setDays] = useState<number>(90);
  const [data, setData] = useState<DeadStockPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/reports/dead-stock?days=${days}`);
      if (res.status === 403) {
        throw new Error(
          "This report shows cost prices, so it needs a manager, admin or owner role."
        );
      }
      if (!res.ok) throw new Error(`Could not load dead stock (${res.status})`);
      setData(await res.json());
    } catch (err) {
      setData(null);
      setError(errorMessage(err, "Something went wrong loading the report."));
    } finally {
      setLoading(false);
    }
  }, [days]);

  useEffect(() => {
    void load();
  }, [load]);

  const items = data?.items ?? [];
  const anyEstimated = items.some((i) => i.valued_at === "sale_price");

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="inline-flex rounded-2xl border border-border-soft bg-surface p-1">
          {WINDOWS.map((w) => (
            <button
              key={w}
              type="button"
              onClick={() => setDays(w)}
              className={`px-4 py-2 rounded-xl text-xs font-extrabold transition-colors ${
                days === w
                  ? "bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 shadow-sm"
                  : "text-text-secondary hover:text-text-primary"
              }`}
            >
              {w === 180 ? "6 months" : `${w} days`}
            </button>
          ))}
        </div>
        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="inline-flex items-center gap-2 rounded-xl border border-border-soft bg-surface px-4 py-2 text-xs font-extrabold text-text-secondary hover:text-text-primary disabled:opacity-50"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? "animate-spin" : ""}`} />
          Refresh
        </button>
      </div>

      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {data && (
        <div className="rounded-[28px] border border-[var(--warning)]/30 bg-[var(--warning)]/10 p-6 sm:p-7">
          <p className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
            Money sitting on the shelf
          </p>
          <p className="mt-1 text-3xl sm:text-4xl font-[900] tracking-tight text-[var(--warning-strong)]">
            {formatCurrency(num(data.tied_up_total))}
          </p>
          <p className="mt-2 text-xs font-semibold text-text-secondary">
            {items.length} item{items.length === 1 ? "" : "s"} unsold for {data.days} days
            {data.never_sold_count > 0 && ` · ${data.never_sold_count} never sold at all`}
          </p>
        </div>
      )}

      {loading && !data ? null : items.length === 0 && !error ? (
        <div className="rounded-[28px] border border-border-soft bg-surface px-6 py-12 text-center">
          <CheckCircle2 className="w-9 h-9 mx-auto text-[var(--success-strong)]" />
          <p className="mt-3 text-sm font-black text-text-primary">Everything is moving</p>
          <p className="mt-1 text-xs font-semibold text-text-secondary">
            No stock has been sitting unsold for {days} days.
          </p>
        </div>
      ) : (
        items.length > 0 && (
          <div className="rounded-[28px] border border-border-soft bg-surface overflow-hidden">
            <p className="px-6 py-4 text-xs font-semibold text-text-secondary border-b border-border-soft">
              Worst first, by money tied up. Consider a discount, a bundle, or
              returning it to the supplier.
            </p>
            <div className="overflow-x-auto">
              <table className="min-w-full border-collapse">
                <thead>
                  <tr className="border-b border-border-soft text-left text-[11px] uppercase tracking-wider text-text-tertiary">
                    <th className="px-6 py-3 font-extrabold">Item</th>
                    <th className="px-6 py-3 font-extrabold">Last sold</th>
                    <th className="px-6 py-3 font-extrabold text-right">In stock</th>
                    <th className="px-6 py-3 font-extrabold text-right">Tied up</th>
                  </tr>
                </thead>
                <tbody>
                  {items.slice(0, 200).map((item) => (
                    <tr key={item.id} className="border-b border-border-soft/60 last:border-0">
                      <td className="px-6 py-4">
                        <p className="text-sm font-bold text-text-primary">{item.name}</p>
                        <p className="text-[11px] font-semibold text-text-tertiary">
                          {item.category}
                        </p>
                      </td>
                      <td className="px-6 py-4">
                        <span
                          className={`inline-block rounded-full px-2.5 py-1 text-[10px] font-extrabold ${
                            item.never_sold
                              ? "bg-[var(--error)]/15 text-[var(--error-strong)]"
                              : "bg-[var(--warning)]/15 text-[var(--warning-strong)]"
                          }`}
                        >
                          {lastSoldLabel(item)}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-right text-sm font-bold text-text-primary">
                        {formatQty(item.stock)}
                      </td>
                      <td className="px-6 py-4 text-right">
                        <p className="text-sm font-extrabold text-[var(--warning-strong)]">
                          {formatCurrency(num(item.tied_up_value))}
                        </p>
                        <p className="text-[10px] font-semibold text-text-tertiary">
                          {item.valued_at === "cost" ? "at cost" : "at sale price"}
                        </p>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {anyEstimated && (
              <p className="px-6 py-4 text-xs font-semibold text-text-secondary border-t border-border-soft">
                Items marked &ldquo;at sale price&rdquo; have no cost price recorded, so
                what they are really worth is an over-estimate. Add cost prices in
                Stock for a true figure.
              </p>
            )}
          </div>
        )
      )}
    </div>
  );
}
