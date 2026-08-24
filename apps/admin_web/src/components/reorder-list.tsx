"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { CheckCircle2, ClipboardCopy, RefreshCw } from "lucide-react";

import { formatCurrency } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



type ReorderItem = {
  id: string;
  name: string;
  sku: string;
  category: string;
  unit: string;
  stock: string;
  reorder_level: number;
  uses_default_level: boolean;
  suggested_qty: string;
  cost_price: string | null;
  estimated_cost: string | null;
  out_of_stock: boolean;
};

type ReorderPayload = {
  default_reorder_level: number;
  out_of_stock_count: number;
  /** Null when any item lacks a cost price — a half-counted budget is worse. */
  estimated_total: string | null;
  items: ReorderItem[];
};

function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatQty(value: string | number): string {
  const n = num(value);
  return Number.isInteger(n) ? String(n) : n.toFixed(3).replace(/0+$/, "").replace(/\.$/, "");
}

/**
 * Build the purchase message a shopkeeper sends their supplier. Plain text on
 * purpose — it has to be readable in a WhatsApp bubble, not a spreadsheet.
 * Mirrors `buildReorderMessage` in the mobile app.
 */
export function buildReorderMessage(shopName: string, items: ReorderItem[]): string {
  const shop = shopName.trim() || "our shop";
  if (items.length === 0) return `Nothing to reorder for ${shop} right now.`;

  const lines = [`*${shop}* - stock order`, ""];
  for (const item of items) {
    const unit = (item.unit || "").trim();
    const qty = formatQty(item.suggested_qty) + (unit ? ` ${unit}` : "");
    const sku = (item.sku || "").trim();
    lines.push(`- ${item.name}${sku ? ` (${sku})` : ""}: ${qty}`);
  }
  lines.push("", "Please confirm availability and rate. Thank you.");
  return lines.join("\n");
}

/** The daily "what do I need to buy" list. */
export function ReorderList({ shopName }: { shopName: string }) {
  const [data, setData] = useState<ReorderPayload | null>(null);
  const [excluded, setExcluded] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/reports/reorder-list");
      if (!res.ok) throw new Error(`Could not load the buying list (${res.status})`);
      setData(await res.json());
    } catch (err) {
      setError(errorMessage(err, "Something went wrong loading the list."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const all = useMemo(() => data?.items ?? [], [data]);
  const selected = useMemo(
    () => all.filter((i) => !excluded.has(i.id)),
    [all, excluded]
  );

  // Only quote a budget when every selected item has a cost. A partial sum
  // reads as the whole bill and is always too low.
  const selectedEstimate = useMemo(() => {
    if (selected.length === 0) return null;
    if (selected.some((i) => i.estimated_cost === null)) return null;
    return selected.reduce((sum, i) => sum + num(i.estimated_cost), 0);
  }, [selected]);

  const toggle = (id: string) => {
    setExcluded((prev) => {
      const next = new Set(prev);
      if (!next.delete(id)) next.add(id);
      return next;
    });
  };

  const copyOrder = async () => {
    try {
      await navigator.clipboard.writeText(buildReorderMessage(shopName, selected));
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2500);
    } catch {
      setError("Could not copy to the clipboard. Select the list and copy manually.");
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <button
          type="button"
          onClick={() => void copyOrder()}
          disabled={selected.length === 0}
          className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-4 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] disabled:opacity-50 border border-[var(--primary)]/25"
        >
          <ClipboardCopy className="w-3.5 h-3.5" />
          {copied ? "Copied!" : `Copy order (${selected.length} items)`}
        </button>
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

      {data && all.length > 0 && (
        <div
          className={`rounded-[28px] border p-6 sm:p-7 ${
            data.out_of_stock_count > 0
              ? "border-[var(--error)]/30 bg-[var(--error)]/10"
              : "border-[var(--warning)]/30 bg-[var(--warning)]/10"
          }`}
        >
          <p className="text-lg font-[900] tracking-tight text-text-primary">
            {all.length} item{all.length === 1 ? "" : "s"} need restocking
          </p>
          <p className="mt-1 text-xs font-semibold text-text-secondary">
            {data.out_of_stock_count > 0
              ? `${data.out_of_stock_count} already out of stock — you are losing sales on these today.`
              : "All still in stock, but running low."}
          </p>
          {selectedEstimate !== null && (
            <p className="mt-2 text-sm font-extrabold text-text-primary">
              Estimated cost: {formatCurrency(selectedEstimate)}
            </p>
          )}
          {selectedEstimate === null && selected.length > 0 && (
            <p className="mt-2 text-xs font-semibold text-text-tertiary">
              No cost estimate — some selected items have no cost price recorded.
            </p>
          )}
        </div>
      )}

      {loading && !data ? null : all.length === 0 && !error ? (
        <div className="rounded-[28px] border border-border-soft bg-surface px-6 py-12 text-center">
          <CheckCircle2 className="w-9 h-9 mx-auto text-[var(--success-strong)]" />
          <p className="mt-3 text-sm font-black text-text-primary">
            Nothing needs reordering
          </p>
          <p className="mt-1 text-xs font-semibold text-text-secondary">
            Items appear here once they drop to their reorder level. Set that level
            when editing an item; the default is {data?.default_reorder_level ?? 5}.
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {all.map((item) => {
            const included = !excluded.has(item.id);
            const unit = (item.unit || "").trim();
            return (
              <label
                key={item.id}
                className={`flex items-center gap-3 rounded-2xl border bg-surface px-4 py-3 cursor-pointer ${
                  included ? "border-border-soft" : "border-border opacity-60"
                }`}
              >
                <input
                  type="checkbox"
                  checked={included}
                  onChange={() => toggle(item.id)}
                  className="w-4 h-4 accent-[var(--primary)]"
                />
                <div className="flex-1 min-w-0">
                  <p className="truncate text-sm font-bold text-text-primary">
                    {item.name}
                    {item.sku && (
                      <span className="ml-2 text-[11px] font-semibold text-text-tertiary">
                        {item.sku}
                      </span>
                    )}
                  </p>
                  <div className="mt-1 flex flex-wrap items-center gap-2">
                    <span
                      className={`rounded-full px-2.5 py-0.5 text-[10px] font-extrabold ${
                        item.out_of_stock
                          ? "bg-[var(--error)]/15 text-[var(--error-strong)]"
                          : "bg-[var(--warning)]/15 text-[var(--warning-strong)]"
                      }`}
                    >
                      {item.out_of_stock
                        ? "OUT OF STOCK"
                        : `Left ${formatQty(item.stock)}${unit ? ` ${unit}` : ""}`}
                    </span>
                    <span className="text-[11px] font-bold text-text-secondary">
                      Order {formatQty(item.suggested_qty)}
                      {unit ? ` ${unit}` : ""}
                    </span>
                    {item.uses_default_level && (
                      <span className="text-[11px] font-semibold text-text-tertiary">
                        default level {item.reorder_level}
                      </span>
                    )}
                  </div>
                </div>
                {item.estimated_cost !== null && (
                  <span className="shrink-0 text-sm font-extrabold text-text-primary">
                    {formatCurrency(num(item.estimated_cost))}
                  </span>
                )}
              </label>
            );
          })}
        </div>
      )}
    </div>
  );
}
