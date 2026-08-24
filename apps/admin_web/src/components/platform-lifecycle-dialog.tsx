"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Props = {
  shopId: string;
  shopName: string;
  action: "approve" | "suspend" | "activate" | "plan";
  actionLabel: string;
  actionDescription: string;
  buttonStyle: React.CSSProperties;
  currentPlan?: string;
};

export function PlatformLifecycleDialog({
  shopId,
  shopName,
  action,
  actionLabel,
  actionDescription,
  buttonStyle,
  currentPlan,
}: Props) {
  const [isOpen, setIsOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [planTier, setPlanTier] = useState(currentPlan || "starter");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const _router = useRouter();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (reason.length < 5) return;
    setLoading(true);
    setError(null);
    try {
      const payload = action === "plan" ? { reason, plan_tier: planTier } : { reason };
      const res = await fetch(`/api/platform/shops/${shopId}/${action}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || "Failed to execute action");
      }
      setIsOpen(false);
      window.location.reload();
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
      setLoading(false);
    }
  };

  return (
    <>
      <button 
        type="button" 
        style={buttonStyle} 
        onClick={() => setIsOpen(true)}
      >
        {actionLabel}
      </button>

      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div 
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={() => !loading && setIsOpen(false)}
          />
          <div className="relative w-full max-w-lg rounded-2xl bg-[rgba(9,14,22,0.95)] p-6 shadow-2xl border border-[var(--border-soft)]">
            <p className="eyebrow text-[var(--warning)]">Operator action — audited</p>
            <h2 className="mt-2 text-2xl font-semibold text-[var(--text-primary)]">{actionLabel}</h2>
            <p className="mt-2 text-sm text-[var(--text-secondary)]">
              {actionDescription} For shop: <strong className="text-[var(--text-primary)]">{shopName}</strong>
            </p>

            <form onSubmit={handleSubmit} className="mt-6 space-y-4">
              {action === "plan" && (
                <div>
                  <label className="block text-sm font-medium text-[var(--text-secondary)]">Plan Tier</label>
                  <select 
                    value={planTier} 
                    onChange={e => setPlanTier(e.target.value)}
                    className="mt-1 w-full rounded-xl border border-[var(--border-soft)] bg-[rgba(255,255,255,0.03)] px-4 py-2 text-white outline-none focus:border-[var(--warning)]"
                    disabled={loading}
                  >
                    <option value="starter">Starter</option>
                    <option value="growth">Growth</option>
                    <option value="pro">Pro</option>
                  </select>
                </div>
              )}

              <div>
                <label className="block text-sm font-medium text-[var(--text-secondary)]">Required Reason</label>
                <textarea
                  value={reason}
                  onChange={e => setReason(e.target.value)}
                  className="mt-1 w-full rounded-xl border border-[var(--border-soft)] bg-[rgba(255,255,255,0.03)] px-4 py-3 text-white outline-none focus:border-[var(--warning)]"
                  placeholder="Provide a reason for the audit log..."
                  rows={4}
                  disabled={loading}
                />
                <div className="mt-1 text-right text-xs text-[var(--text-muted)]">
                  {reason.length} / 5 chars minimum
                </div>
              </div>

              {error && (
                <div className="rounded-lg bg-[rgba(244,63,94,0.1)] p-3 text-sm text-[var(--error)] border border-[rgba(244,63,94,0.2)]">
                  {error}
                </div>
              )}

              <div className="mt-8 flex justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setIsOpen(false)}
                  disabled={loading}
                  className="rounded-xl px-4 py-2 text-sm font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={loading || reason.length < 5}
                  className="rounded-xl bg-[var(--warning)] px-4 py-2 text-sm font-semibold text-black disabled:opacity-50"
                >
                  {loading ? "Processing..." : "Confirm Action"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}
