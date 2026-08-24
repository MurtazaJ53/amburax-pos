"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertTriangle, CheckCircle2, ExternalLink, Loader2, Receipt } from "lucide-react";

import { formatCurrency } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



type PlanOption = {
  period: string;
  label: string;
  amount: string;
  days: number;
  effective_monthly: string;
  savings_percent: number;
};

type Subscription = {
  status: string;
  plan_tier: string;
  billing_period: string | null;
  trial_ends_at: string | null;
  current_period_end: string | null;
  access_until: string | null;
  days_remaining: number;
  has_paid_access: boolean;
  is_trial: boolean;
};

type SubscriptionPayload = {
  subscription: Subscription;
  plans: PlanOption[];
  /** False when no gateway keys are configured — checkout cannot work. */
  payments_enabled: boolean;
};

type Invoice = {
  invoice_number: string;
  billing_period: string;
  amount: string;
  currency: string;
  status: string;
  payment_url: string | null;
  paid_at: string | null;
  created_at: string;
};

function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatDate(iso: string | null): string {
  if (!iso) return "—";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

export function SubscriptionBilling() {
  const [data, setData] = useState<SubscriptionPayload | null>(null);
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [loading, setLoading] = useState(true);
  const [checkingOut, setCheckingOut] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [subRes, invRes] = await Promise.all([
        fetch("/api/billing/subscription"),
        fetch("/api/billing/invoices"),
      ]);
      if (!subRes.ok) throw new Error(`Could not load your plan (${subRes.status})`);
      setData(await subRes.json());
      // Invoices are secondary; a failure there shouldn't hide the plan.
      if (invRes.ok) {
        const body = await invRes.json();
        setInvoices(Array.isArray(body) ? body : (body?.results ?? []));
      }
    } catch (err) {
      setError(errorMessage(err, "Something went wrong."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const checkout = async (period: string) => {
    setCheckingOut(period);
    setError(null);
    try {
      const res = await fetch("/api/billing/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ billing_period: period }),
      });
      if (res.status === 403) {
        throw new Error("Only an owner or admin can pay for the workspace.");
      }
      if (res.status === 503) {
        throw new Error(
          "Online payment isn't switched on for this workspace yet. Contact support to pay another way."
        );
      }
      if (!res.ok) throw new Error(`Could not start the payment (${res.status})`);

      const body = await res.json();
      if (!body.payment_url) {
        throw new Error("The payment link came back empty. Nothing has been charged.");
      }
      // Same tab: a payment page lost behind a pop-up blocker looks like a
      // failed charge and invites a second attempt.
      // A deliberate navigation away from the app, not component state.
      // eslint-disable-next-line react-hooks/immutability
      window.location.href = body.payment_url;
    } catch (err) {
      setError(errorMessage(err, "Could not start the payment."));
      setCheckingOut(null);
    }
  };

  if (loading && !data) {
    return (
      <div className="rounded-[28px] border border-border-soft bg-surface px-6 py-12 text-center text-sm font-semibold text-text-secondary">
        Loading…
      </div>
    );
  }

  const sub = data?.subscription;
  const expiringSoon = sub ? sub.days_remaining <= 7 : false;
  const lapsed = sub ? !sub.has_paid_access : false;

  return (
    <div className="space-y-6">
      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {sub && (
        <div
          className={`rounded-[28px] border p-6 sm:p-7 ${
            lapsed
              ? "border-[var(--error)]/30 bg-[var(--error)]/10"
              : expiringSoon
                ? "border-[var(--warning)]/30 bg-[var(--warning)]/10"
                : "border-[var(--success)]/30 bg-[var(--success)]/10"
          }`}
        >
          <div className="flex items-start gap-4">
            {lapsed ? (
              <AlertTriangle className="w-7 h-7 shrink-0 text-[var(--error-strong)]" />
            ) : (
              <CheckCircle2 className="w-7 h-7 shrink-0 text-[var(--success-strong)]" />
            )}
            <div>
              <p className="text-lg font-[900] tracking-tight text-text-primary">
                {sub.is_trial
                  ? "Free trial"
                  : lapsed
                    ? "Subscription lapsed"
                    : "Business Hub Pro"}
              </p>
              <p className="mt-1 text-xs font-semibold text-text-secondary">
                {lapsed
                  ? "Your data is safe and readable, and basic billing still works — paid features are locked until you renew."
                  : `${sub.days_remaining} day${sub.days_remaining === 1 ? "" : "s"} remaining · ${
                      sub.is_trial ? "trial ends" : "renews"
                    } ${formatDate(sub.access_until)}`}
              </p>
            </div>
          </div>
        </div>
      )}

      {data && !data.payments_enabled && (
        <div className="rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-5 py-4 text-xs font-semibold text-text-secondary">
          Online payment isn&rsquo;t configured for this deployment yet, so the
          buttons below will not complete a charge.
        </div>
      )}

      <div>
        <h2 className="text-sm font-black text-text-primary">Choose how long to pay for</h2>
        <p className="mt-1 text-xs font-semibold text-text-secondary">
          The same Pro plan either way — longer terms just cost less per month.
        </p>
        <div className="mt-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {(data?.plans ?? []).map((plan) => (
            <div
              key={plan.period}
              className="rounded-[24px] border border-border-soft bg-surface p-5 flex flex-col"
            >
              <div className="flex items-center justify-between gap-2">
                <p className="text-xs font-extrabold uppercase tracking-wider text-text-tertiary">
                  {plan.label}
                </p>
                {plan.savings_percent > 0 && (
                  <span className="rounded-full bg-[var(--success)]/15 px-2 py-0.5 text-[10px] font-extrabold text-[var(--success-strong)]">
                    SAVE {plan.savings_percent}%
                  </span>
                )}
              </div>
              <p className="mt-2 text-2xl font-[900] tracking-tight text-text-primary">
                {formatCurrency(num(plan.amount))}
              </p>
              <p className="mt-1 text-[11px] font-semibold text-text-secondary">
                {formatCurrency(num(plan.effective_monthly))}/month &middot; {plan.days} days
              </p>
              <button
                type="button"
                onClick={() => void checkout(plan.period)}
                disabled={checkingOut !== null}
                className="mt-4 inline-flex items-center justify-center gap-2 rounded-xl bg-[var(--primary)]/12 px-4 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] disabled:opacity-50 border border-[var(--primary)]/25"
              >
                {checkingOut === plan.period ? (
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                ) : (
                  <ExternalLink className="w-3.5 h-3.5" />
                )}
                {checkingOut === plan.period ? "Opening…" : "Pay"}
              </button>
            </div>
          ))}
        </div>
      </div>

      {invoices.length > 0 && (
        <div className="rounded-[28px] border border-border-soft bg-surface overflow-hidden">
          <div className="flex items-center gap-2.5 px-6 py-5 border-b border-border-soft">
            <Receipt className="w-4 h-4 text-[var(--primary)]" />
            <h2 className="text-sm font-black text-text-primary uppercase tracking-wide">
              Payment history
            </h2>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full border-collapse">
              <thead>
                <tr className="border-b border-border-soft text-left text-[11px] uppercase tracking-wider text-text-tertiary">
                  <th className="px-6 py-3 font-extrabold">Invoice</th>
                  <th className="px-6 py-3 font-extrabold">Period</th>
                  <th className="px-6 py-3 font-extrabold">Date</th>
                  <th className="px-6 py-3 font-extrabold">Status</th>
                  <th className="px-6 py-3 font-extrabold text-right">Amount</th>
                </tr>
              </thead>
              <tbody>
                {invoices.map((invoice) => {
                  const paid = invoice.status === "paid";
                  return (
                    <tr
                      key={invoice.invoice_number}
                      className="border-b border-border-soft/60 last:border-0"
                    >
                      <td className="px-6 py-4 text-xs font-bold text-text-primary">
                        {invoice.invoice_number}
                      </td>
                      <td className="px-6 py-4 text-xs font-semibold text-text-secondary">
                        {invoice.billing_period}
                      </td>
                      <td className="px-6 py-4 text-xs font-semibold text-text-secondary">
                        {formatDate(invoice.paid_at || invoice.created_at)}
                      </td>
                      <td className="px-6 py-4">
                        <span
                          className={`rounded-full px-2.5 py-0.5 text-[10px] font-extrabold uppercase ${
                            paid
                              ? "bg-[var(--success)]/15 text-[var(--success-strong)]"
                              : invoice.status === "failed"
                                ? "bg-[var(--error)]/15 text-[var(--error-strong)]"
                                : "bg-[var(--warning)]/15 text-[var(--warning-strong)]"
                          }`}
                        >
                          {invoice.status}
                        </span>
                        {!paid && invoice.payment_url && (
                          <a
                            href={invoice.payment_url}
                            className="ml-2 text-[11px] font-extrabold text-[var(--primary)] underline"
                          >
                            Finish payment
                          </a>
                        )}
                      </td>
                      <td className="px-6 py-4 text-right text-sm font-extrabold text-text-primary">
                        {formatCurrency(num(invoice.amount))}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
