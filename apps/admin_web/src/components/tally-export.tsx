"use client";

import { useState } from "react";
import { Download, FileSpreadsheet, Loader2 } from "lucide-react";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



function isoDaysAgo(days: number): string {
  return new Date(Date.now() - days * 86_400_000).toISOString().slice(0, 10);
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Export sales as a Tally-importable voucher file.
 *
 * Indian accountants work in Tally, so "can my CA import this?" often decides
 * whether a shop can adopt the app at all.
 */
export function TallyExport() {
  const [dateFrom, setDateFrom] = useState(isoDaysAgo(30));
  const [dateTo, setDateTo] = useState(today());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const rangeIsBackwards = Boolean(dateFrom && dateTo && dateFrom > dateTo);

  const download = async () => {
    setBusy(true);
    setError(null);
    try {
      const params = new URLSearchParams();
      if (dateFrom) params.set("date_from", dateFrom);
      if (dateTo) params.set("date_to", dateTo);

      const res = await fetch(`/api/reports/tally-export?${params}`);
      if (res.status === 403) {
        throw new Error("Exporting the books needs an admin or owner role.");
      }
      if (!res.ok) throw new Error(`Export failed (${res.status})`);

      // Read the server's own filename so the CA gets the shop and date range
      // in the name rather than "download.xml".
      const disposition = res.headers.get("content-disposition") || "";
      const match = disposition.match(/filename="?([^"]+)"?/);
      const filename = match?.[1] || `Tally_${dateFrom}_${dateTo}.xml`;

      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(errorMessage(err, "Could not build the export."));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-5">
      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      <div className="rounded-[28px] border border-border-soft bg-surface p-6 sm:p-7 space-y-5">
        <div className="flex items-start gap-4">
          <FileSpreadsheet className="w-6 h-6 shrink-0 text-[var(--primary)]" />
          <div>
            <p className="text-sm font-black text-text-primary">Tally export</p>
            <p className="mt-1 text-xs font-semibold text-text-secondary">
              A voucher XML your accountant can import straight into Tally.
              Refunded bills are left out — importing them would overstate revenue.
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2 border-t border-border-soft">
          <label className="block">
            <span className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
              From
            </span>
            <input
              type="date"
              value={dateFrom}
              max={dateTo || undefined}
              onChange={(e) => setDateFrom(e.target.value)}
              className="mt-1.5 w-full rounded-xl border border-border-soft bg-bg-base px-3 py-2.5 text-sm font-bold text-text-primary"
            />
          </label>
          <label className="block">
            <span className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
              To
            </span>
            <input
              type="date"
              value={dateTo}
              min={dateFrom || undefined}
              onChange={(e) => setDateTo(e.target.value)}
              className="mt-1.5 w-full rounded-xl border border-border-soft bg-bg-base px-3 py-2.5 text-sm font-bold text-text-primary"
            />
          </label>
        </div>

        {rangeIsBackwards && (
          <p className="text-xs font-semibold text-[var(--error-strong)]">
            The start date is after the end date, so the export would be empty.
          </p>
        )}

        <button
          type="button"
          onClick={() => void download()}
          disabled={busy || rangeIsBackwards}
          className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-5 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] disabled:opacity-50 border border-[var(--primary)]/25"
        >
          {busy ? (
            <Loader2 className="w-3.5 h-3.5 animate-spin" />
          ) : (
            <Download className="w-3.5 h-3.5" />
          )}
          Download Tally XML
        </button>
      </div>
    </div>
  );
}
