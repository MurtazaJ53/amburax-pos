import Link from "next/link";
import type { ReactNode } from "react";

/**
 * The standard content container for a redesigned screen: a titled card with
 * an optional count badge and one trailing action. Every list, table and
 * chart block on the new screens sits in one of these, so spacing and
 * heading weight stay identical across the app.
 */

type PanelTone = "neutral" | "alert" | "warning" | "good";

const badgeTone: Record<PanelTone, string> = {
  neutral: "bg-[var(--bg-soft)] text-[var(--text-secondary)]",
  alert: "bg-[var(--error)]/10 text-[var(--error-strong)]",
  warning: "bg-[var(--warning)]/10 text-[var(--warning-strong)]",
  good: "bg-[var(--success)]/10 text-[var(--success-strong)]",
};

type PanelProps = {
  title: string;
  /** Small number beside the title, e.g. how many items need attention. */
  count?: number;
  countTone?: PanelTone;
  action?: { label: string; href: string };
  children: ReactNode;
  className?: string;
};

export function Panel({
  title,
  count,
  countTone = "neutral",
  action,
  children,
  className = "",
}: PanelProps) {
  return (
    <section
      className={`bg-[var(--surface)] border border-[var(--border-soft)] rounded-[20px] p-5 shadow-sm ${className}`}
    >
      <div className="flex items-center gap-2.5 mb-3.5">
        <h3 className="text-sm font-extrabold text-[var(--text-primary)] tracking-tight">
          {title}
        </h3>
        {count !== undefined && count > 0 && (
          <span
            className={`tnum rounded-md px-1.5 py-0.5 font-mono text-[10px] font-bold ${badgeTone[countTone]}`}
          >
            {count}
          </span>
        )}
        {action && (
          <Link
            href={action.href}
            className="ml-auto text-[11.5px] font-bold text-[var(--primary-hover)] hover:underline focus-ring"
          >
            {action.label}
          </Link>
        )}
      </div>
      {children}
    </section>
  );
}

/**
 * The dashed box a panel shows when it has nothing to list. Kept as its own
 * export so an empty Recent Sales and an empty Low Stock read identically.
 */
export function PanelEmpty({ children }: { children: ReactNode }) {
  return (
    <p className="rounded-2xl border border-dashed border-[var(--border-soft)] bg-[var(--bg-base)] py-10 text-center text-xs font-bold text-[var(--text-tertiary)]">
      {children}
    </p>
  );
}
