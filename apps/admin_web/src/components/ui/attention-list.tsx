import Link from "next/link";

/**
 * A prioritised queue of things the shop should act on, each with a verb.
 *
 * The severity stripe means the ranking survives a greyscale print and does
 * not depend on colour alone — the label text says the same thing.
 */

export type AttentionSeverity = "critical" | "warning" | "info";

export type AttentionItem = {
  id: string;
  severity: AttentionSeverity;
  title: string;
  body: string;
  cta: string;
  href: string;
};

const stripeTone: Record<AttentionSeverity, string> = {
  critical: "bg-[var(--error)]",
  warning: "bg-[var(--warning)]",
  info: "bg-[var(--primary)]",
};

const severityWord: Record<AttentionSeverity, string> = {
  critical: "Urgent",
  warning: "Soon",
  info: "For information",
};

export function AttentionList({ items }: { items: AttentionItem[] }) {
  return (
    <ul className="flex list-none flex-col gap-2 p-0 m-0">
      {items.map((item, index) => (
        <li key={item.id}>
          <Link
            href={item.href}
            className="hover-nudge focus-ring group flex items-start gap-3 rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-2.5 hover:border-[var(--border)] animate-fade-in-up"
            style={{ animationDelay: `${200 + index * 40}ms` }}
          >
            <span
              className={`w-[3px] self-stretch rounded-full ${stripeTone[item.severity]}`}
              aria-hidden="true"
            />
            <span className="min-w-0 flex-1">
              <span className="block text-[12.5px] font-extrabold tracking-tight text-[var(--text-primary)]">
                <span className="sr-only">{severityWord[item.severity]}: </span>
                {item.title}
              </span>
              {/* Two lines, not one clipped line. The body is where the
                  actual number lives - "267 products are already at zero
                  stock" truncated to "...before the n" tells nobody
                  anything, and the panel has the room. */}
              <span className="mt-0.5 line-clamp-2 block text-[11px] font-medium leading-[1.45] text-[var(--text-secondary)]">
                {item.body}
              </span>
            </span>
            <span className="flex-none self-center whitespace-nowrap rounded-lg border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 text-[11px] font-bold text-[var(--text-secondary)] transition-colors group-hover:border-[var(--primary)] group-hover:bg-[var(--primary)] group-hover:text-white">
              {item.cta}
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}
