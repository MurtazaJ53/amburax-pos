import Link from "next/link";
import type { ReactNode } from "react";

/**
 * A single figure with its context: what it is, what it's worth, and how to
 * read it. The note line carries the comparison — a number with nothing to
 * judge it against is the thing this replaces.
 */

export type StatTone = "neutral" | "good" | "warning" | "alert" | "brand";

const figureTone: Record<StatTone, string> = {
  neutral: "text-[var(--text-primary)]",
  brand: "text-[var(--primary-hover)]",
  good: "text-[var(--success-strong)]",
  warning: "text-[var(--warning-strong)]",
  alert: "text-[var(--error-strong)]",
};

const noteTone: Record<StatTone, string> = {
  neutral: "text-[var(--text-secondary)]",
  brand: "text-[var(--text-secondary)]",
  good: "text-[var(--success-strong)]",
  warning: "text-[var(--warning-strong)]",
  alert: "text-[var(--error-strong)]",
};

type StatTileProps = {
  label: string;
  value: string;
  note: string;
  href?: string;
  tone?: StatTone;
  noteToneOverride?: StatTone;
  /** Small trailing element: a trend bar strip, a chip, an icon. */
  trailing?: ReactNode;
  className?: string;
};

export function StatTile({
  label,
  value,
  note,
  href,
  tone = "neutral",
  noteToneOverride,
  trailing,
  className = "",
}: StatTileProps) {
  const body = (
    <>
      <div className="flex items-center justify-between gap-2">
        <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
          {label}
        </span>
        {trailing}
      </div>
      <p className={`tnum mt-2 font-mono text-[22px] font-bold tracking-tight ${figureTone[tone]}`}>
        {value}
      </p>
      <p className={`mt-0.5 text-[11.5px] font-semibold ${noteTone[noteToneOverride ?? tone]}`}>
        {note}
      </p>
    </>
  );

  const shell =
    "block rounded-[18px] border border-[var(--border-soft)] bg-[var(--surface)] p-4 shadow-sm";

  if (!href) {
    return <div className={`${shell} ${className}`}>{body}</div>;
  }

  return (
    <Link
      href={href}
      className={`${shell} hover-lift focus-ring cursor-pointer ${className}`}
    >
      {body}
    </Link>
  );
}

/**
 * Six bars of recent history, to anchor the figure above them. Values are
 * relative — this shows direction, not readable quantities, so it carries no
 * axis and is hidden from screen readers in favour of the note line.
 */
export function TrendBars({ values }: { values: number[] }) {
  const peak = Math.max(...values, 1);

  return (
    <span className="flex h-6 items-end gap-[2.5px]" aria-hidden="true">
      {values.map((value, index) => (
        <span
          key={index}
          className={`block w-1 rounded-[2px] ${
            index === values.length - 1 ? "bg-[var(--primary-bright)]" : "bg-[var(--border)]"
          }`}
          style={{ height: `${Math.max(3, (value / peak) * 24)}px` }}
        />
      ))}
    </span>
  );
}
