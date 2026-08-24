"use client";

import { useCallback, useEffect, useState } from "react";
import { Gift, Loader2 } from "lucide-react";

import { formatCurrency } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



type LoyaltyConfig = {
  enabled: boolean;
  points_per_hundred: number;
  point_value: string;
  summary: string;
};

function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

/**
 * The loyalty promise, in one sentence a cashier can say across the counter.
 * Anything with tiers or expiry gets argued with daily, so the shop only gets
 * two numbers to set.
 */
export function LoyaltySettings() {
  const [config, setConfig] = useState<LoyaltyConfig | null>(null);
  const [perHundred, setPerHundred] = useState("1");
  const [pointValue, setPointValue] = useState("1.00");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [readOnly, setReadOnly] = useState(false);

  const apply = (body: LoyaltyConfig) => {
    setConfig(body);
    setPerHundred(String(body.points_per_hundred));
    setPointValue(String(body.point_value));
  };

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/loyalty");
      if (!res.ok) throw new Error(`Could not load loyalty settings (${res.status})`);
      apply(await res.json());
    } catch (err) {
      setError(errorMessage(err, "Something went wrong."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const save = async (patch: Record<string, unknown>) => {
    setSaving(true);
    setError(null);
    setSaved(false);
    try {
      const res = await fetch("/api/loyalty", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(patch),
      });
      if (res.status === 403) {
        setReadOnly(true);
        throw new Error(
          "Changing the loyalty rules needs an admin or owner role — it changes what the shop owes every existing customer."
        );
      }
      if (!res.ok) {
        const body = await res.json().catch(() => null);
        // Surface the server's field message; it explains the actual limit.
        const detail =
          body && typeof body.error === "string" ? body.error : `HTTP ${res.status}`;
        throw new Error(detail);
      }
      apply(await res.json());
      setSaved(true);
      window.setTimeout(() => setSaved(false), 2500);
    } catch (err) {
      setError(errorMessage(err, "Could not save."));
      // Put the inputs back to what is actually stored, so the screen never
      // shows a rate the shop is not honouring.
      await load();
    } finally {
      setSaving(false);
    }
  };

  if (loading && !config) {
    return (
      <div className="rounded-[28px] border border-border-soft bg-surface px-6 py-12 text-center text-sm font-semibold text-text-secondary">
        Loading…
      </div>
    );
  }

  const enabled = config?.enabled ?? false;
  const previewSpend = 1000;
  const previewPoints = Math.floor(previewSpend / 100) * num(perHundred);

  return (
    <div className="space-y-5">
      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}
      {saved && (
        <div className="rounded-2xl border border-[var(--success)]/30 bg-[var(--success)]/10 px-5 py-4 text-sm font-semibold text-[var(--success-strong)]">
          Saved. New bills use these rules straight away.
        </div>
      )}

      <div className="rounded-[28px] border border-border-soft bg-surface p-6 sm:p-7 space-y-5">
        <div className="flex items-start gap-4">
          <Gift className="w-6 h-6 shrink-0 text-[var(--primary)]" />
          <div className="flex-1">
            <p className="text-sm font-black text-text-primary">Loyalty points</p>
            <p className="mt-1 text-xs font-semibold text-text-secondary">
              {config?.summary}
            </p>
          </div>
          <button
            type="button"
            role="switch"
            aria-checked={enabled}
            disabled={saving || readOnly}
            onClick={() => void save({ enabled: !enabled })}
            className={`relative h-7 w-12 shrink-0 rounded-full transition-colors disabled:opacity-50 ${
              enabled ? "bg-[var(--primary)]" : "bg-border"
            }`}
          >
            <span
              className={`absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition-all ${
                enabled ? "left-[1.375rem]" : "left-0.5"
              }`}
            />
          </button>
        </div>

        {enabled && (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2 border-t border-border-soft">
            <label className="block">
              <span className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
                Points per ₹100 spent
              </span>
              <input
                type="number"
                min={0}
                max={1000}
                value={perHundred}
                disabled={readOnly}
                onChange={(e) => setPerHundred(e.target.value)}
                className="mt-1.5 w-full rounded-xl border border-border-soft bg-bg-base px-3 py-2.5 text-sm font-bold text-text-primary"
              />
            </label>
            <label className="block">
              <span className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
                One point is worth (₹)
              </span>
              <input
                type="number"
                min="0.01"
                step="0.01"
                value={pointValue}
                disabled={readOnly}
                onChange={(e) => setPointValue(e.target.value)}
                className="mt-1.5 w-full rounded-xl border border-border-soft bg-bg-base px-3 py-2.5 text-sm font-bold text-text-primary"
              />
            </label>

            <div className="sm:col-span-2 rounded-2xl bg-bg-base border border-border-soft px-4 py-3">
              <p className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
                What a customer gets
              </p>
              <p className="mt-1 text-xs font-semibold text-text-secondary">
                Spend {formatCurrency(previewSpend)} &rarr; earn {previewPoints} point
                {previewPoints === 1 ? "" : "s"} &rarr; worth{" "}
                <strong className="text-text-primary">
                  {formatCurrency(previewPoints * num(pointValue))}
                </strong>{" "}
                off a future bill.
              </p>
              <p className="mt-1.5 text-[11px] font-semibold text-text-tertiary">
                Points are rounded down, so a ₹190 bill earns the same as ₹100 — the
                shop never owes more than it intended.
              </p>
            </div>

            <div className="sm:col-span-2">
              <button
                type="button"
                disabled={saving || readOnly}
                onClick={() =>
                  void save({
                    points_per_hundred: perHundred,
                    point_value: pointValue,
                  })
                }
                className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-5 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] disabled:opacity-50 border border-[var(--primary)]/25"
              >
                {saving && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                Save rules
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
