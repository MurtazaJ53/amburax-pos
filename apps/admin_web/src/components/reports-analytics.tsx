"use client";

import { useCallback, useEffect, useState } from "react";
import { BarChart3, Download, FileSpreadsheet, Loader2, PieChart } from "lucide-react";

import { formatCurrency } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



/**
 * Real P&L and GST figures from the backend.
 *
 * These numbers get read to an accountant and filed with the tax portal, so
 * anything this screen cannot prove it must refuse to show rather than
 * estimate.
 */

type ProfitAndLoss = {
  start: string;
  end: string;
  revenue: string;
  tax_collected: string;
  /** Revenue less the GST held for the tax office. Profit is measured from
   *  this, not from revenue, and showing it is what makes the column add up. */
  net_revenue: string;
  cost_of_goods_sold: string;
  gross_profit: string;
  total_expenses: string;
  net_profit: string;
  net_margin_pct: string;
  purchases_total: string;
};

type GstRateRow = {
  "items__gst_rate": string | null;
  taxable_amount: string;
  tax_amount: string;
  cgst_amount: string;
  sgst_amount: string;
  igst_amount: string;
};

type GstSummary = {
  taxable_amount: string;
  tax_amount: string;
  cgst_amount: string;
  sgst_amount: string;
  igst_amount: string;
  gross_amount: string;
  b2c_small: GstRateRow[];
  hsn_summary: Record<string, string | null>[];
};

function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

