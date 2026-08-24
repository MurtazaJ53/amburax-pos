"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight } from "lucide-react";

import { Panel, PanelEmpty } from "@/components/ui/panel";
import { paginate } from "@/lib/paging";
import { formatQuantity } from "@/lib/utils";

const PAGE_SIZE = 6;

export type LowStockRow = {
  id: string;
  item_name: string;
  sku?: string | null;
  category?: string | null;
  stock_on_hand: number;
};

type Props = {
  rows: LowStockRow[];
  /** Every low-stock item in the shop, which is far more than is sent here. */
  totalCount: number;
  className?: string;
};

/** The shelves running out, six at a time.
 *
 *  The badge said 135 above a list of six with no way to reach the seventh.
 *  The rows arrive most-urgent-first, so paging forward walks down the
 *  severity order rather than jumping around it.
 */
export function LowStockWatch({ rows, totalCount, className = "" }: Props) {
  const [pageIndex, setPageIndex] = useState(0);
  const page = paginate(rows, pageIndex, PAGE_SIZE);

  const pager =
    page.total > 1 ? (
      <div className="flex items-center gap-1.5">
        <span className="tnum font-mono text-[10.5px] font-bold text-[var(--text-tertiary)]">
          {page.firstIndex}-{page.lastIndex}
        </span>
        <button
          type="button"
          onClick={() => setPageIndex((current) => current - 1)}
          disabled={!page.hasPrevious}
          aria-label="Previous low-stock items"
          className="focus-ring grid h-7 w-7 cursor-pointer place-items-center rounded-[8px] border border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          <ChevronLeft className="h-3.5 w-3.5" />
        </button>
        <button
          type="button"
          onClick={() => setPageIndex((current) => current + 1)}
          disabled={!page.hasNext}
          aria-label="More low-stock items"
          className="focus-ring grid h-7 w-7 cursor-pointer place-items-center rounded-[8px] border border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          <ChevronRight className="h-3.5 w-3.5" />
        </button>
      </div>
    ) : null;

  return (
    <Panel
      title="Low stock watch"
      count={totalCount}
      countTone="alert"
      actionSlot={pager}
      scrollBody
      className={className}
    >
      {page.items.length === 0 ? (
        <PanelEmpty>No urgent low-stock items.</PanelEmpty>
      ) : (
        <>
          <ul className="m-0 grid list-none gap-2 p-0 sm:grid-cols-2">
            {page.items.map((item, index) => (
              <li
                key={item.id}
                className="animate-fade-in-up"
                style={{ animationDelay: `${index * 30}ms` }}
              >
                <Link
                  href="/inventory"
                  className="hover-nudge focus-ring flex items-center gap-3 rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-2.5"
                >
                  <span
                    className={`w-[3px] self-stretch rounded-full ${
                      item.stock_on_hand <= 0 ? "bg-[var(--error)]" : "bg-[var(--warning)]"
                    }`}
                    aria-hidden="true"
                  />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[12.5px] font-extrabold text-[var(--text-primary)]">
                      {item.item_name}
                    </span>
                    <span className="mt-0.5 block truncate text-[11px] font-medium text-[var(--text-tertiary)]">
                      {item.category || "Uncategorised"}
                      {item.sku ? ` · ${item.sku}` : ""}
                    </span>
                  </span>
                  <span
                    className={`tnum flex-none rounded-full px-2 py-1 font-mono text-[10px] font-bold ${
                      item.stock_on_hand <= 0
                        ? "bg-[var(--error)]/10 text-[var(--error-strong)]"
                        : "bg-[var(--warning)]/10 text-[var(--warning-strong)]"
                    }`}
                  >
                    {item.stock_on_hand <= 0
                      ? "Out"
                      : `${formatQuantity(item.stock_on_hand)} left`}
                  </span>
                </Link>
              </li>
            ))}
          </ul>

          {/* A badge of 135 above a list of six is a discrepancy the reader
              has to resolve. Name what is reachable here and where the rest
              lives. */}
          <p className="m-0 mt-2.5 flex flex-wrap items-center gap-x-2 text-[11px] font-medium text-[var(--text-tertiary)]">
            <span>
              {totalCount > rows.length
                ? `The ${rows.length} most urgent of ${totalCount}.`
                : `All ${totalCount}.`}
            </span>
            <Link
              href="/inventory"
              className="focus-ring font-bold text-[var(--primary-hover)] hover:underline"
            >
              Open stock
            </Link>
          </p>
        </>
      )}
    </Panel>
  );
}
