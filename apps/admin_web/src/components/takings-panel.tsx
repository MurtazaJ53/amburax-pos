"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CalendarDays, ChevronDown, Loader2, TrendingDown, TrendingUp } from "lucide-react";

import { MixBar } from "@/components/ui/mix-bar";
import type { MixSegment } from "@/components/ui/mix-bar";
import { Sparkline } from "@/components/ui/sparkline";
import {
  isValidRange,
  RANGE_OPTIONS,
  resolveRange,
  shopToday,
} from "@/lib/date-ranges";
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
  const [menuOpen, setMenuOpen] = useState(false);
  const [takings, setTakings] = useState<Takings>(EMPTY_TAKINGS);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState("");
  const menuRef = useRef<HTMLDivElement>(null);

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
      const res = await fetch(
        `/api/sales/takings?from=${range.from}&to=${range.to}`,
      );
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
  }, [range.from, range.to, ready]);

  useEffect(() => {
    void load();
  }, [load]);

  // Click-away, so the menu does not sit open over the figures.
  useEffect(() => {
    if (!menuOpen) return;
    const onPointerDown = (event: MouseEvent) => {
      if (!menuRef.current?.contains(event.target as Node)) setMenuOpen(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMenuOpen(false);
    };
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [menuOpen]);

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

        <div ref={menuRef} className="relative">
          <button
            type="button"
            onClick={() => setMenuOpen((open) => !open)}
            aria-expanded={menuOpen}
            aria-haspopup="menu"
            className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-base)] px-3 py-2 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)]"
          >
            <CalendarDays className="h-3.5 w-3.5" />
            {range.label}
            <ChevronDown
              className={`h-3.5 w-3.5 transition-transform duration-200 ${
                menuOpen ? "rotate-180" : ""
              }`}
            />
          </button>

          {menuOpen && (
            <div
              role="menu"
              className="animate-fade-in-up absolute right-0 z-30 mt-1.5 w-[220px] rounded-[12px] border border-[var(--border-soft)] bg-[var(--surface)] p-1.5 shadow-lg"
            >
              {RANGE_OPTIONS.map((option) => (
                <button
                  key={option.key}
                  type="button"
                  role="menuitemradio"
                  aria-checked={rangeKey === option.key}
                  onClick={() => {
                    setRangeKey(option.key);
                    if (option.key !== "custom") setMenuOpen(false);
                  }}
                  className={`focus-ring block w-full cursor-pointer rounded-[8px] px-3 py-2 text-left text-[12px] font-bold transition-colors ${
                    rangeKey === option.key
                      ? "bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                      : "text-[var(--text-secondary)] hover:bg-[var(--bg-base)] hover:text-[var(--text-primary)]"
                  }`}
                >
                  {option.label}
                </button>
              ))}

              {rangeKey === "custom" && (
                <div className="mt-1.5 border-t border-[var(--border-soft)] px-1.5 pt-2">
                  <label className="block text-[10px] font-bold uppercase tracking-wide text-[var(--text-tertiary)]">
                    From
                    <input
                      type="date"
                      value={custom.from}
                      max={today}
                      onChange={(e) =>
                        setCustom((prev) => ({ ...prev, from: e.target.value }))
                      }
                      className="focus-ring mt-1 w-full rounded-[8px] border border-[var(--border-soft)] bg-[var(--bg-soft)] px-2 py-1.5 font-mono text-[11.5px] font-bold text-[var(--text-primary)] outline-none"
                    />
                  </label>
                  <label className="mt-2 block text-[10px] font-bold uppercase tracking-wide text-[var(--text-tertiary)]">
                    To
                    <input
                      type="date"
                      value={custom.to}
                      max={today}
                      onChange={(e) =>
                        setCustom((prev) => ({ ...prev, to: e.target.value }))
                      }
                      className="focus-ring mt-1 w-full rounded-[8px] border border-[var(--border-soft)] bg-[var(--bg-soft)] px-2 py-1.5 font-mono text-[11.5px] font-bold text-[var(--text-primary)] outline-none"
                    />
                  </label>
                  <p className="m-0 mt-2 text-[10.5px] font-medium text-[var(--text-tertiary)]">
                    {ready ? range.label : "Pick both dates to see the period."}
                  </p>
                </div>
              )}
            </div>
          )}
        </div>
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
