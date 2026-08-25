"use client";

import { useEffect, useRef, useState } from "react";
import { CalendarDays, ChevronDown } from "lucide-react";

import { RANGE_OPTIONS, isValidRange, resolveRange } from "@/lib/date-ranges";
import type { DateRange, RangeKey } from "@/lib/date-ranges";

type Props = {
  value: RangeKey;
  custom: DateRange;
  /** Shop-local today, YYYY-MM-DD. Caps the pickers so no future date is
   *  offered - a shop cannot have taken money tomorrow. */
  today: string;
  onChange: (key: RangeKey, custom: DateRange) => void;
  className?: string;
};

/** The period control, shared by every screen that asks about one.
 *
 *  Extracted so History and the dashboard cannot drift apart: two copies of a
 *  date menu become two different lists of presets, and then two different
 *  answers to "last month".
 */
export function DateRangePicker({ value, custom, today, onChange, className = "" }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const range = resolveRange(value, today, custom);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: MouseEvent) => {
      if (!ref.current?.contains(event.target as Node)) setOpen(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    // z-40 while open so the menu clears anything drawn beside it. Clearing
    // what is drawn BELOW it is the ancestor's job: a card animating its
    // transform makes a stacking context the menu cannot escape.
    <div ref={ref} className={`relative ${open ? "z-40" : ""} ${className}`}>
      <button
        type="button"
        onClick={() => setOpen((current) => !current)}
        aria-expanded={open}
        aria-haspopup="menu"
        className="focus-ring inline-flex w-full cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-base)] px-3 py-2 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)]"
      >
        <CalendarDays className="h-3.5 w-3.5 shrink-0" />
        {range.label}
        <ChevronDown
          className={`ml-auto h-3.5 w-3.5 shrink-0 transition-transform duration-200 ${
            open ? "rotate-180" : ""
          }`}
        />
      </button>

      {open && (
        <div
          role="menu"
          className="animate-fade-in-up absolute right-0 z-30 mt-1.5 w-[230px] rounded-[12px] border border-[var(--border-soft)] bg-[var(--surface)] p-1.5 shadow-lg"
        >
          {RANGE_OPTIONS.map((option) => (
            <button
              key={option.key}
              type="button"
              role="menuitemradio"
              aria-checked={value === option.key}
              onClick={() => {
                onChange(option.key, custom);
                // The custom row stays open: it has fields still to fill in.
                if (option.key !== "custom") setOpen(false);
              }}
              className={`focus-ring block w-full cursor-pointer rounded-[8px] px-3 py-2 text-left text-[12px] font-bold transition-colors ${
                value === option.key
                  ? "bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                  : "text-[var(--text-secondary)] hover:bg-[var(--bg-base)] hover:text-[var(--text-primary)]"
              }`}
            >
              {option.label}
            </button>
          ))}

          {value === "custom" && (
            <div className="mt-1.5 border-t border-[var(--border-soft)] px-1.5 pt-2">
              <label className="block text-[10px] font-bold uppercase tracking-wide text-[var(--text-tertiary)]">
                From
                <input
                  type="date"
                  value={custom.from}
                  max={today}
                  onChange={(e) => onChange("custom", { ...custom, from: e.target.value })}
                  className="focus-ring mt-1 w-full rounded-[8px] border border-[var(--border-soft)] bg-[var(--bg-soft)] px-2 py-1.5 font-mono text-[11.5px] font-bold text-[var(--text-primary)] outline-none"
                />
              </label>
              <label className="mt-2 block text-[10px] font-bold uppercase tracking-wide text-[var(--text-tertiary)]">
                To
                <input
                  type="date"
                  value={custom.to}
                  max={today}
                  onChange={(e) => onChange("custom", { ...custom, to: e.target.value })}
                  className="focus-ring mt-1 w-full rounded-[8px] border border-[var(--border-soft)] bg-[var(--bg-soft)] px-2 py-1.5 font-mono text-[11.5px] font-bold text-[var(--text-primary)] outline-none"
                />
              </label>
              <p className="m-0 mt-2 text-[10.5px] font-medium text-[var(--text-tertiary)]">
                {isValidRange(custom) ? range.label : "Pick both dates to see the period."}
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
