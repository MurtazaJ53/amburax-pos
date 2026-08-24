"use client";

import { useCallback, useEffect, useState } from "react";
import { ArrowDownRight, ArrowUpRight, Package, RefreshCw, TrendingUp } from "lucide-react";

import { formatCurrency } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



type CashFlow = {
  days: number;
  sales_collected: string;
  purchases: string;
  expenses: string;
  money_out: string;
  net: string;
};

type BestSeller = {
  name: string;
  quantity_sold: string;
  revenue: string;
  /** Null whenever any line of that product was billed without a cost price. */
  profit: string | null;
};

const WINDOWS = [7, 30, 90] as const;

/** DRF serialises money as JSON strings; parse defensively. */
function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return value;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatQty(value: string | number): string {
  const n = num(value);
  return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
}

export function BusinessPulse() {
  const [days, setDays] = useState<number>(30);
  const [cashFlow, setCashFlow] = useState<CashFlow | null>(null);
  const [sellers, setSellers] = useState<BestSeller[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // A cashier can read best sellers but not the shop's cash position, so the
  // two halves fail independently.
  const [cashDenied, setCashDenied] = useState(false);
  /** Net across twice the chosen window, used only to work out the previous
   *  period. Null when that second call did not succeed. */
  const [doubleWindowNet, setDoubleWindowNet] = useState<number | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    setCashDenied(false);
    try {
      // The endpoint takes a rolling window only, so the previous period is
      // derived: net over twice the window, minus net over this one. Without
      // it the headline figure has nothing to be judged against.
      const [cashRes, sellersRes, priorRes] = await Promise.all([
        fetch(`/api/reports/cash-flow?days=${days}`),
        fetch(`/api/reports/best-sellers?days=${days}`),
        fetch(`/api/reports/cash-flow?days=${days * 2}`),
      ]);

      if (priorRes.ok) {
        setDoubleWindowNet(num((await priorRes.json())?.net));
      } else {
        setDoubleWindowNet(null);
      }

      if (cashRes.ok) {
        setCashFlow(await cashRes.json());
      } else {
        setCashFlow(null);
        if (cashRes.status === 403) {
          setCashDenied(true);
        } else {
          throw new Error(`Could not load cash flow (${cashRes.status})`);
        }
      }

      if (!sellersRes.ok) {
        throw new Error(`Could not load best sellers (${sellersRes.status})`);
      }
      const body = await sellersRes.json();
      setSellers(Array.isArray(body.items) ? body.items : []);
    } catch (err) {
      setError(errorMessage(err, "Something went wrong loading the report."));
    } finally {
      setLoading(false);
    }
  }, [days]);

  useEffect(() => {
    void load();
  }, [load]);

  const net = num(cashFlow?.net);

  /** Change against the period before this one, or null when there is no
   *  usable baseline. A rise measured against zero is noise, not insight. */
  const changeVsPrevious = (() => {
    if (doubleWindowNet === null || cashFlow === null) return null;
    const previous = doubleWindowNet - net;
    if (previous <= 0) return null;
    return Math.round(((net - previous) / previous) * 100);
  })();
  const topQty = sellers.length ? num(sellers[0].quantity_sold) : 0;
  const anyProfitHidden = sellers.some((s) => s.profit === null);

  return (
    <div className="space-y-6">
      {/* Window picker */}
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
              {w} days
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

      {/* Cash position */}
      {cashDenied ? (
        <div className="rounded-[24px] border border-border-soft bg-surface px-5 py-4 text-sm font-semibold text-text-secondary">
          Your role can see what is selling, but not the shop&rsquo;s cash position.
          Ask the owner or a manager for that.
        </div>
      ) : (
        <div
          className={`rounded-[28px] border p-6 sm:p-7 ${
            net >= 0
              ? "border-[var(--success)]/30 bg-[var(--success)]/10"
              : "border-[var(--error)]/30 bg-[var(--error)]/10"
          }`}
        >
          <div className="flex flex-wrap items-center gap-2.5">
            <p className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-text-tertiary">
              Money kept in the last {cashFlow?.days ?? days} days
            </p>
            {changeVsPrevious !== null && (
              <span
                className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11.5px] font-bold ${
                  changeVsPrevious >= 0
                    ? "bg-[var(--success)]/10 text-[var(--success-strong)]"
                    : "bg-[var(--error)]/10 text-[var(--error-strong)]"
                }`}
              >
                {changeVsPrevious >= 0 ? (
                  <ArrowUpRight className="h-3 w-3" />
                ) : (
                  <ArrowDownRight className="h-3 w-3" />
                )}
                {Math.abs(changeVsPrevious)}% vs previous {cashFlow?.days ?? days} days
              </span>
            )}
          </div>
          <p
            className={`mt-1 text-3xl sm:text-4xl font-[900] tracking-tight ${
              net >= 0 ? "text-[var(--success-strong)]" : "text-[var(--error-strong)]"
            }`}
          >
            {formatCurrency(net)}
          </p>
          <div className="mt-5 grid grid-cols-1 sm:grid-cols-3 gap-4">
            <FlowStat
              label="Collected from sales"
              value={num(cashFlow?.sales_collected)}
              direction="in"
            />
            <FlowStat
              label="Paid to suppliers"
              value={num(cashFlow?.purchases)}
              direction="out"
              note="Only invoices actually paid"
            />
            <FlowStat
              label="Expenses"
              value={num(cashFlow?.expenses)}
              direction="out"
            />
          </div>
        </div>
      )}

      {/* Best sellers */}
      <div className="rounded-[28px] border border-border-soft bg-surface overflow-hidden">
        <div className="flex items-center gap-2.5 px-6 py-5 border-b border-border-soft">
          <TrendingUp className="w-4 h-4 text-[var(--primary)]" />
          <h2 className="text-sm font-black text-text-primary uppercase tracking-wide">
            Best sellers
          </h2>
        </div>

        {loading && !sellers.length ? (
          <div className="px-6 py-12 text-center text-sm font-semibold text-text-secondary">
            Loading&hellip;
          </div>
        ) : sellers.length === 0 ? (
          <div className="px-6 py-12 text-center">
            <Package className="w-8 h-8 mx-auto text-text-tertiary" />
            <p className="mt-3 text-sm font-bold text-text-primary">
              No sales in this period
            </p>
            <p className="mt-1 text-xs font-semibold text-text-secondary">
              Bills raised on the app or the POS will show up here.
            </p>
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="min-w-full border-collapse">
                <thead>
                  <tr className="border-b border-border-soft text-left text-[11px] uppercase tracking-wider text-text-tertiary">
                    <th className="px-6 py-3 font-extrabold">#</th>
                    <th className="px-6 py-3 font-extrabold">Item</th>
                    <th className="px-6 py-3 font-extrabold text-right">Sold</th>
                    <th className="px-6 py-3 font-extrabold text-right">Revenue</th>
                    <th className="px-6 py-3 font-extrabold text-right">Profit</th>
                    <th className="px-6 py-3 font-extrabold text-right">Margin</th>
                  </tr>
                </thead>
                <tbody>
                  {sellers.map((item, index) => {
                    const share = topQty > 0 ? num(item.quantity_sold) / topQty : 0;
                    // Margin as a share of what the customer paid — the figure
                    // a shopkeeper compares against a distributor's offer.
                    const revenue = num(item.revenue);
                    const margin =
                      item.profit === null || revenue <= 0
                        ? null
                        : (num(item.profit) / revenue) * 100;
                    return (
                      <tr
                        key={`${item.name}-${index}`}
                        className="border-b border-border-soft/60 last:border-0"
                      >
                        <td className="px-6 py-4 text-xs font-black text-text-tertiary">
                          {index + 1}
                        </td>
                        <td className="px-6 py-4">
                          <p className="text-sm font-bold text-text-primary">{item.name}</p>
                          <div className="mt-2 h-1.5 w-40 max-w-full rounded-full bg-border-soft overflow-hidden">
                            <div
                              className="h-full rounded-full bg-[var(--primary)]"
                              style={{ width: `${Math.max(share * 100, 4)}%` }}
                            />
                          </div>
                        </td>
                        <td className="px-6 py-4 text-right text-sm font-bold text-text-primary">
                          {formatQty(item.quantity_sold)}
                        </td>
                        <td className="px-6 py-4 text-right text-sm font-extrabold text-text-primary">
                          {formatCurrency(num(item.revenue))}
                        </td>
                        <td className="px-6 py-4 text-right text-sm font-bold">
                          {item.profit === null ? (
                            <span
                              className="text-text-tertiary"
                              title="Some bills for this item were raised without a cost price, so profit cannot be worked out."
                            >
                              &mdash;
                            </span>
                          ) : (
                            <span
                              className={
                                num(item.profit) >= 0
                                  ? "text-[var(--success-strong)]"
                                  : "text-[var(--error-strong)]"
                              }
                            >
                              {formatCurrency(num(item.profit))}
                            </span>
                          )}
                        </td>
                        <td className="px-6 py-4 text-right text-sm font-bold">
                          {margin === null ? (
                            <span
                              className="rounded-full bg-[var(--warning)]/10 px-2.5 py-1 text-[11px] font-bold text-[var(--warning-strong)]"
                              title="At least one bill for this item had no cost price, so margin cannot be worked out."
                            >
                              No cost
                            </span>
                          ) : (
                            <span
                              className={
                                margin < 0
                                  ? "text-[var(--error-strong)]"
                                  : margin < 10
                                    ? "text-[var(--warning-strong)]"
                                    : "text-[var(--success-strong)]"
                              }
                            >
                              {margin.toFixed(1)}%
                            </span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {anyProfitHidden && (
              <p className="px-6 py-4 text-xs font-semibold text-text-secondary border-t border-border-soft">
                A dash in Profit means at least one bill for that item had no cost
                price recorded. Add cost prices in Stock to see the margin.
              </p>
            )}
          </>
        )}
      </div>
    </div>
  );
}

function FlowStat({
  label,
  value,
  direction,
  note,
}: {
  label: string;
  value: number;
  direction: "in" | "out";
  note?: string;
}) {
  const Icon = direction === "in" ? ArrowUpRight : ArrowDownRight;
  const tone = direction === "in" ? "text-[var(--success-strong)]" : "text-[var(--error-strong)]";
  return (
    <div className="rounded-2xl bg-surface/70 border border-border-soft px-4 py-3">
      <div className="flex items-center gap-1.5">
        <Icon className={`w-3.5 h-3.5 ${tone}`} />
        <p className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
          {label}
        </p>
      </div>
      <p className="mt-1 text-lg font-[900] text-text-primary tracking-tight">
        {formatCurrency(value)}
      </p>
      {note && (
        <p className="mt-0.5 text-[11px] font-semibold text-text-tertiary">{note}</p>
      )}
    </div>
  );
}
