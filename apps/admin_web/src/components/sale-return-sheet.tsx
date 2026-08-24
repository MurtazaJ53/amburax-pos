"use client";

import { useCallback, useEffect, useState } from "react";
import { Undo2, X } from "lucide-react";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

type ReturnableLine = {
  sale_item_id: string;
  name: string;
  size: string;
  sold: string;
  returned: string;
  returnable: string;
  unit_price: string;
};

type Returnable = {
  sale_id: string;
  receipt_number: string;
  is_void: boolean;
  customer_id: string | null;
  any_returnable: boolean;
  lines: ReturnableLine[];
};

/**
 * Refund methods, in the order a counter reaches for them.
 *
 * `khata` and `exchange` are not payment types — they are the two cases where
 * no cash leaves the drawer, and mislabelling them as payment is how a shop
 * ends up refunding a credit sale twice.
 */
const REFUND_MODES = [
  { value: "CASH", label: "Cash", hint: "Money out of the drawer" },
  { value: "UPI", label: "UPI", hint: "Refunded to their UPI" },
  { value: "CARD", label: "Card", hint: "Reversed to the card" },
  { value: "BANK", label: "Bank", hint: "Bank transfer" },
  { value: "KHATA", label: "Against khata", hint: "Reduces what they owe" },
  { value: "EXCHANGE", label: "Exchange", hint: "No money — ring the swap next" },
] as const;

const num = (v: string | number | null | undefined): number => {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? "0"));
  return Number.isFinite(n) ? n : 0;
};

const money = (v: number, currency = "INR") => {
  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency,
      maximumFractionDigits: 2,
    }).format(v);
  } catch {
    return `₹${v.toFixed(2)}`;
  }
};

/** Trim trailing zeros so 1.000 reads as 1 but 2.500 keeps its half. */
const qty = (v: string | number) => {
  const n = num(v);
  return Number.isInteger(n) ? String(n) : String(n);
};

/**
 * Take goods back against one bill.
 *
 * Voiding cancels a whole sale, which is the wrong tool when a customer brings
 * one shirt back out of four. This returns individual lines and leaves the
 * original bill intact — the bill still records what was sold, the return
 * records what came back.
 */