function startOfMonth(): string {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

export function ReportsAnalytics() {
  const [start, setStart] = useState(startOfMonth());
  const [end, setEnd] = useState(today());
  const [tab, setTab] = useState<"pnl" | "gst">("pnl");

  const [pnl, setPnl] = useState<ProfitAndLoss | null>(null);
  const [gst, setGst] = useState<GstSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [pnlError, setPnlError] = useState<string | null>(null);
  const [gstError, setGstError] = useState<string | null>(null);
  const [downloading, setDownloading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setPnlError(null);
    setGstError(null);

    // P&L is admin-only while the GST summary is not, so they fail separately.
    const [pnlRes, gstRes] = await Promise.allSettled([
      fetch(`/api/reports/profit-loss?start=${start}&end=${end}`),
      fetch(`/api/reports/gst-summary?date_from=${start}&date_to=${end}`),
    ]);

    if (pnlRes.status === "fulfilled" && pnlRes.value.ok) {
      setPnl(await pnlRes.value.json());
    } else {
      setPnl(null);
      const status = pnlRes.status === "fulfilled" ? pnlRes.value.status : 0;
      setPnlError(
        status === 403
          ? "Profit and loss is limited to owners and admins."
          : `Could not load profit and loss${status ? ` (${status})` : ""}.`
      );
    }

    if (gstRes.status === "fulfilled" && gstRes.value.ok) {
      setGst(await gstRes.value.json());
    } else {
      setGst(null);
      const status = gstRes.status === "fulfilled" ? gstRes.value.status : 0;
      setGstError(`Could not load the GST summary${status ? ` (${status})` : ""}.`);
    }

    setLoading(false);
  }, [start, end]);

  useEffect(() => {
    void load();
  }, [load]);

  const downloadGstr1 = async () => {
    setDownloading(true);
    setGstError(null);
    try {
      const res = await fetch(`/api/reports/gstr1?date_from=${start}&date_to=${end}`);
      if (res.status === 403) {
        throw new Error("Filing exports are limited to owners and admins.");
      }
      if (!res.ok) throw new Error(`Export failed (${res.status})`);

      const disposition = res.headers.get("content-disposition") || "";
      const match = disposition.match(/filename="?([^"]+)"?/);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = match?.[1] || `GSTR1_${start}_${end}.json`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      setGstError(errorMessage(err, "Could not build the export."));
    } finally {
      setDownloading(false);
    }
  };

  const rangeIsBackwards = start > end;
  const costsIncomplete = pnl
    ? num(pnl.cost_of_goods_sold) <= 0 && num(pnl.revenue) > 0
    : false;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-wrap items-end gap-3">
          <label className="block">
            <span className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
              From
            </span>
            <input
              type="date"
              value={start}
              max={end}
              onChange={(e) => setStart(e.target.value)}
              className="mt-1.5 block rounded-xl border border-border-soft bg-surface px-3 py-2 text-sm font-bold text-text-primary"
            />
          </label>
          <label className="block">
            <span className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
              To
            </span>
            <input
              type="date"
              value={end}
              min={start}
              onChange={(e) => setEnd(e.target.value)}
              className="mt-1.5 block rounded-xl border border-border-soft bg-surface px-3 py-2 text-sm font-bold text-text-primary"
            />
          </label>
        </div>
        <div className="inline-flex rounded-2xl border border-border-soft bg-surface p-1">
          <button
            type="button"
            onClick={() => setTab("pnl")}
            className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-extrabold ${
              tab === "pnl"
                ? "bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20"
                : "text-text-secondary hover:text-text-primary"
            }`}
          >
            <BarChart3 className="w-3.5 h-3.5" />
            Profit &amp; loss
          </button>
          <button
            type="button"
            onClick={() => setTab("gst")}
            className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-extrabold ${
              tab === "gst"
                ? "bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20"
                : "text-text-secondary hover:text-text-primary"
            }`}
          >
            <PieChart className="w-3.5 h-3.5" />
            GST
          </button>
        </div>
      </div>

      {rangeIsBackwards && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          The start date is after the end date.
        </div>
      )}

      {loading && !pnl && !gst ? (
        <div className="rounded-[28px] border border-border-soft bg-surface px-6 py-12 text-center text-sm font-semibold text-text-secondary">
          Loading&hellip;
        </div>
      ) : tab === "pnl" ? (
        pnlError ? (
          <div className="rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-5 py-4 text-sm font-semibold text-text-secondary">
            {pnlError}
          </div>
        ) : (
          pnl && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <Figure label="Revenue" value={num(pnl.revenue)} />
                <Figure
                  label="Cost of goods sold"
                  value={num(pnl.cost_of_goods_sold)}
                  tone="negative"
                />
                <Figure
                  label="Gross profit"
                  value={num(pnl.gross_profit)}
                  tone="positive"
                />
                <Figure
                  label="Net profit"
                  value={num(pnl.net_profit)}
                  tone={num(pnl.net_profit) >= 0 ? "positive" : "negative"}
                  detail={`${num(pnl.net_margin_pct).toFixed(2)}% margin`}
                />
              </div>

              <div className="rounded-[16px] border border-border-soft bg-surface overflow-hidden">
                <table className="min-w-full border-collapse">
                  <tbody>
                    {/* The tax line sits IN the column, not below it as a
                        footnote. Profit is measured from revenue net of GST -
                        the backend is explicit about that and hands over
                        net_revenue so the arithmetic can be followed - but
                        the table jumped straight from a tax-inclusive revenue
                        to a subtraction, so the figures on screen did not add
                        up. A shopkeeper checking the column with a pen was
                        right to distrust it. */}
                    <Row label="Revenue" value={num(pnl.revenue)} />
                    <Row
                      label="Less: GST collected (held for the tax office)"
                      value={-num(pnl.tax_collected)}
                    />
                    <Row label="Net revenue" value={num(pnl.net_revenue)} />
                    <Row
                      label="Less: cost of goods sold"
                      value={-num(pnl.cost_of_goods_sold)}
                    />
                    <Row label="Gross profit" value={num(pnl.gross_profit)} strong />
                    <Row label="Less: expenses" value={-num(pnl.total_expenses)} />
                    <Row label="Net profit" value={num(pnl.net_profit)} strong />
                    <Row
                      label="Stock purchased (cash out, not a P&amp;L expense)"
                      value={num(pnl.purchases_total)}
                      muted
                    />
                  </tbody>
                </table>
              </div>

              {costsIncomplete && (
                <div className="rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-5 py-4 text-xs font-semibold text-text-secondary">
                  No cost prices were recorded on the bills in this range, so cost of
                  goods sold is zero and gross profit is overstated. Add cost prices
                  in Stock for a true margin.
                </div>
              )}
            </div>
          )
        )
      ) : gstError ? (
        <div className="rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-5 py-4 text-sm font-semibold text-text-secondary">
          {gstError}
        </div>
      ) : (
        gst && (
          <div className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              <Figure label="Taxable value" value={num(gst.taxable_amount)} />
              <Figure label="CGST" value={num(gst.cgst_amount)} />
              <Figure label="SGST" value={num(gst.sgst_amount)} />
              <Figure label="IGST" value={num(gst.igst_amount)} />
            </div>

            <div className="rounded-[16px] border border-border-soft bg-surface overflow-hidden">
              <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-5 border-b border-border-soft">
                <h2 className="text-sm font-black text-text-primary uppercase tracking-wide">
                  By tax rate
                </h2>
                <button
                  type="button"
                  onClick={() => void downloadGstr1()}
                  disabled={downloading || rangeIsBackwards}
                  className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-4 py-2 text-xs font-extrabold text-[var(--primary-dark)] disabled:opacity-50 border border-[var(--primary)]/25"
                >
                  {downloading ? (
                    <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  ) : (
                    <Download className="w-3.5 h-3.5" />
                  )}
                  Download GSTR-1
                </button>
              </div>

              {gst.b2c_small.length === 0 ? (
                <div className="px-6 py-12 text-center">
                  <FileSpreadsheet className="w-8 h-8 mx-auto text-text-tertiary" />
                  <p className="mt-3 text-sm font-bold text-text-primary">
                    No taxable sales in this range
                  </p>
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="min-w-full border-collapse">
                    <thead>
                      <tr className="border-b border-border-soft text-left text-[11px] uppercase tracking-wider text-text-tertiary">
                        <th className="px-6 py-3 font-extrabold">Rate</th>
                        <th className="px-6 py-3 font-extrabold text-right">Taxable</th>
                        <th className="px-6 py-3 font-extrabold text-right">CGST</th>
                        <th className="px-6 py-3 font-extrabold text-right">SGST</th>
                        <th className="px-6 py-3 font-extrabold text-right">IGST</th>
                        <th className="px-6 py-3 font-extrabold text-right">Total tax</th>
                      </tr>
                    </thead>
                    <tbody>
                      {gst.b2c_small.map((row, index) => (
                        <tr
                          key={index}
                          className="border-b border-border-soft/60 last:border-0"
                        >
                          <td className="px-6 py-4 text-sm font-bold text-text-primary">
                            {num(row["items__gst_rate"]).toFixed(2)}%
                          </td>
                          <td className="px-6 py-4 text-right text-sm font-semibold text-text-secondary">
                            {formatCurrency(num(row.taxable_amount))}
                          </td>
                          <td className="px-6 py-4 text-right text-sm font-semibold text-text-secondary">
                            {formatCurrency(num(row.cgst_amount))}
                          </td>
                          <td className="px-6 py-4 text-right text-sm font-semibold text-text-secondary">
                            {formatCurrency(num(row.sgst_amount))}
                          </td>
                          <td className="px-6 py-4 text-right text-sm font-semibold text-text-secondary">
                            {formatCurrency(num(row.igst_amount))}
                          </td>
                          <td className="px-6 py-4 text-right text-sm font-extrabold text-text-primary">
                            {formatCurrency(num(row.tax_amount))}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            <p className="text-xs font-semibold text-text-tertiary">
              Voided bills are excluded, and returns are deducted from these
              figures and the tables below, including part returns. The GSTR-1
              CSV lists invoices as they were issued — returns belong there as
              credit notes, which it does not yet produce, so your accountant
              must enter them. Check these figures against your books before
              filing — this is a summary of what was billed, not tax advice.
            </p>
          </div>
        )
      )}
    </div>
  );
}

function Figure({
  label,
  value,
  detail,
  tone = "neutral",
}: {
  label: string;
  value: number;
  detail?: string;
  tone?: "neutral" | "positive" | "negative";
}) {
  const colour =
    tone === "positive"
      ? "text-[var(--success-strong)]"
      : tone === "negative"
        ? "text-[var(--error-strong)]"
        : "text-text-primary";
  return (
    <div className="rounded-[24px] border border-border-soft bg-surface p-5">
      <p className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
        {label}
      </p>
      <p className={`mt-1 text-2xl font-[900] tracking-tight ${colour}`}>
        {formatCurrency(value)}
      </p>
      {detail && (
        <p className="mt-1 text-[11px] font-semibold text-text-secondary">{detail}</p>
      )}
    </div>
  );
}

function Row({
  label,
  value,
  strong = false,
  muted = false,
}: {
  label: string;
  value: number;
  strong?: boolean;
  muted?: boolean;
}) {
  return (
    <tr className="border-b border-border-soft/60 last:border-0">
      <td
        className={`px-6 py-3.5 text-sm ${
          strong ? "font-black text-text-primary" : "font-semibold text-text-secondary"
        }`}
      >
        {label}
      </td>
      <td
        className={`px-6 py-3.5 text-right text-sm ${
          muted
            ? "font-semibold text-text-tertiary"
            : strong
              ? "font-[900] text-text-primary"
              : "font-bold text-text-primary"
        }`}
      >
        {formatCurrency(value)}
      </td>
    </tr>
  );
}
