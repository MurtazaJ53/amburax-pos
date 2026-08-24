"use client";

import { useCallback, useEffect, useState } from "react";
import { RefreshCw, Users } from "lucide-react";

import { formatCurrency } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



type StaffRow = {
  name: string;
  sale_count: number;
  gross: string;
  collected?: string;
  discount_given: string;
  average_ticket: string;
};

const WINDOWS = [7, 30, 90] as const;

function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

function unwrap(body: unknown): StaffRow[] {
  if (Array.isArray(body)) return body as StaffRow[];
  const results = (body as { results?: unknown })?.results;
  return Array.isArray(results) ? (results as StaffRow[]) : [];
}

function isoDaysAgo(days: number): string {
  const then = new Date(Date.now() - days * 86_400_000);
  return then.toISOString().slice(0, 10);
}

/**
 * Who is selling, and how. Useful for targets and for spotting a till that
 * gives away far more discount than anyone else.
 */
export function StaffPerformance() {
  const [days, setDays] = useState<number>(30);
  const [rows, setRows] = useState<StaffRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/reports/staff-performance?date_from=${isoDaysAgo(days)}`
      );
      if (res.status === 403) {
        throw new Error(
          "Comparing team members needs a manager, admin or owner role."
        );
      }
      if (!res.ok) throw new Error(`Could not load performance (${res.status})`);
      setRows(unwrap(await res.json()));
    } catch (err) {
      setRows([]);
      setError(errorMessage(err, "Something went wrong loading the report."));
    } finally {
      setLoading(false);
    }
  }, [days]);

  useEffect(() => {
    void load();
  }, [load]);

  const total = rows.reduce((sum, r) => sum + num(r.gross), 0);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="inline-flex rounded-2xl border border-border-soft bg-surface p-1">
          {WINDOWS.map((w) => (
            <button
              key={w}
              type="button"
              onClick={() => setDays(w)}
              className={`px-4 py-2 rounded-xl text-xs font-extrabold transition-colors ${
                days === w
                  ? "bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 shadow-sm"
                  : "text-text-secondary hover:text-text-primary"
              }`}
            >
              {w} days
            </button>
          ))}
        </div>
        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="inline-flex items-center gap-2 rounded-xl border border-border-soft bg-surface px-4 py-2 text-xs font-extrabold text-text-secondary hover:text-text-primary disabled:opacity-50"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? "animate-spin" : ""}`} />
          Refresh
        </button>
      </div>

      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {loading && rows.length === 0 ? null : rows.length === 0 && !error ? (
        <div className="rounded-[28px] border border-border-soft bg-surface px-6 py-12 text-center">
          <Users className="w-9 h-9 mx-auto text-text-tertiary" />
          <p className="mt-3 text-sm font-black text-text-primary">
            Nothing to compare yet
          </p>
          <p className="mt-1 text-xs font-semibold text-text-secondary">
            Sales are credited to whoever was signed in when they were billed.
          </p>
        </div>
      ) : (
        <>
          <div className="space-y-2.5">
            {rows.map((row, index) => {
              const gross = num(row.gross);
              const discount = num(row.discount_given);
              const share = total > 0 ? gross / total : 0;
              return (
                <div
                  key={`${row.name}-${index}`}
                  className="rounded-2xl border border-border-soft bg-surface px-4 py-3.5"
                >
                  <div className="flex items-center gap-3">
                    <span
                      className={`w-7 h-7 shrink-0 rounded-full flex items-center justify-center text-[11px] font-[900] ${
                        index === 0
                          ? "bg-[var(--success)]/15 text-[var(--success-strong)]"
                          : "bg-border-soft text-text-secondary"
                      }`}
                    >
                      {index + 1}
                    </span>
                    <p className="flex-1 min-w-0 truncate text-sm font-extrabold text-text-primary">
                      {row.name}
                    </p>
                    <span className="text-sm font-[900] text-[var(--primary)]">
                      {formatCurrency(gross)}
                    </span>
                  </div>
                  <div className="mt-2.5 h-1.5 rounded-full bg-border-soft overflow-hidden">
                    <div
                      className="h-full rounded-full bg-[var(--primary)]"
                      style={{ width: `${Math.max(share * 100, 2)}%` }}
                    />
                  </div>
                  <p className="mt-2 text-[11px] font-semibold text-text-secondary">
                    {row.sale_count} bill{row.sale_count === 1 ? "" : "s"} &middot; avg{" "}
                    {formatCurrency(num(row.average_ticket))}
                    {discount > 0.009 &&
                      ` · ${formatCurrency(discount)} discount given`}
                  </p>
                </div>
              );
            })}
          </div>

          {rows.length === 1 && (
            <div className="rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-5 py-4">
              <p className="text-xs font-semibold text-text-secondary">
                {/* Be honest rather than let an owner read one row as proof that
                    one person did everything. */}
                Everything is credited to one account. Give each team member their
                own login from Staff &amp; PINs to compare them.
              </p>
            </div>
          )}
        </>
      )}
    </div>
  );
}
