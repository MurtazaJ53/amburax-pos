"use client";

import { useCallback, useEffect, useState } from "react";
import { Copy, RefreshCw, Share2 } from "lucide-react";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

type DayBook = {
  date: string;
  shop_name: string;
  currency_code: string;
  jama: {
    cash: string;
    upi: string;
    card: string;
    bank: string;
    other: string;
    khata_repayments: string;
    total: string;
  };
  udhaar: { credit_given: string; customers: number };
  money_out: { expenses: string };
  cash_in_hand: string;
  sales_count: number;
  summary_text: string;
};

function money(value: string | number, currency: string): string {
  const n = typeof value === "number" ? value : parseFloat(String(value ?? "0"));
  const safe = Number.isFinite(n) ? n : 0;
  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: currency || "INR",
      maximumFractionDigits: 2,
    }).format(safe);
  } catch {
    return `₹${safe.toFixed(2)}`;
  }
}

/**
 * The day's Roj Mel, in the two columns a shopkeeper already keeps on paper.
 *
 * Jama is money actually received; Udhaar is value handed over on credit and
 * still owed. Keeping them side by side is the point — a day of strong sales
 * and weak collection reads as healthy on a single revenue figure, and that is
 * exactly the day worth noticing.
 */
export function DayBook({ upiVpa: _upiVpa = "" }: { upiVpa?: string }) {
  const today = new Date().toISOString().slice(0, 10);
  const [date, setDate] = useState(today);
  const [data, setData] = useState<DayBook | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/reports/day-book?date=${date}`);
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || `Could not load the day book (${res.status})`);
      }
      setData(await res.json());
    } catch (err) {
      setData(null);
      setError(errorMessage(err, "Something went wrong loading the day book."));
    } finally {
      setLoading(false);
    }
  }, [date]);

  useEffect(() => {
    void load();
  }, [load]);

  const copy = async () => {
    if (!data) return;
    try {
      await navigator.clipboard.writeText(data.summary_text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setError("Could not copy. Select the summary text and copy it manually.");
    }
  };

  const share = () => {
    if (!data) return;
    // wa.me with no number opens WhatsApp's contact picker, so the owner
    // chooses where it goes. Sending unattended needs the Business API.
    window.open(
      `https://wa.me/?text=${encodeURIComponent(data.summary_text)}`,
      "_blank",
      "noopener,noreferrer",
    );
  };

  const c = data?.currency_code ?? "INR";

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <input
          type="date"
          value={date}
          max={today}
          onChange={(e) => setDate(e.target.value)}
          className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] px-4 py-2.5 text-sm font-bold text-[var(--text-primary)]"
        />
        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="inline-flex items-center gap-2 rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2 text-xs font-extrabold text-[var(--text-secondary)] hover:text-[var(--text-primary)] disabled:opacity-50"
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
        <>
          <div className="grid gap-4 sm:grid-cols-2">
            {/* Jama — money in */}
            <section className="rounded-[24px] border border-[var(--success)]/30 bg-[var(--success)]/5 p-5">
              <h3 className="text-[10px] font-extrabold uppercase tracking-[0.12em] text-[var(--success-strong)]">
                Jama · received
              </h3>
              <p className="mt-1 text-2xl font-[900] tracking-tight text-[var(--text-primary)]">
                {money(data.jama.total, c)}
              </p>
              <dl className="mt-3.5 space-y-1.5 text-xs">
                {[
                  ["Cash", data.jama.cash],
                  ["UPI", data.jama.upi],
                  ["Card", data.jama.card],
                  ["Bank", data.jama.bank],
                  ["Khata repayments", data.jama.khata_repayments],
                ].map(([label, value]) => (
                  <div key={label} className="flex justify-between gap-3">
                    <dt className="font-semibold text-[var(--text-secondary)]">{label}</dt>
                    <dd className="font-extrabold text-[var(--text-primary)] tabular-nums">
                      {money(value, c)}
                    </dd>
                  </div>
                ))}
              </dl>
            </section>

            {/* Udhaar — credit out */}
            <section className="rounded-[24px] border border-[var(--warning)]/30 bg-[var(--warning)]/5 p-5">
              <h3 className="text-[10px] font-extrabold uppercase tracking-[0.12em] text-[var(--warning-strong)]">
                Udhaar · given
              </h3>
              <p className="mt-1 text-2xl font-[900] tracking-tight text-[var(--text-primary)]">
                {money(data.udhaar.credit_given, c)}
              </p>
              <dl className="mt-3.5 space-y-1.5 text-xs">
                <div className="flex justify-between gap-3">
                  <dt className="font-semibold text-[var(--text-secondary)]">
                    Customers on credit
                  </dt>
                  <dd className="font-extrabold text-[var(--text-primary)] tabular-nums">
                    {data.udhaar.customers}
                  </dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="font-semibold text-[var(--text-secondary)]">Expenses</dt>
                  <dd className="font-extrabold text-[var(--text-primary)] tabular-nums">
                    {money(data.money_out.expenses, c)}
                  </dd>
                </div>
                <div className="flex justify-between gap-3 border-t border-[var(--border-soft)] pt-1.5">
                  <dt className="font-semibold text-[var(--text-secondary)]">
                    Cash in hand
                  </dt>
                  <dd className="font-extrabold text-[var(--text-primary)] tabular-nums">
                    {money(data.cash_in_hand, c)}
                  </dd>
                </div>
              </dl>
            </section>
          </div>

          <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h3 className="text-sm font-extrabold text-[var(--text-primary)]">
                Summary to send
              </h3>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => void copy()}
                  className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--border)] px-3.5 py-2 text-xs font-extrabold text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                >
                  <Copy className="w-3.5 h-3.5" />
                  {copied ? "Copied" : "Copy"}
                </button>
                <button
                  type="button"
                  onClick={share}
                  className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--primary)] px-3.5 py-2 text-xs font-extrabold text-white hover:bg-[var(--primary-hover)]"
                >
                  <Share2 className="w-3.5 h-3.5" />
                  WhatsApp
                </button>
              </div>
            </div>
            <pre className="mt-3 whitespace-pre-wrap font-mono text-[11px] leading-relaxed text-[var(--text-secondary)]">
              {data.summary_text}
            </pre>
            <p className="mt-2 text-[10px] font-semibold text-[var(--text-tertiary)]">
              {data.sales_count} bill{data.sales_count === 1 ? "" : "s"} on{" "}
              {new Date(data.date).toLocaleDateString("en-IN", {
                day: "numeric",
                month: "long",
                year: "numeric",
              })}
            </p>
          </div>
        </>
      )}
    </div>
  );
}
