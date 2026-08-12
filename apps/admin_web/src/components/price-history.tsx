"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { TrendingDown, TrendingUp } from "lucide-react";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

type Point = {
  purchase_id: string;
  date: string | null;
  invoice_number: string;
  unit_cost: string;
  quantity: string;
};

type Series = {
  item_id: string;
  item_name: string;
  supplier_id: string;
  supplier_name: string;
  latest_cost: string | null;
  previous_cost: string | null;
  /** Null when there is only one purchase, or the baseline was zero. */
  change_percent: string | null;
  purchases: number;
  points: Point[];
};

type Payload = {
  series: Series[];
  movements: Series[];
  material_change_percent: string;
  tracked_pairs: number;
};

const num = (v: string | null | undefined): number => {
  const n = parseFloat(String(v ?? "0"));
  return Number.isFinite(n) ? n : 0;
};

const money = (v: number, currency: string) => {
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
 * What the shop pays its suppliers, and who has been putting prices up.
 *
 * Nothing new is recorded to produce this — every purchase already stored the
 * cost per item — so a shop that has been entering bills has a history waiting
 * for it. That is also the trap: the data was never collected with this
 * question in mind, so the screen is careful to say when it cannot answer
 * rather than filling the gap with a confident figure.
 *
 * Rises lead, because a rise costs money and a fall does not. A pair with one
 * purchase shows the price with no percentage at all: one purchase is a price,
 * not a trend, and a shopkeeper who is told otherwise once stops believing the
 * screen.
 */
export function PriceHistoryScreen({ currencyCode = "INR" }: { currencyCode?: string }) {
  const [payload, setPayload] = useState<Payload | null>(null);
  const [openItem, setOpenItem] = useState<Series | null>(null);
  const [points, setPoints] = useState<Point[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/price-history");
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || "Could not load price history.");
      setPayload(body);
    } catch (err) {
      setError(errorMessage(err, "Could not load price history."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const openDetail = async (row: Series) => {
    setOpenItem(row);
    setPoints(null);
    try {
      const res = await fetch(`/api/price-history?item_id=${encodeURIComponent(row.item_id)}`);
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || "Could not load that item.");
      const match = (body.series as Series[] | undefined)?.find(
        (s) => s.supplier_id === row.supplier_id,
      );
      setPoints(match?.points ?? []);
    } catch (err) {
      setError(errorMessage(err, "Could not load that item."));
      setOpenItem(null);
    }
  };

  const steady = useMemo(() => {
    if (!payload) return [];
    const moved = new Set(payload.movements.map((m) => `${m.item_id}:${m.supplier_id}`));
    return payload.series.filter((s) => !moved.has(`${s.item_id}:${s.supplier_id}`));
  }, [payload]);

  if (loading) {
    return (
      <p className="py-14 text-center text-xs font-bold text-[var(--text-tertiary)]">
        Loading…
      </p>
    );
  }

  if (error) {
    return (
      <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-3 text-xs font-bold text-[var(--error-strong)]">
        {error}
      </div>
    );
  }

  if (!payload || payload.tracked_pairs === 0) {
    return (
      <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-6">
        <h3 className="text-base font-extrabold text-[var(--text-primary)]">
          Nothing to compare yet
        </h3>
        <p className="mt-1.5 max-w-prose text-xs font-semibold text-[var(--text-secondary)]">
          This is built from purchase invoices you have already entered — record
          a few, with the supplier attached, and the prices you pay will start
          showing up here on their own.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
        <h3 className="text-sm font-extrabold text-[var(--text-primary)]">
          Prices that moved
        </h3>
        <p className="mt-1 max-w-prose text-[11px] font-semibold text-[var(--text-tertiary)]">
          Each supplier is compared only against its own earlier price, so a
          cheaper supplier never reads as a price cut. Movements under{" "}
          {payload.material_change_percent}% are left out.
        </p>

        {payload.movements.length === 0 ? (
          <p className="mt-4 rounded-2xl bg-[var(--bg-base)] px-4 py-3 text-xs font-bold text-[var(--text-secondary)]">
            No supplier has moved a price by more than{" "}
            {payload.material_change_percent}% since the purchase before.
          </p>
        ) : (
          <div className="mt-4 space-y-2">
            {payload.movements.map((row) => (
              <MovementRow
                key={`${row.item_id}:${row.supplier_id}`}
                row={row}
                currencyCode={currencyCode}
                onOpen={() => void openDetail(row)}
              />
            ))}
          </div>
        )}
      </div>

      {steady.length > 0 && (
        <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
          <h3 className="text-xs font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
            Holding steady
          </h3>
          <div className="mt-3 overflow-x-auto">
            <table className="w-full min-w-[520px] text-left">
              <thead>
                <tr className="text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
                  <th className="pb-1.5 pr-3">Item</th>
                  <th className="pb-1.5 pr-3">Supplier</th>
                  <th className="pb-1.5 pr-3 text-right">Last paid</th>
                  <th className="pb-1.5 text-right">Purchases</th>
                </tr>
              </thead>
              <tbody>
                {steady.map((row) => (
                  <tr
                    key={`${row.item_id}:${row.supplier_id}`}
                    className="border-t border-[var(--border-soft)]"
                  >
                    <td className="py-1.5 pr-3 text-xs font-bold text-[var(--text-primary)]">
                      {row.item_name}
                    </td>
                    <td className="py-1.5 pr-3 text-xs font-semibold text-[var(--text-secondary)]">
                      {row.supplier_name}
                    </td>
                    <td className="py-1.5 pr-3 text-right text-xs font-bold tabular-nums text-[var(--text-primary)]">
                      {money(num(row.latest_cost), currencyCode)}
                    </td>
                    <td className="py-1.5 text-right text-xs tabular-nums text-[var(--text-tertiary)]">
                      {/* One purchase is a price, not a trend, and saying so
                          is more useful than showing a percentage that would
                          have to be invented. */}
                      {row.purchases === 1 ? "first" : row.purchases}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {openItem && (
        <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h3 className="text-sm font-extrabold text-[var(--text-primary)]">
              {openItem.item_name} · {openItem.supplier_name}
            </h3>
            <button
              type="button"
              onClick={() => setOpenItem(null)}
              className="text-[11px] font-extrabold text-[var(--text-tertiary)] hover:underline"
            >
              Close
            </button>
          </div>
          <p className="mt-1 text-[11px] font-semibold text-[var(--text-tertiary)]">
            Every invoice behind the figure, so it can be checked against the
            paperwork.
          </p>
          {points === null ? (
            <p className="mt-4 text-xs font-bold text-[var(--text-tertiary)]">Loading…</p>
          ) : (
            <div className="mt-3 overflow-x-auto">
              <table className="w-full min-w-[420px] text-left">
                <thead>
                  <tr className="text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
                    <th className="pb-1.5 pr-3">Date</th>
                    <th className="pb-1.5 pr-3">Invoice</th>
                    <th className="pb-1.5 pr-3 text-right">Quantity</th>
                    <th className="pb-1.5 text-right">Unit cost</th>
                  </tr>
                </thead>
                <tbody>
                  {points.map((point) => (
                    <tr key={point.purchase_id} className="border-t border-[var(--border-soft)]">
                      <td className="py-1.5 pr-3 text-xs font-semibold text-[var(--text-secondary)]">
                        {point.date ?? "—"}
                      </td>
                      <td className="py-1.5 pr-3 font-mono text-[11px] text-[var(--text-tertiary)]">
                        {point.invoice_number || "—"}
                      </td>
                      <td className="py-1.5 pr-3 text-right text-xs tabular-nums text-[var(--text-secondary)]">
                        {point.quantity}
                      </td>
                      <td className="py-1.5 text-right text-xs font-bold tabular-nums text-[var(--text-primary)]">
                        {money(num(point.unit_cost), currencyCode)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function MovementRow({
  row,
  currencyCode,
  onOpen,
}: {
  row: Series;
  currencyCode: string;
  onOpen: () => void;
}) {
  const change = num(row.change_percent);
  const up = change > 0;

  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex w-full flex-wrap items-center justify-between gap-3 rounded-2xl bg-[var(--bg-base)] px-4 py-3 text-left hover:bg-[var(--bg-soft)]"
    >
      <span className="min-w-0">
        <span className="block truncate text-xs font-extrabold text-[var(--text-primary)]">
          {row.item_name}
        </span>
        <span className="block text-[11px] font-semibold text-[var(--text-tertiary)]">
          {row.supplier_name} · {money(num(row.previous_cost), currencyCode)} →{" "}
          {money(num(row.latest_cost), currencyCode)}
        </span>
      </span>
      <span
        className={`inline-flex shrink-0 items-center gap-1.5 text-sm font-black tabular-nums ${
          // A rise costs money and a fall saves it, so the colour carries the
          // meaning rather than merely decorating the number.
          up ? "text-[var(--error-strong)]" : "text-[var(--success-strong)]"
        }`}
      >
        {up ? <TrendingUp className="w-4 h-4" /> : <TrendingDown className="w-4 h-4" />}
        {up ? "+" : ""}
        {row.change_percent}%
      </span>
    </button>
  );
}