export function SaleReturnSheet({
  saleId,
  currencyCode = "INR",
  onClose,
  onDone,
}: {
  saleId: string;
  currencyCode?: string;
  onClose: () => void;
  onDone?: () => void;
}) {
  const [data, setData] = useState<Returnable | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [entered, setEntered] = useState<Record<string, string>>({});
  const [mode, setMode] = useState<string>("CASH");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/sales/${saleId}/returnable`);
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || "Could not load this bill.");
      setData(body);
    } catch (err) {
      setData(null);
      setError(errorMessage(err, "Could not load this bill."));
    } finally {
      setLoading(false);
    }
  }, [saleId]);

  useEffect(() => {
    void load();
  }, [load]);

  // A bill with no customer has no khata to credit, so that option would only
  // ever produce a rejection.
  const canKhata = Boolean(data?.customer_id);

  const refundTotal = (data?.lines ?? []).reduce((sum, line) => {
    const q = num(entered[line.sale_item_id]);
    return sum + q * num(line.unit_price);
  }, 0);

  const anyEntered = Object.values(entered).some((v) => num(v) > 0);

  const submit = async () => {
    if (!data) return;

    const lines = data.lines
      .filter((l) => num(entered[l.sale_item_id]) > 0)
      .map((l) => ({
        sale_item_id: l.sale_item_id,
        quantity: entered[l.sale_item_id].trim(),
      }));

    if (lines.length === 0) {
      setError("Enter how much of each item is coming back.");
      return;
    }

    // Checked here as well as on the server. The server is the authority, but
    // finding out at the counter with a customer waiting is the wrong moment.
    for (const line of data.lines) {
      const q = num(entered[line.sale_item_id]);
      if (q > num(line.returnable)) {
        setError(
          `${line.name}: only ${qty(line.returnable)} can be returned on this bill.`,
        );
        return;
      }
    }

    setSaving(true);
    setError(null);
    try {
      const res = await fetch(`/api/sales/${saleId}/return`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ lines, refund_mode: mode, note: note.trim() }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || "Could not process this return.");
      onDone?.();
      onClose();
    } catch (err) {
      setError(errorMessage(err, "Could not process this return."));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/60 p-0 sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Return items"
    >
      <div className="w-full sm:max-w-lg max-h-[92vh] overflow-y-auto rounded-t-[28px] sm:rounded-[28px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 sm:p-6 shadow-lg">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="text-base font-black text-[var(--text-primary)]">
              Return items
            </h2>
            {data && (
              <p className="mt-0.5 text-xs font-semibold text-[var(--text-secondary)]">
                Bill {data.receipt_number}
              </p>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="p-2 rounded-xl text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {error && (
          <div className="mt-4 rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-4 py-3 text-xs font-bold text-[var(--error-strong)]">
            {error}
          </div>
        )}

        {loading ? (
          <p className="py-10 text-center text-xs font-bold text-[var(--text-tertiary)]">
            Loading the bill…
          </p>
        ) : !data ? null : data.is_void ? (
          <p className="mt-4 rounded-2xl border border-[var(--border-soft)] bg-[var(--bg-base)] px-4 py-6 text-center text-xs font-bold text-[var(--text-secondary)]">
            This bill was voided, which already put the stock back. Nothing
            further to return.
          </p>
        ) : !data.any_returnable ? (
          <p className="mt-4 rounded-2xl border border-[var(--border-soft)] bg-[var(--bg-base)] px-4 py-6 text-center text-xs font-bold text-[var(--text-secondary)]">
            Everything on this bill has already been returned.
          </p>
        ) : (
          <>
            <div className="mt-4 space-y-2.5">
              {data.lines.map((line) => {
                const remaining = num(line.returnable);
                const isSpent = remaining <= 0;
                return (
                  <div
                    key={line.sale_item_id}
                    className={`flex items-center justify-between gap-3 rounded-2xl border border-[var(--border-soft)] px-4 py-3 ${
                      isSpent ? "bg-[var(--bg-base)] opacity-60" : "bg-[var(--bg-base)]"
                    }`}
                  >
                    <div className="min-w-0">
                      <p className="text-xs font-extrabold text-[var(--text-primary)] truncate">
                        {line.name}
                        {line.size && (
                          <span className="text-[var(--text-tertiary)]"> ({line.size})</span>
                        )}
                      </p>
                      <p className="mt-0.5 text-[10px] font-bold text-[var(--text-tertiary)]">
                        {qty(line.sold)} sold
                        {num(line.returned) > 0 && ` · ${qty(line.returned)} already returned`}
                        {" · "}
                        {money(num(line.unit_price), currencyCode)} each
                      </p>
                    </div>

                    {isSpent ? (
                      <span className="shrink-0 text-[10px] font-extrabold uppercase tracking-wide text-[var(--text-tertiary)]">
                        Returned
                      </span>
                    ) : (
                      <div className="flex items-center gap-2 shrink-0">
                        <input
                          aria-label={`Quantity returning for ${line.name}`}
                          type="number"
                          min="0"
                          max={remaining}
                          step="any"
                          inputMode="decimal"
                          placeholder="0"
                          value={entered[line.sale_item_id] ?? ""}
                          onChange={(e) =>
                            setEntered((prev) => ({
                              ...prev,
                              [line.sale_item_id]: e.target.value,
                            }))
                          }
                          className="w-16 rounded-xl border border-[var(--border)] bg-[var(--surface)] px-2 py-2 text-center text-xs font-extrabold text-[var(--text-primary)]"
                        />
                        <button
                          type="button"
                          onClick={() =>
                            setEntered((prev) => ({
                              ...prev,
                              [line.sale_item_id]: line.returnable,
                            }))
                          }
                          className="text-[10px] font-extrabold text-[var(--primary)] hover:underline whitespace-nowrap"
                        >
                          all {qty(line.returnable)}
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            <div className="mt-5">
              <p className="text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
                Refund method
              </p>
              <div className="mt-2 grid grid-cols-2 gap-2">
                {REFUND_MODES.map((m) => {
                  const disabled = m.value === "KHATA" && !canKhata;
                  return (
                    <button
                      key={m.value}
                      type="button"
                      disabled={disabled}
                      onClick={() => setMode(m.value)}
                      title={
                        disabled
                          ? "This bill has no customer, so there is no khata to credit."
                          : m.hint
                      }
                      className={`rounded-2xl border px-3 py-2.5 text-left transition-colors ${
                        mode === m.value
                          ? "border-[var(--primary)] bg-[var(--primary)]/10"
                          : "border-[var(--border)] hover:border-[var(--primary)]"
                      } ${disabled ? "opacity-40 cursor-not-allowed" : ""}`}
                    >
                      <span className="block text-xs font-extrabold text-[var(--text-primary)]">
                        {m.label}
                      </span>
                      <span className="block text-[10px] font-semibold text-[var(--text-tertiary)]">
                        {m.hint}
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>

            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Reason (optional) — e.g. wrong size"
              className="mt-4 w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-3 text-xs font-semibold text-[var(--text-primary)]"
            />

            <div className="mt-5 flex items-center justify-between gap-3 rounded-2xl bg-[var(--bg-base)] px-4 py-3">
              <span className="text-xs font-bold text-[var(--text-secondary)]">
                {mode === "EXCHANGE" ? "Value to carry over" : "Refund"}
              </span>
              <span className="text-lg font-black text-[var(--text-primary)] tabular-nums">
                {money(refundTotal, currencyCode)}
              </span>
            </div>

            {mode === "EXCHANGE" && anyEntered && (
              <p className="mt-2 text-[11px] font-semibold text-[var(--text-secondary)]">
                No money moves. Ring up the replacement item next and take the
                difference.
              </p>
            )}
            {mode === "KHATA" && anyEntered && (
              <p className="mt-2 text-[11px] font-semibold text-[var(--text-secondary)]">
                This reduces what the customer owes rather than paying cash out.
              </p>
            )}

            <button
              type="button"
              onClick={() => void submit()}
              disabled={saving || !anyEntered}
              className="mt-4 w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-[var(--primary)]/12 px-6 py-3.5 text-sm font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] disabled:opacity-50 border border-[var(--primary)]/25"
            >
              <Undo2 className="w-4 h-4" />
              {saving ? "Processing…" : "Process return"}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
