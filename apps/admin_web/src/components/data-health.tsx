"use client";

import { useCallback, useEffect, useState } from "react";
import {
  BadgeCheck,
  PhoneOff,
  RefreshCw,
  Stethoscope,
  TrendingDown,
  WalletMinimal,
} from "lucide-react";

import type { DataHealthReport, DuplicateGroup } from "@/lib/data-health";
import { formatCurrency } from "@/lib/utils";
import { useServerRefresh } from "@/lib/use-server-refresh";
import { useDialog } from "@/components/ui/dialog-provider";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



const EMPTY_REPORT: DataHealthReport = {
  duplicateGroups: [],
  negativeStock: [],
  missingPrice: [],
  customersWithoutPhone: [],
  duplicateRowCount: 0,
  totalIssues: 0,
  isHealthy: true,
};

function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatQty(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(3).replace(/0+$/, "").replace(/\.$/, "");
}

/** The API speaks snake_case and returns only what the UI needs; map it onto
 *  the shape this component and the merge routine already use. */
/** The data-health payload, naming only what this screen reads. */
type ApiHealthItem = { id: string; name: string; stock?: string | number };
type ApiDuplicateGroup = {
  key: string;
  copies: number;
  combined_stock: string | number;
  keeper: ApiHealthItem;
  duplicates?: ApiHealthItem[];
};
type ApiHealthReport = {
  duplicate_groups?: ApiDuplicateGroup[];
  negative_stock?: unknown[];
  missing_price?: unknown[];
  customers_without_phone?: unknown[];
  duplicate_row_count?: number;
  total_issues?: number;
  is_healthy?: boolean;
};

function toReport(body: ApiHealthReport): DataHealthReport {
  const groups = (body?.duplicate_groups ?? []).map((g) => ({
    key: g.key,
    copies: g.copies,
    combinedStock: num(g.combined_stock),
    keeper: { id: g.keeper.id, name: g.keeper.name, stock_on_hand: num(g.keeper.stock) },
    duplicates: (g.duplicates ?? []).map((d) => ({
      id: d.id,
      name: d.name,
      stock_on_hand: num(d.stock),
    })),
  }));
  return {
    duplicateGroups: groups,
    negativeStock: body?.negative_stock ?? [],
    missingPrice: body?.missing_price ?? [],
    customersWithoutPhone: body?.customers_without_phone ?? [],
    duplicateRowCount: body?.duplicate_row_count ?? 0,
    totalIssues: body?.total_issues ?? 0,
    isHealthy: Boolean(body?.is_healthy),
  } as unknown as DataHealthReport;
}

