"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { AlertTriangle } from "lucide-react";

/** What /api/billing/subscription returns, narrowed to what this needs. */
type SubscriptionState = {
  status: string;
  days_remaining: number;
  is_trial: boolean;
};

/** Show the banner from here on. Earlier is nagging: a shopkeeper with three
 *  weeks left does not need a warning strip above every screen. */
const WARN_FROM_DAYS = 7;

const DISMISS_KEY = "bh_trial_banner_dismissed_at";
const DISMISS_FOR_MS = 24 * 60 * 60 * 1000;

/** A banner about the trial ending, on every screen.
 *
 *  Nothing told a shopkeeper their trial was ending. days_remaining and
 *  expiringSoon existed only inside the billing page — the 16th of 17 sidebar
 *  items — so a 30-day trial converted at roughly the rate of people who
 *  happened to click "Subscription & billing".
 *
 *  Dismissible while there is still time, because a warning that cannot be
 *  silenced gets ignored rather than acted on. NOT dismissible once access has
 *  lapsed: at that point features are locked, and the banner is the
 *  explanation for why the app is suddenly behaving differently.
 */
export function TrialBanner() {
  const [state, setState] = useState<SubscriptionState | null>(null);
  const [dismissed, setDismissed] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/billing/subscription");
        if (!res.ok) return;
        const data = await res.json();
        if (cancelled) return;
        setState(data?.subscription ?? null);
        // Dismissal lasts a day, not forever. The situation changes daily, and
        // "I closed it once last week" must not hide the final warning.
        const dismissedAt = Number(
          window.localStorage.getItem(DISMISS_KEY) ?? 0
        );
        setDismissed(Date.now() - dismissedAt < DISMISS_FOR_MS);
      } catch {
        // Silent. A billing banner is not worth an error state on every screen
        // in the product, and the shop can still trade without it.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  if (!state) return null;

  const lapsed = state.status === "past_due" || state.status === "expired";
  const endingSoon = state.is_trial && state.days_remaining <= WARN_FROM_DAYS;

  if (!lapsed && !endingSoon) return null;
  if (!lapsed && dismissed) return null;

  const days = state.days_remaining;
  const message = lapsed
    ? "Your plan has ended and paid features are locked. Your data is safe and comes back as soon as you renew."
    : `Your trial ends in ${days} ${days === 1 ? "day" : "days"}.`;

  return (
    <div
      role="status"
      className={`flex flex-wrap items-center gap-3 px-4 py-2.5 text-xs font-bold border-b ${
        lapsed
          ? "bg-[var(--error)]/10 border-[var(--error)]/30 text-[var(--error-strong)]"
          : "bg-[var(--warning)]/10 border-[var(--warning)]/30 text-[var(--warning-strong)]"
      }`}
    >
      <AlertTriangle className="w-4 h-4 shrink-0" />
      <span className="flex-1 min-w-0">{message}</span>
      <Link
        href="/billing"
        className="underline underline-offset-2 hover:no-underline whitespace-nowrap"
      >
        {lapsed ? "Renew" : "Choose a plan"}
      </Link>
      {!lapsed && (
        <button
          type="button"
          onClick={() => {
            window.localStorage.setItem(DISMISS_KEY, String(Date.now()));
            setDismissed(true);
          }}
          className="opacity-70 hover:opacity-100 whitespace-nowrap"
        >
          Dismiss
        </button>
      )}
    </div>
  );
}
