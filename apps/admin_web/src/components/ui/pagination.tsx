"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";

/** Numbered pages for a long list.
 *
 *  Replaces "load older bills", which could only ever walk forward one page at
 *  a time. On nineteen thousand sales that is a button somebody presses forty
 *  times to reach last March, with no way back to where they were. A
 *  shopkeeper hunting a bill thinks in pages, not in "older".
 *
 *  The window slides rather than listing every page: at six hundred pages a
 *  full row of numbers is unreadable and unclickable. First and last stay
 *  reachable, the current page always sits inside the window, and gaps are
 *  drawn so nobody reads page 4 as following page 2.
 *
 *  Not to be confused with lib/paging.ts, which slices an array already in
 *  memory for a six-row preview panel. This one drives a server request.
 */

/** How many numbered buttons to show either side of the current page. */
const WINDOW = 2;

export function pagesToShow(page: number, pageCount: number): (number | "gap")[] {
  if (pageCount <= 7) {
    return Array.from({ length: pageCount }, (_, index) => index + 1);
  }

  const around = new Set<number>([1, pageCount, page]);
  for (let offset = 1; offset <= WINDOW; offset++) {
    if (page - offset > 1) around.add(page - offset);
    if (page + offset < pageCount) around.add(page + offset);
  }

  const sorted = [...around].sort((a, b) => a - b);
  const out: (number | "gap")[] = [];
  let previous = 0;
  for (const number of sorted) {
    // A gap only where pages are genuinely missing. "1 … 2" would be a lie
    // told to save one character.
    if (number - previous > 1) out.push("gap");
    out.push(number);
    previous = number;
  }
  return out;
}

export function Pagination({
  page,
  pageCount,
  onPage,
  busy = false,
  label = "bills",
  total,
}: {
  page: number;
  pageCount: number;
  onPage: (page: number) => void;
  busy?: boolean;
  /** What is being paged, for the count line and the screen reader. */
  label?: string;
  total?: number;
}) {
  if (pageCount <= 1) return null;

  const numbers = pagesToShow(page, pageCount);
  const go = (target: number) => {
    if (busy || target === page || target < 1 || target > pageCount) return;
    onPage(target);
  };

  return (
    <nav
      aria-label={`${label} pages`}
      className="flex flex-wrap items-center justify-between gap-3 pt-1"
    >
      {typeof total === "number" && (
        <p className="tnum text-[11.5px] font-bold text-[var(--text-tertiary)]">
          Page {page} of {pageCount} · {total.toLocaleString()} {label}
        </p>
      )}

      <div className="ml-auto flex items-center gap-1">
        <button
          type="button"
          onClick={() => go(page - 1)}
          disabled={busy || page === 1}
          aria-label="Previous page"
          className="focus-ring grid h-9 w-9 cursor-pointer place-items-center rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] transition-colors duration-200 hover:bg-[var(--bg-base)] hover:text-[var(--text-primary)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>

        {numbers.map((entry, index) =>
          entry === "gap" ? (
            <span
              key={`gap-${index}`}
              aria-hidden="true"
              className="px-1 text-[12px] font-bold text-[var(--text-tertiary)]"
            >
              …
            </span>
          ) : (
            <button
              key={entry}
              type="button"
              onClick={() => go(entry)}
              disabled={busy}
              aria-label={`Page ${entry}`}
              aria-current={entry === page ? "page" : undefined}
              className={`focus-ring tnum h-9 min-w-9 cursor-pointer rounded-[10px] border px-2.5 text-[12px] font-extrabold transition-colors duration-200 disabled:cursor-not-allowed ${
                entry === page
                  ? "border-[var(--primary)]/40 bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                  : "border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] hover:bg-[var(--bg-base)] hover:text-[var(--text-primary)]"
              }`}
            >
              {entry}
            </button>
          ),
        )}

        <button
          type="button"
          onClick={() => go(page + 1)}
          disabled={busy || page === pageCount}
          aria-label="Next page"
          className="focus-ring grid h-9 w-9 cursor-pointer place-items-center rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] transition-colors duration-200 hover:bg-[var(--bg-base)] hover:text-[var(--text-primary)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
    </nav>
  );
}
