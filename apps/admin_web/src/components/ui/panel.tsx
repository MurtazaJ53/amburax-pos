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
  /** Anything else for the header's trailing slot - a pager, a toggle. Used
   *  instead of `action` when the control is not a link. */
  actionSlot?: ReactNode;
  /** Scroll the panel's BODY instead of the page.
   *
   *  The dashboard holds still while its lists move: a shopkeeper looking up
   *  one figure should not lose the takings off the top of the screen to
   *  reach the alert underneath. The header stays put and only the content
   *  below it scrolls. */
  scrollBody?: boolean;
  /** A line pinned below the scrolling body - a caption, a count. Inside the
   *  scroll area it gets clipped half-drawn at the fold, which reads as a
   *  rendering fault rather than as something to scroll to. */
  footer?: ReactNode;
  children: ReactNode;
  className?: string;
};

export function Panel({
  title,
  count,
  countTone = "neutral",
  action,
  actionSlot,
  scrollBody = false,
  footer,
  children,
  className = "",
}: PanelProps) {
  return (
    <section
      className={`rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm ${
        scrollBody ? "flex min-h-0 flex-col overflow-hidden" : ""
      } ${className}`}
    >
      <div className="mb-3.5 flex shrink-0 items-center gap-2.5">
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
        {actionSlot && <div className="ml-auto shrink-0">{actionSlot}</div>}
      </div>
      {/* The scroll container is a separate element from the layout one on
          purpose: giving a single element the flex sizing AND the scrolling
          collapses its rows to nothing. */}
      {scrollBody ? (
        <div className="no-scrollbar min-h-0 flex-1 overflow-y-auto">{children}</div>
      ) : (
        children
      )}
      {footer && <div className="mt-2.5 shrink-0">{footer}</div>}
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
