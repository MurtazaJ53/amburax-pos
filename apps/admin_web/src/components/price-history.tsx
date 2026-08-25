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
      <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-6">
        <h3 className="text-base font-extrabold text-[var(--text-primary)]">
          Nothing to compare yet
        </h3>
        <p className="mt-1.5 max-w-prose text-xs font-semibold text-[var(--text-secondary)]">
          Nothing is entered on this screen. It is built from the purchase
          bills you record - book in a delivery on Purchase orders, or enter a
          bill on Suppliers, always with the supplier attached, and the prices
          you pay appear here on their own. Two purchases of the same item from
          the same supplier are needed before there is anything to compare.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      {/* Where this comes from, because nothing is entered on this screen and
          that is the first thing anyone wonders. */}
      <section className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm animate-fade-in-up">
        <h2 className="m-0 text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
          Where these figures come from
        </h2>
        <p className="m-0 mt-2 max-w-[72ch] text-[13px] font-medium leading-[1.6] text-[var(--text-secondary)]">
          Nothing is recorded here. Every purchase bill you enter already
          stores what each item cost, along with the supplier and the date - so
          the shop has been building this history since the first bill went in.
          It simply had nowhere to be looked at. Book in a delivery on Purchase
          orders, or enter a bill on Suppliers, and it appears here on its own.
        </p>
        <ul className="m-0 mt-3 flex list-none flex-col gap-1.5 p-0 text-[12.5px] font-medium text-[var(--text-secondary)]">
          {[
            "A supplier is only ever compared against its own earlier price. The same shirt at 100 from one and 120 from another is two suppliers, not a rise.",
            "Lines with no cost are skipped. A zero is a free sample or a gap, and treating it as a price makes the next real one look like an infinite increase.",
            "Two purchases minimum. One purchase is a price, not a trend.",
          ].map((line) => (
            <li key={line} className="flex gap-2">
              <span aria-hidden="true" className="text-[var(--text-tertiary)]">
                &middot;
              </span>
              {line}
            </li>
          ))}
        </ul>
      </section>

      {/* One row of figures, like every other screen. */}
      <div className="flex flex-wrap items-center gap-4 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm animate-fade-in-up">
        <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
          {[
            {
              label: "tracked",
              value: String(payload.tracked_pairs),
              detail: "item and supplier pairs",
              tone: "text-[var(--text-primary)]",
            },
            {
              label: "moved",
              value: String(payload.movements.length),
              detail: `over ${payload.material_change_percent}%`,
              tone:
                payload.movements.length > 0
                  ? "text-[var(--warning-strong)]"
                  : "text-[var(--success-strong)]",
            },
            {
              label: "gone up",
              value: String(payload.movements.filter((m) => num(m.change_percent) > 0).length),
              detail: "costing you more",
              tone:
                payload.movements.some((m) => num(m.change_percent) > 0)
                  ? "text-[var(--error-strong)]"
                  : "text-[var(--text-primary)]",
            },
            {
              label: "gone down",
              value: String(payload.movements.filter((m) => num(m.change_percent) < 0).length),
              detail: "cheaper than before",
              tone: "text-[var(--success-strong)]",
            },
          ].map((stat, index) => (
            <div
              key={stat.label}
              className={`flex shrink-0 flex-col justify-center ${
                index > 0 ? "border-l border-[var(--border-soft)] pl-4" : ""
              }`}
            >
              <dt className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                {stat.label}
              </dt>
              <dd className="m-0 flex items-baseline gap-1.5">
                <span className={`tnum font-mono text-[17px] font-bold leading-tight ${stat.tone}`}>
                  {stat.value}
                </span>
                <span className="whitespace-nowrap text-[11px] font-semibold text-[var(--text-tertiary)]">
                  {stat.detail}
                </span>
              </dd>
            </div>
          ))}
        </dl>
      </div>

      <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm">
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
        <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
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
        <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
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
