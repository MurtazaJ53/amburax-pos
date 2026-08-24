"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { CheckCircle2, MessageCircle, PhoneOff, RefreshCw, Send } from "lucide-react";

import { buildKhataReminder, whatsAppLink } from "@/lib/khata-reminder";
import { formatCurrency } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



type Debtor = {
  id: string;
  name: string;
  phone: string;
  has_phone: boolean;
  balance: string;
  last_reminded_at: string | null;
  days_since_reminder: number | null;
  reminded_today: boolean;
  is_overdue: boolean;
};

type DebtorPayload = {
  overdue_after_days: number;
  total_outstanding: string;
  unreachable_count: number;
  items: Debtor[];
};

function num(value: string | number | null | undefined): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

/** Mirrors `KhataDebtor.reminderStatus` in the mobile app. */
function reminderStatus(debtor: Debtor): string {
  if (debtor.reminded_today) return "Reminded today";
  const days = debtor.days_since_reminder;
  if (days === null) return "Never reminded";
  if (days === 1) return "Reminded yesterday";
  return `Reminded ${days} days ago`;
}

export function KhataCollection({
  shopName,
  upiVpa,
}: {
  shopName: string;
  upiVpa: string;
}) {
  const [data, setData] = useState<DebtorPayload | null>(null);
  const [onlyOverdue, setOnlyOverdue] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [marking, setMarking] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/khata/debtors");
      if (!res.ok) throw new Error(`Could not load the khata list (${res.status})`);
      setData(await res.json());
    } catch (err) {
      setError(errorMessage(err, "Something went wrong loading the list."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const all = useMemo(() => data?.items ?? [], [data]);
  const shown = onlyOverdue ? all.filter((d) => d.is_overdue) : all;
  const chaseable = all.filter((d) => d.has_phone && !d.reminded_today).length;

  /**
   * A collection round: statement links minted up front, then one customer at
   * a time.
   *
   * WhatsApp cannot be sent programmatically — every message needs the owner
   * to press send — so "remind all" can only ever be a guided walk. What it
   * removes is the waiting: all the links are minted in a single request
   * before the walk starts, so each step is pure client-side work and the
   * pop-up is opened directly inside the click.
   */
  const [round, setRound] = useState<{
    queue: Debtor[];
    at: number;
    links: Record<string, string>;
  } | null>(null);

  const startRound = async () => {
    const queue = shown.filter((d) => d.has_phone && !d.reminded_today);
    if (queue.length === 0) {
      setError("Everyone here has already been reminded today.");
      return;
    }

    setError(null);
    let links: Record<string, string> = {};
    try {
      const res = await fetch("/api/customers/statement-links/bulk", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ customer_ids: queue.map((d) => d.id) }),
      });
      if (res.ok) {
        const body = await res.json();
        for (const [id, link] of Object.entries(body.links ?? {})) {
          const path = (link as { path?: string }).path;
          if (path) links[id] = `${window.location.origin}${path}`;
        }
      }
    } catch {
      // The round still runs; the messages simply carry no statement link.
      links = {};
    }

    setRound({ queue, at: 0, links });
  };

  /** Send the current customer's message, then advance. */
  const sendCurrent = async () => {
    if (!round) return;
    const debtor = round.queue[round.at];
    if (!debtor) return;

    const message = buildKhataReminder({
      shopName,
      customerName: debtor.name,
      balance: num(debtor.balance),
      upiVpa,
      statementUrl: round.links[debtor.id] ?? "",
    });
    const link = whatsAppLink(debtor.phone, message);
    // Opened synchronously — no await between the click and window.open.
    const opened = link
      ? window.open(link, "_blank", "noopener,noreferrer")
      : null;

    if (!opened) {
      setError(
        `Could not open WhatsApp for ${debtor.name}. Allow pop-ups for this site.`
      );
      return;
    }

    try {
      await fetch(`/api/khata/remind/${debtor.id}`, { method: "POST" });
    } catch {
      // The message did go out; a failed mark only means they may show as
      // un-chased. Not worth stopping the round for.
    }

    const next = round.at + 1;
    if (next >= round.queue.length) {
      setRound(null);
      await load();
    } else {
      setRound({ ...round, at: next });
    }
  };

  /**
   * Open WhatsApp, then record the reminder.
   *
   * The mark only happens once the message window actually opened, matching
   * the phone: marking first would let a blocked pop-up quietly convince the
   * owner they had chased someone they hadn't.
   */
  const remind = async (debtor: Debtor) => {
    if (!whatsAppLink(debtor.phone, "probe")) {
      setError(`${debtor.name} has no usable mobile number.`);
      return;
    }

    // Open the window NOW, while we are still inside the click. The statement
    // link has to be fetched before the message can be composed, and a
    // window.open after an await has lost the user gesture — every browser
    // blocks it. So: claim the window synchronously, then navigate it.
    const opened = window.open("", "_blank", "noopener,noreferrer");
    if (!opened) {
      setError(
        "Your browser blocked the WhatsApp window. Allow pop-ups for this site, then try again."
      );
      return;
    }

    let statementUrl = "";
    try {
      const res = await fetch(`/api/customers/${debtor.id}/statement-link`, {
        method: "POST",
      });
      if (res.ok) {
        const body = await res.json();
        if (body.path) statementUrl = `${window.location.origin}${body.path}`;
      }
    } catch {
      // Send the reminder without the statement rather than not chasing the
      // money at all — the same call the UPI link makes when a VPA is broken.
    }

    const message = buildKhataReminder({
      shopName,
      customerName: debtor.name,
      balance: num(debtor.balance),
      upiVpa,
      statementUrl,
    });
    const link = whatsAppLink(debtor.phone, message);
    if (!link) {
      opened.close();
      setError(`${debtor.name} has no usable mobile number.`);
      return;
    }
    opened.location.href = link;

    setMarking(debtor.id);
    try {
      const res = await fetch(`/api/khata/remind/${debtor.id}`, { method: "POST" });
      if (!res.ok) throw new Error(`Could not record the reminder (${res.status})`);
      await load();
    } catch (err) {
      // The message did go out, so say exactly that rather than implying it
      // failed — otherwise the owner sends it twice.
      setError(
        `WhatsApp opened for ${debtor.name}, but recording the reminder failed. ` +
          `They may show as un-chased. (${errorMessage(err, "unknown error")})`
      );
    } finally {
      setMarking(null);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <label className="inline-flex items-center gap-2 rounded-xl border border-border-soft bg-surface px-4 py-2.5 text-xs font-extrabold text-text-secondary cursor-pointer">
          <input
            type="checkbox"
            checked={onlyOverdue}
            onChange={(e) => setOnlyOverdue(e.target.checked)}
            className="w-4 h-4 accent-[var(--primary)]"
          />
          Only overdue ({data?.overdue_after_days ?? 7}+ days)
        </label>
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

      {data && all.length > 0 && (
        <div className="rounded-[28px] border border-[var(--warning)]/30 bg-[var(--warning)]/10 p-6 sm:p-7">
          <p className="text-[11px] font-extrabold uppercase tracking-wider text-text-tertiary">
            Money out on udhaar
          </p>
          <p className="mt-1 text-3xl sm:text-4xl font-[900] tracking-tight text-[var(--warning-strong)]">
            {formatCurrency(num(data.total_outstanding))}
          </p>
          <p className="mt-2 text-xs font-semibold text-text-secondary">
            {all.length} customer{all.length === 1 ? "" : "s"} owe you
            {chaseable > 0 && ` · ${chaseable} can be chased today`}
            {data.unreachable_count > 0 &&
              ` · ${data.unreachable_count} with no mobile number`}
          </p>

          {chaseable > 0 && !round && (
            <button
              type="button"
              onClick={() => void startRound()}
              className="mt-4 inline-flex items-center gap-2 rounded-2xl bg-[var(--primary)]/12 px-5 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] border border-[var(--primary)]/25"
            >
              <Send className="w-3.5 h-3.5" />
              Remind everyone ({chaseable})
            </button>
          )}

          {round && (
            <div className="mt-4 rounded-2xl border border-[var(--primary)]/30 bg-[var(--primary)]/10 p-4">
              <p className="text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
                Collection round · {round.at + 1} of {round.queue.length}
              </p>
              <p className="mt-1 text-sm font-extrabold text-[var(--text-primary)]">
                {round.queue[round.at]?.name}
                <span className="ml-2 font-bold text-[var(--warning-strong)]">
                  {formatCurrency(num(round.queue[round.at]?.balance ?? 0))}
                </span>
              </p>
              <p className="mt-1 text-[11px] font-semibold text-[var(--text-secondary)]">
                WhatsApp opens with the message ready. Press send there, then
                come back for the next one.
              </p>
              <div className="mt-3 flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() => void sendCurrent()}
                  className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-4 py-2 text-xs font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] border border-[var(--primary)]/25"
                >
                  <Send className="w-3.5 h-3.5" />
                  Open WhatsApp
                </button>
                <button
                  type="button"
                  onClick={() =>
                    setRound((r) =>
                      !r
                        ? null
                        : r.at + 1 >= r.queue.length
                          ? null
                          : { ...r, at: r.at + 1 }
                    )
                  }
                  className="rounded-xl border border-[var(--border)] px-4 py-2 text-xs font-extrabold text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                >
                  Skip
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setRound(null);
                    void load();
                  }}
                  className="text-xs font-extrabold text-[var(--text-tertiary)] hover:underline"
                >
                  Stop
                </button>
              </div>
            </div>
          )}
          {!upiVpa.trim() && (
            <p className="mt-3 text-xs font-semibold text-text-tertiary">
              Add your UPI ID in Business details to include a one-tap pay link in
              every reminder.
            </p>
          )}
        </div>
      )}

      {loading && !data ? null : shown.length === 0 ? (
        <div className="rounded-[28px] border border-border-soft bg-surface px-6 py-12 text-center">
          <CheckCircle2 className="w-9 h-9 mx-auto text-[var(--success-strong)]" />
          <p className="mt-3 text-sm font-black text-text-primary">
            {all.length === 0 ? "Nobody owes you anything" : "Nothing overdue"}
          </p>
          <p className="mt-1 text-xs font-semibold text-text-secondary">
            {all.length === 0
              ? "Credit sales appear here automatically."
              : "Everyone with a balance has been chased in the last week."}
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {shown.map((debtor) => (
            <div
              key={debtor.id}
              className="flex flex-wrap items-center gap-3 rounded-2xl border border-border-soft bg-surface px-4 py-3.5"
            >
              <div className="flex-1 min-w-[12rem]">
                <p className="truncate text-sm font-bold text-text-primary">
                  {debtor.name}
                </p>
                <div className="mt-1 flex flex-wrap items-center gap-2">
                  <span
                    className={`rounded-full px-2.5 py-0.5 text-[10px] font-extrabold ${
                      debtor.reminded_today
                        ? "bg-[var(--success)]/15 text-[var(--success-strong)]"
                        : debtor.is_overdue
                          ? "bg-[var(--error)]/15 text-[var(--error-strong)]"
                          : "bg-[var(--warning)]/15 text-[var(--warning-strong)]"
                    }`}
                  >
                    {reminderStatus(debtor)}
                  </span>
                  {!debtor.has_phone && (
                    <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-text-tertiary">
                      <PhoneOff className="w-3 h-3" />
                      No mobile number
                    </span>
                  )}
                </div>
              </div>
              <span className="text-sm font-[900] text-text-primary">
                {formatCurrency(num(debtor.balance))}
              </span>
              <button
                type="button"
                onClick={() => void remind(debtor)}
                disabled={!debtor.has_phone || marking === debtor.id}
                title={
                  debtor.reminded_today
                    ? "Already reminded today — sending again risks annoying them."
                    : undefined
                }
                className={`inline-flex shrink-0 items-center gap-2 rounded-xl px-3.5 py-2 text-xs font-extrabold disabled:opacity-40 ${
                  debtor.reminded_today
                    ? "border border-border-soft text-text-secondary"
                    : "bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20"
                }`}
              >
                <MessageCircle className="w-3.5 h-3.5" />
                {marking === debtor.id
                  ? "Saving…"
                  : debtor.reminded_today
                    ? "Remind again"
                    : "Remind"}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
