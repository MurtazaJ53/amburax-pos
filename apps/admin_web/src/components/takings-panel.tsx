"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Loader2, TrendingDown, TrendingUp } from "lucide-react";

import { DateRangePicker } from "@/components/ui/date-range-picker";
import { MixBar } from "@/components/ui/mix-bar";
import type { MixSegment } from "@/components/ui/mix-bar";
import { Sparkline } from "@/components/ui/sparkline";
import { isValidRange, resolveRange, shopToday } from "@/lib/date-ranges";
import type { DateRange, RangeKey } from "@/lib/date-ranges";
import { formatCurrency } from "@/lib/formatters";
import {
  axisLabel,
  EMPTY_TAKINGS,
  peakLabel,
  peakPoint,
  percentChange,
  readTakings,
} from "@/lib/takings";
import type { Takings } from "@/lib/takings";

const MIX_COLORS: Record<string, string> = {
  CASH: "var(--success)",
  UPI: "var(--primary-bright)",
  CARD: "var(--primary)",
  BANK: "var(--primary-hover)",
  CREDIT: "var(--warning)",
  // Money still owed, and split bills whose tenders were never written. Both
  // are real parts of the total and neither is a payment method, so they read
  // as unresolved rather than borrowing a method's colour.
  UNPAID: "var(--error)",
  SPLIT: "var(--text-tertiary)",
  OTHER: "var(--text-tertiary)",
};

type Props = {
  currencyCode: string;
  timeZone: string;
};

/** Takings for whichever period the shopkeeper asks about.
 *
 *  A client component because the period is a question, not a fact of the
 *  page: changing it must not cost a full server round trip of the whole
 *  dashboard. Every figure still comes from the server — the browser chooses
 *  the window and nothing else.
 */
