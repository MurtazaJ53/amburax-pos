"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { ChevronLeft, ChevronRight, Copy, RefreshCw, Share2 } from "lucide-react";

import { addDays, shopDateKey } from "@/lib/dashboard-metrics";

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

function amount(value: string | undefined): number {
  const n = parseFloat(String(value ?? "0"));
  return Number.isFinite(n) ? n : 0;
}

/** The jama split, in a fixed order so the bar never reshuffles. */
const JAMA_ROWS = [
  { key: "cash", label: "Cash", color: "var(--success)" },
  { key: "upi", label: "UPI", color: "var(--primary-bright)" },
  { key: "card", label: "Card", color: "var(--violet-strong)" },
  { key: "bank", label: "Bank", color: "var(--info)" },
  { key: "khata_repayments", label: "Khata repayments", color: "var(--warning)" },
] as const;

/**
 * The day's Roj Mel, in the two columns a shopkeeper already keeps on paper.
 *
 * Jama is money actually received; Udhaar is value handed over on credit and
 * still owed. Keeping them side by side is the point — a day of strong sales
 * and weak collection reads as healthy on a single revenue figure, and that is
 * exactly the day worth noticing.
 */
export function DayBook({
  upiVpa: _upiVpa = "",
  timeZone = "Asia/Kolkata",
}: {
  upiVpa?: string;
  /** The shop's own clock. Without it a Kolkata shop billing after 6:30 PM
   *  local — when UTC is still on the previous date — would open the book on
   *  yesterday, because toISOString() reports UTC. */
  timeZone?: string;
}) {
  const today = useMemo(() => shopDateKey(new Date(), timeZone), [timeZone]);
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
      setError(errorMessage(err, "Could not load the day book."));
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
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setError("Could not copy the summary. Select the text and copy it by hand.");
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
  const isToday = date === today;

  const jamaSegments = useMemo(() => {
    if (!data) return [];
    return JAMA_ROWS.map((row) => ({
      ...row,
      value: amount(data.jama[row.key]),
    })).filter((row) => row.value > 0);
  }, [data]);

  const jamaTotal = jamaSegments.reduce((sum, row) => sum + row.value, 0);

  return (
    <div className="flex flex-col gap-4">
      {/* Step through days. A date picker is three taps to answer "and
          yesterday?", which is the question this screen gets asked most. */}
      <div className="flex flex-wrap items-center gap-2.5 animate-fade-in-up">
        <div className="flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => setDate(addDays(date, -1))}
            aria-label="Previous day"
            className="focus-ring grid h-9 w-9 cursor-pointer place-items-center rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-hover)]"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>

          <input
            type="date"
            value={date}
            max={today}
            onChange={(e) => setDate(e.target.value)}
            aria-label="Day book date"
            className="rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2 font-mono text-[12.5px] font-bold text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
          />

          <button
            type="button"
            onClick={() => setDate(addDays(date, 1))}
            disabled={isToday}
            aria-label="Next day"
            className="focus-ring grid h-9 w-9 cursor-pointer place-items-center rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-hover)] disabled:cursor-not-allowed disabled:opacity-40"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        {!isToday && (
          <button
            type="button"
            onClick={() => setDate(today)}
            className="focus-ring cursor-pointer rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2 text-[12.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
          >
            Today
          </button>
        )}

        {data && (
          <span className="font-mono text-[11px] font-medium text-[var(--text-tertiary)]">
            {data.sales_count} {data.sales_count === 1 ? "bill" : "bills"}
          </span>
        )}

        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="focus-ring ml-auto inline-flex cursor-pointer items-center gap-2 rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2 text-[12.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)] disabled:opacity-50"
        >
          <RefreshCw className={`h-3.5 w-3.5 ${loading ? "animate-spin" : ""}`} />
          Refresh
        </button>
      </div>

      {error && (
        <div className="rounded-[16px] border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {loading && !data && (
        <div className="grid gap-3.5 sm:grid-cols-2">
          {[0, 1].map((i) => (
            <div
              key={i}
              className="h-52 animate-pulse rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface-strong)]"
            />
          ))}
        </div>
      )}

      {data && (
        <>
          <div className="grid gap-3.5 sm:grid-cols-2">
            {/* Jama — money actually received */}
            <section className="rounded-[20px] border border-[var(--success)]/40 bg-[var(--success)]/10 p-5 animate-fade-in-up delay-1">
              <h3 className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--success-strong)]">
                Jama · received
              </h3>
              <p className="tnum mt-1.5 font-mono text-[30px] font-bold leading-none tracking-tight text-[var(--success-strong)]">
                {money(data.jama.total, c)}
              </p>

              {jamaTotal > 0 && (
                <div
                  className="mt-3.5 flex h-2 gap-0.5"
                  role="img"
                  aria-label={`Split: ${jamaSegments
                    .map((row) => `${row.label} ${money(row.value, c)}`)
                    .join(", ")}`}
                >
                  {jamaSegments.map((row) => (
                    <span
                      key={row.key}
                      className="block rounded-full"
                      style={{ flex: row.value, background: row.color }}
                    />
                  ))}
                </div>
              )}

              <dl className="mt-3.5 space-y-1.5">
                {JAMA_ROWS.map((row) => {
                  const value = amount(data.jama[row.key]);
                  return (
                    <div key={row.key} className="flex items-center gap-2.5">
                      <span
                        className="block h-2 w-2 flex-none rounded-[3px]"
                        style={{ background: value > 0 ? row.color : "var(--border)" }}
                        aria-hidden="true"
                      />
                      <dt className="text-[12.5px] font-semibold text-[var(--text-secondary)]">
                        {row.label}
                      </dt>
                      <dd className="tnum ml-auto font-mono text-[12.5px] font-bold text-[var(--text-primary)]">
                        {money(value, c)}
                      </dd>
                    </div>
                  );
                })}
              </dl>
            </section>

            {/* Udhaar — value handed over and still owed */}
            <section className="flex flex-col rounded-[20px] border border-[var(--warning)]/40 bg-[var(--warning)]/10 p-5 animate-fade-in-up delay-2">
              <h3 className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--warning-strong)]">
                Udhaar · given
              </h3>
              <p className="tnum mt-1.5 font-mono text-[30px] font-bold leading-none tracking-tight text-[var(--warning-strong)]">
                {money(data.udhaar.credit_given, c)}
              </p>

              <dl className="mt-4 space-y-1.5">
                <div className="flex items-center gap-3">
                  <dt className="text-[12.5px] font-semibold text-[var(--text-secondary)]">
                    Customers on credit
                  </dt>
                  <dd className="tnum ml-auto font-mono text-[12.5px] font-bold text-[var(--text-primary)]">
                    {data.udhaar.customers}
                  </dd>
                </div>
                <div className="flex items-center gap-3">
                  <dt className="text-[12.5px] font-semibold text-[var(--text-secondary)]">
                    Expenses paid out
                  </dt>
                  <dd className="tnum ml-auto font-mono text-[12.5px] font-bold text-[var(--text-primary)]">
                    {money(data.money_out.expenses, c)}
                  </dd>
                </div>
              </dl>

              {/* The number counted against the drawer at close. */}
              <div className="mt-auto rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] p-3.5">
                <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
                  Cash in hand
                </span>
                <p className="tnum mt-1 font-mono text-[22px] font-bold tracking-tight text-[var(--text-primary)]">
                  {money(data.cash_in_hand, c)}
                </p>
                <p className="mt-1 text-[11px] font-medium text-[var(--text-tertiary)]">
                  {money(data.jama.cash, c)} cash taken, less{" "}
                  {money(data.money_out.expenses, c)} paid out
                </p>
              </div>
            </section>
          </div>

          <div className="rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm animate-fade-in-up delay-3">
            <div className="flex flex-wrap items-center gap-2.5">
              <h3 className="text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
                Summary to send
              </h3>
              <span className="rounded-full border border-[var(--border-soft)] bg-[var(--bg-base)] px-2.5 py-1 text-[11px] font-bold text-[var(--text-secondary)]">
                {data.sales_count} {data.sales_count === 1 ? "bill" : "bills"} on{" "}
                {new Date(data.date).toLocaleDateString("en-IN", {
                  day: "numeric",
                  month: "short",
                })}
              </span>

              <div className="ml-auto flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => void copy()}
                  className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2 text-[12px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
                >
                  <Copy className="h-3.5 w-3.5" />
                  {copied ? "Copied" : "Copy"}
                </button>
                <button
                  type="button"
                  onClick={share}
                  className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] bg-[var(--success)] px-3.5 py-2 text-[12px] font-bold text-white transition-colors hover:bg-[var(--success-dark)]"
                >
                  <Share2 className="h-3.5 w-3.5" />
                  WhatsApp
                </button>
              </div>
            </div>

            <pre className="mt-3 overflow-x-auto whitespace-pre-wrap rounded-[14px] border border-dashed border-[var(--border)] bg-[var(--bg-base)] px-4 py-3.5 font-mono text-[11.5px] leading-[1.75] text-[var(--text-secondary)]">
              {data.summary_text}
            </pre>
          </div>
        </>
      )}
    </div>
  );
}