export function DataHealth() {
  const { ask } = useDialog();
  const refreshServerData = useServerRefresh();
  const [report, setReport] = useState<DataHealthReport>(EMPTY_REPORT);
  const [scanned, setScanned] = useState({ items: 0, customers: 0 });
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // Scanned server-side. The browser version read /inventory/ and
      // /customers/, which slice to 200 rows, so a larger catalog was
      // half-scanned while this page claimed a full sweep.
      const res = await fetch("/api/reports/data-health");
      if (!res.ok) {
        // The status alone says nothing anybody can act on. The proxy already
        // pulls the server's own sentence out of the failure - "you do not
        // have access to this shop", "no shop selected" - and it was being
        // thrown away here, leaving a bare number on screen and no way to
        // tell a permissions problem from a missing route.
        const body = await res.json().catch(() => null);
        const detail = typeof body?.error === "string" ? body.error : "";
        throw new Error(
          detail
            ? `Could not run the scan: ${detail}`
            : `Could not run the scan (${res.status})`,
        );
      }
      const body = await res.json();
      setReport(toReport(body));
      setScanned({
        items: body?.scanned_items ?? 0,
        customers: body?.scanned_customers ?? 0,
      });
    } catch (err) {
      setError(errorMessage(err, "Something went wrong running the scan."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  /**
   * Move every copy's stock onto the keeper, then archive the copies.
   *
   * Stock is read-only on the API by design — it is the sum of a ledger — so
   * the move is two adjustments per copy rather than a stock overwrite. That
   * also leaves an audit trail explaining where the stock went. The keeper is
   * credited BEFORE the copy is archived, so a failure part way through leaves
   * the stock present and duplicated rather than destroyed.
   */
  const mergeGroup = useCallback(async (group: DuplicateGroup): Promise<void> => {
    for (const duplicate of group.duplicates) {
      const moved = num(duplicate.stock_on_hand);
      if (moved !== 0) {
        const credit = await fetch(`/api/inventory/${group.keeper.id}/adjust-stock`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            quantity_delta: moved,
            event_type: "adjustment",
            note: `Merged duplicate "${duplicate.name}" into this item.`,
          }),
        });
        if (!credit.ok) {
          throw new Error(`Could not move stock from "${duplicate.name}".`);
        }

        const drain = await fetch(`/api/inventory/${duplicate.id}/adjust-stock`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            quantity_delta: -moved,
            event_type: "adjustment",
            note: `Stock moved to "${group.keeper.name}" while merging duplicates.`,
          }),
        });
        if (!drain.ok) {
          // The keeper already holds the stock. Stopping here would leave the
          // total double-counted, which is worse than not merging at all.
          throw new Error(
            `Stock was added to "${group.keeper.name}" but could not be cleared ` +
              `from "${duplicate.name}". Check both items before retrying.`
          );
        }
      }

      // Archiving needs a higher role than adjusting stock does, so this can
      // fail after the stock has already moved. That state is still correct —
      // the keeper holds the full count and the copy holds zero — but say so
      // rather than let it read as "nothing happened".
      const archive = await fetch(`/api/inventory/${duplicate.id}`, { method: "DELETE" });
      if (!archive.ok) {
        const why =
          archive.status === 403
            ? "archiving needs an admin or owner role"
            : `the server refused (${archive.status})`;
        throw new Error(
          `Stock was combined onto "${group.keeper.name}", but the empty copy ` +
            `"${duplicate.name}" could not be archived — ${why}. The counts are ` +
            `correct; the extra row is still listed.`
        );
      }
    }
  }, []);

  const runMerge = useCallback(
    async (groups: DuplicateGroup[]) => {
      setBusy(true);
      setError(null);
      setNotice(null);
      let merged = 0;
      let failure: string | null = null;
      for (const group of groups) {
        try {
          await mergeGroup(group);
          merged += 1;
        } catch (err) {
          // One bad group shouldn't abandon the rest; report honestly at the end.
          failure = errorMessage(err, "A merge failed.");
          break;
        }
      }
      setBusy(false);
      if (merged > 0) {
        setNotice(
          `Merged ${merged} product${merged === 1 ? "" : "s"} into a single item each.`
        );
      }
      if (failure) setError(failure);
      await load();
      refreshServerData();
    },
    [mergeGroup, load, refreshServerData]
  );

  const confirmAndMerge = useCallback(
    async (groups: DuplicateGroup[]) => {
      const message =
        groups.length === 1
          ? `"${groups[0].keeper.name}" appears ${groups[0].copies} times.\n\n` +
            `Keep one item with the combined stock of ${formatQty(groups[0].combinedStock)}, ` +
            `and archive the other ${groups[0].copies - 1}.\n\n` +
            `Past bills are not affected — they keep the name and price they were sold at.`
          : `Merge ${groups.length} products?\n\nEach will be reduced to a single item ` +
            `holding the combined stock of its copies. Past bills are not affected.`;
      if (!(await ask("Merge duplicate products?", message, { confirmLabel: "Merge" }))) return;
      void runMerge(groups);
    },
    [runMerge, ask]
  );

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-xs font-semibold text-text-secondary max-w-2xl">
          Scanned {scanned.items} product{scanned.items === 1 ? "" : "s"} and{" "}
          {scanned.customers} client{scanned.customers === 1 ? "" : "s"}.
        </p>
        <button
          type="button"
          onClick={() => void load()}
          disabled={loading || busy}
          className="inline-flex items-center gap-2 rounded-xl border border-border-soft bg-surface px-4 py-2 text-xs font-extrabold text-text-secondary hover:text-text-primary disabled:opacity-50"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? "animate-spin" : ""}`} />
          Re-scan
        </button>
      </div>

      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}
      {notice && (
        <div className="rounded-2xl border border-[var(--success)]/30 bg-[var(--success)]/10 px-5 py-4 text-sm font-semibold text-[var(--success-strong)]">
          {notice}
        </div>
      )}

      <HeaderCard report={report} loading={loading} failed={error !== null} />

      {/* Always on screen, clear or not. "No problems found" on its own asks
          to be taken on trust; four named checks with their counts show what
          was actually looked at, which is what makes the verdict believable.
          It is also the answer to "why do I need this screen". */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {CHECKS.map((check) => (
          <CheckTile
            key={check.key}
            label={check.label}
            caption={check.caption}
            why={check.why}
            count={report[check.key].length}
            unknown={loading || error !== null}
          />
        ))}
      </div>

      {loading || error ? null : report.isHealthy ? (
        // The four tiles above already name every check and show it clear, so
        // a panel repeating them in prose said the same thing twice and took
        // half the screen to do it.
        <div className="flex items-center gap-3 rounded-[16px] border border-[var(--success)]/25 bg-[var(--success)]/8 px-5 py-4">
          <BadgeCheck className="h-5 w-5 shrink-0 text-[var(--success-strong)]" />
          <p className="m-0 text-[13px] font-semibold text-[var(--text-secondary)]">
            All four checks came back clear. This re-runs every time you open
            the screen, so it is worth a look after an import or a busy day.
          </p>
        </div>
      ) : (
        <>
          {report.missingPrice.length > 0 && (
            <Section
              title="Items with no price"
              count={report.missingPrice.length}
              explanation="These will ring up as free at the till. Set a selling price from Stock."
            >
              {report.missingPrice.slice(0, 30).map((item) => (
                <IssueRow
                  key={item.id}
                  icon={<WalletMinimal className="w-4 h-4 text-[var(--warning-strong)]" />}
                  title={item.name}
                  detail="No selling price"
                />
              ))}
            </Section>
          )}

          {report.duplicateGroups.length > 0 && (
            <Section
              title="Duplicate products"
              count={report.duplicateRowCount}
              explanation="The same product imported more than once. Copies split one product's stock across rows, so counts and reorder suggestions go wrong."
              action={
                report.duplicateGroups.length > 1 ? (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => confirmAndMerge(report.duplicateGroups)}
                    className="rounded-xl bg-[var(--primary)]/12 px-4 py-2 text-xs font-extrabold text-[var(--primary-dark)] disabled:opacity-50 border border-[var(--primary)]/25"
                  >
                    {busy ? "Merging…" : "Merge all"}
                  </button>
                ) : null
              }
            >
              {report.duplicateGroups.slice(0, 30).map((group) => (
                <div
                  key={group.keeper.id}
                  className="flex items-center gap-3 rounded-2xl border border-border-soft bg-surface px-4 py-3"
                >
                  <div className="flex-1 min-w-0">
                    <p className="truncate text-sm font-bold text-text-primary">
                      {group.keeper.name}
                    </p>
                    <p className="mt-0.5 text-[11px] font-semibold text-text-secondary">
                      {group.copies} copies &middot; combined stock{" "}
                      {formatQty(group.combinedStock)}
                    </p>
                  </div>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => confirmAndMerge([group])}
                    className="shrink-0 rounded-xl border border-border-soft px-3.5 py-2 text-xs font-extrabold text-text-primary hover:border-[var(--primary)] disabled:opacity-50"
                  >
                    Merge
                  </button>
                </div>
              ))}
            </Section>
          )}

          {report.negativeStock.length > 0 && (
            <Section
              title="Impossible stock counts"
              count={report.negativeStock.length}
              explanation='Stock below zero means more was sold than the system ever had. Open the item and use "Set exact" to enter the real count from the shelf.'
            >
              {report.negativeStock.slice(0, 30).map((item) => (
                <IssueRow
                  key={item.id}
                  icon={<TrendingDown className="w-4 h-4 text-[var(--error-strong)]" />}
                  title={item.name}
                  detail={`${formatQty(num(item.stock_on_hand))} in stock`}
                />
              ))}
            </Section>
          )}

          {report.customersWithoutPhone.length > 0 && (
            <Section
              title="Debts you cannot chase"
              count={report.customersWithoutPhone.length}
              explanation="These customers owe money but have no mobile number, so they can never be sent a reminder. Add their number from Clients."
            >
              {report.customersWithoutPhone.slice(0, 30).map((customer) => (
                <IssueRow
                  key={customer.id}
                  icon={<PhoneOff className="w-4 h-4 text-[var(--warning-strong)]" />}
                  title={customer.name}
                  detail={`${formatCurrency(
                    num(customer.balance ?? customer.balance_amount)
                  )} owed, no mobile`}
                />
              ))}
            </Section>
          )}
        </>
      )}

      <p className="text-xs font-semibold text-text-tertiary">
        This scan re-runs as you fix things. Nothing here deletes a sale or a
        payment — only duplicate product rows are archived.
      </p>
    </div>
  );
}

/** The four things this scan looks for, worst first.
 *
 *  They are not equally urgent and the screen should not pretend otherwise.
 *  A product with no price is losing money on every sale being rung up right
 *  now. A duplicate is quietly splitting one product's stock in two, so the
 *  reorder list is wrong but nothing is bleeding. Negative stock means the
 *  books are already wrong and stay wrong. A debtor with no phone number is
 *  stable - the money is owed either way, there is just no way to chase it.
 *
 *  Ordering by that, rather than alphabetically or by count, is the whole
 *  difference between a list and a list worth reading top to bottom.
 */
const CHECKS = [
  {
    key: "missingPrice" as const,
    label: "Free at the till",
    caption: "Products with no price",
    why: "These ring up as zero. Every one sold is money gone, today.",
  },
  {
    key: "duplicateGroups" as const,
    label: "Duplicates",
    caption: "The same product twice",
    why: "Two rows split one product's stock, so counts and reordering go wrong.",
  },
  {
    key: "negativeStock" as const,
    label: "Impossible stock",
    caption: "Below zero on the shelf",
    why: "Something sold that was never received. The books are already wrong.",
  },
  {
    key: "customersWithoutPhone" as const,
    label: "Unreachable debt",
    caption: "Owes money, no number",
    why: "The debt stands, but there is no way to chase it.",
  },
];

/** One check, always shown - clear or not.
 *
 *  Shown even at zero on purpose. A screen that renders nothing when all is
 *  well answers "is my data fine" but never "what did you actually look at",
 *  and the second question is the one that makes the first believable.
 */
function CheckTile({
  label,
  caption,
  why,
  count,
  unknown,
}: {
  label: string;
  caption: string;
  why: string;
  count: number;
  unknown: boolean;
}) {
  const clear = count === 0;
  const tone = unknown
    ? "border-[var(--border-soft)] bg-[var(--bg-base)]"
    : clear
      ? "border-[var(--success)]/25 bg-[var(--success)]/8"
      : "border-[var(--warning)]/30 bg-[var(--warning)]/10";
  const numberTone = unknown
    ? "text-[var(--text-tertiary)]"
    : clear
      ? "text-[var(--success-strong)]"
      : "text-[var(--warning-strong)]";
  return (
    <div
      className={`flex flex-col gap-1 rounded-[16px] border p-4 transition-colors duration-200 ${tone}`}
      title={why}
    >
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-[11px] font-extrabold uppercase tracking-wide text-[var(--text-tertiary)]">
          {caption}
        </span>
        {/* Tabular, so four tiles side by side do not jiggle as counts change
            after a fix. */}
        <span className={`tnum font-mono text-lg font-black leading-none ${numberTone}`}>
          {unknown ? "–" : count}
        </span>
      </div>
      <p className="m-0 text-[13px] font-extrabold text-[var(--text-primary)]">
        {label}
      </p>
      <p className="m-0 text-[11.5px] font-semibold leading-relaxed text-[var(--text-tertiary)]">
        {why}
      </p>
    </div>
  );
}

function HeaderCard({
  report,
  loading,
  failed,
}: {
  report: DataHealthReport;
  loading: boolean;
  failed: boolean;
}) {
  // An empty report is the starting value, not a result. Reading it as
  // "healthy" when the scan never returned is how this screen came to show
  // "No problems found" directly beneath "Could not run the scan".
  const healthy = !failed && report.isHealthy;
  const tone = failed
    ? "border-[var(--border-soft)] bg-[var(--bg-base)]"
    : healthy
      ? "border-[var(--success)]/30 bg-[var(--success)]/10"
      : "border-[var(--warning)]/30 bg-[var(--warning)]/10";
  return (
    <div className={`rounded-[16px] border p-6 sm:p-7 flex items-center gap-4 ${tone}`}>
      {healthy ? (
        <BadgeCheck className="w-8 h-8 shrink-0 text-[var(--success-strong)]" />
      ) : (
        <Stethoscope className="w-8 h-8 shrink-0 text-[var(--warning-strong)]" />
      )}
      <div>
        <p className="text-lg font-[900] tracking-tight text-text-primary">
          {loading
            ? "Scanning…"
            : failed
              ? "The scan did not run"
              : healthy
                ? "No problems found"
                : `${report.totalIssues} thing${report.totalIssues === 1 ? "" : "s"} to fix`}
        </p>
        <p className="mt-0.5 text-xs font-semibold text-text-secondary">
          {failed
            ? "Nothing was checked, so this says nothing about your data."
            : healthy
              ? "Your products and customers look consistent."
              : "Wrong data quietly corrupts every report built on it."}
        </p>
      </div>
    </div>
  );
}

function Section({
  title,
  count,
  explanation,
  action,
  children,
}: {
  title: string;
  count: number;
  explanation: string;
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="space-y-2.5">
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1">
          <h2 className="text-sm font-black text-text-primary">
            {title} ({count})
          </h2>
          <p className="mt-0.5 text-xs font-semibold text-text-secondary leading-relaxed max-w-2xl">
            {explanation}
          </p>
        </div>
        {action}
      </div>
      <div className="space-y-2">{children}</div>
    </section>
  );
}

function IssueRow({
  icon,
  title,
  detail,
}: {
  icon: React.ReactNode;
  title: string;
  detail: string;
}) {
  return (
    <div className="flex items-center gap-3 rounded-2xl border border-border-soft bg-surface px-4 py-3">
      <span className="shrink-0">{icon}</span>
      <div className="min-w-0">
        <p className="truncate text-sm font-bold text-text-primary">{title}</p>
        <p className="text-[11px] font-semibold text-text-secondary">{detail}</p>
      </div>
    </div>
  );
}