export function TakingsPanel({ currencyCode, timeZone }: Props) {
  const [rangeKey, setRangeKey] = useState<RangeKey>("today");
  const [custom, setCustom] = useState<DateRange>({ from: "", to: "" });
  const [takings, setTakings] = useState<Takings>(EMPTY_TAKINGS);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");

  const today = useMemo(() => shopToday(timeZone), [timeZone]);
  const range = useMemo(
    () => resolveRange(rangeKey, today, custom),
    [rangeKey, today, custom],
  );

  // A custom period is only asked for once BOTH ends are set. Fetching on the
  // first date would answer a question nobody finished asking.
  const ready = rangeKey !== "custom" || isValidRange(custom);

  const load = useCallback(async () => {
    if (!ready) return;
    setIsLoading(true);
    setError("");
    try {
      // All time has no start date, so it asks for itself by name rather
      // than sending an empty `from` the server would read as today.
      const query = range.unbounded
        ? "all=1"
        : `from=${range.from}&to=${range.to}`;
      const res = await fetch(`/api/sales/takings?${query}`);
      const body = await res.json().catch(() => null);
      if (!res.ok) {
        throw new Error(
          (body as { detail?: string })?.detail || "Could not load takings.",
        );
      }
      setTakings(readTakings(body));
    } catch (err) {
      // Empty figures, not stale ones. A total from the previous period under
      // a heading naming this one is the worst outcome here.
      setTakings(EMPTY_TAKINGS);
      setError(err instanceof Error ? err.message : "Could not load takings.");
    } finally {
      setIsLoading(false);
    }
  }, [range.from, range.to, range.unbounded, ready]);

  useEffect(() => {
    void load();
  }, [load]);


  const change = percentChange(takings.total, takings.previousTotal);
  const peak = peakPoint(takings.series);
  const segments: MixSegment[] = takings.mix.map((slice) => ({
    key: slice.key,
    label: slice.label,
    amount: slice.amount,
    color: MIX_COLORS[slice.key] ?? MIX_COLORS.OTHER,
  }));

  return (
    <div className="rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm animate-fade-in-up delay-1">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
          Takings
        </span>

        <DateRangePicker
          value={rangeKey}
          custom={custom}
          today={today}
          onChange={(key, next) => {
            setRangeKey(key);
            setCustom(next);
          }}
        />
      </div>

      <p className="tnum mt-2 flex items-center gap-2.5 font-mono text-[38px] font-bold leading-none tracking-tighter text-[var(--text-primary)] sm:text-[42px]">
        {formatCurrency(takings.total, currencyCode)}
        {isLoading && (
          <Loader2 className="h-4 w-4 animate-spin text-[var(--text-tertiary)]" />
        )}
      </p>

      <div className="mt-2.5 flex flex-wrap items-center gap-2">
        {change !== null && (
          <span
            className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11.5px] font-bold ${
              change >= 0
                ? "bg-[var(--success)]/10 text-[var(--success-strong)]"
                : "bg-[var(--error)]/10 text-[var(--error-strong)]"
            }`}
          >
            {change >= 0 ? (
              <TrendingUp className="h-3 w-3" />
            ) : (
              <TrendingDown className="h-3 w-3" />
            )}
            {Math.abs(change)}% {range.comparisonLabel}
          </span>
        )}
        {takings.billCount > 0 && (
          <span className="rounded-full border border-[var(--border-soft)] bg-[var(--bg-base)] px-2.5 py-1 text-[11.5px] font-bold text-[var(--text-secondary)]">
            {takings.billCount} {takings.billCount === 1 ? "bill" : "bills"} &middot; avg{" "}
            {formatCurrency(Math.round(takings.averageBill), currencyCode)}
          </span>
        )}
        {peak && (
          <span className="text-[11.5px] font-medium text-[var(--text-tertiary)]">
            {peakLabel(takings.granularity)} {axisLabel(peak.label, takings.granularity)}{" "}
            &middot; {formatCurrency(peak.amount, currencyCode)}
          </span>
        )}
      </div>

      {error ? (
        <p
          role="alert"
          className="mt-4 rounded-2xl border border-[var(--error)]/40 bg-[var(--error)]/10 px-4 py-3 text-xs font-bold text-[var(--error-strong)]"
        >
          {error}
        </p>
      ) : peak ? (
        <div className="mt-3.5">
          <Sparkline
            points={takings.series.map((point) => ({
              label: axisLabel(point.label, takings.granularity),
              amount: point.amount,
            }))}
            ariaLabel={`Takings for ${range.label}.`}
          />
          <div className="mt-1.5 flex justify-between font-mono text-[9.5px] font-medium tracking-wide text-[var(--text-tertiary)]">
            <span>{axisLabel(takings.series[0]?.label ?? "", takings.granularity)}</span>
            {takings.series.length > 2 && (
              <span>
                {axisLabel(
                  takings.series[Math.floor(takings.series.length / 2)].label,
                  takings.granularity,
                )}
              </span>
            )}
            <span>
              {axisLabel(
                takings.series[takings.series.length - 1]?.label ?? "",
                takings.granularity,
              )}
            </span>
          </div>
        </div>
      ) : (
        <p className="mt-4 rounded-2xl border border-dashed border-[var(--border-soft)] bg-[var(--bg-base)] py-7 text-center text-xs font-bold text-[var(--text-tertiary)]">
          {isLoading ? "Reading the period..." : `No bills in ${range.label.toLowerCase()}.`}
        </p>
      )}

      {segments.length > 0 && (
        <div className="mt-3.5 border-t border-dashed border-[var(--border-soft)] pt-3.5">
          <MixBar
            segments={segments}
            format={(amount) => formatCurrency(amount, currencyCode)}
            ariaLabel={`How the takings were paid: ${takings.mix
              .map((slice) => `${slice.label} ${formatCurrency(slice.amount, currencyCode)}`)
              .join(", ")}.`}
          />
        </div>
      )}
    </div>
  );
}
