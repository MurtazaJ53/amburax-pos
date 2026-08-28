"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchAllPages } from "@/lib/fetch-all";
import {
  ArrowRight,
  Check,
  Package,
  Plus,
  RefreshCw,
  Trash2,
  Store,
  TruckIcon,
  Undo2,
  X,
} from "lucide-react";

import type { ShopMembership } from "@/lib/types";
import { useServerRefresh } from "@/lib/use-server-refresh";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

type TransferLine = {
  id: string;
  source_item_id: string;
  destination_item_id: string | null;
  name: string;
  sku: string;
  size: string;
  unit: string;
  quantity: string;
  unit_cost: string | null;
};

type Transfer = {
  id: string;
  reference: string;
  status: "in_transit" | "received" | "cancelled";
  note: string;
  source_shop: { id: string; name: string };
  destination_shop: { id: string; name: string };
  dispatched_at: string;
  received_at: string | null;
  cancelled_at: string | null;
  lines: TransferLine[];
};

type TransferPayload = {
  shop_id: string;
  incoming_in_transit: number;
  outgoing_in_transit: number;
  transfers: Transfer[];
};

type StockItem = {
  id: string;
  name: string;
  sku: string;
  size: string;
  unit: string;
  stock_on_hand: number;
};

/** A row in the "what am I sending" builder. */
type DraftLine = { itemId: string; quantity: string };

function formatQty(value: string | number): string {
  const n = typeof value === "number" ? value : parseFloat(String(value ?? "0"));
  if (!Number.isFinite(n)) return "0";
  return Number.isInteger(n) ? String(n) : String(n);
}

function formatWhen(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "" : d.toLocaleString();
}

const STATUS_STYLES: Record<Transfer["status"], string> = {
  in_transit:
    "bg-[var(--warning)]/10 text-[var(--warning-strong)] border-[var(--warning)]/30",
  received:
    "bg-[var(--success)]/10 text-[var(--success-strong)] border-[var(--success)]/30",
  cancelled:
    "bg-[var(--text-tertiary)]/10 text-[var(--text-tertiary)] border-[var(--border)]",
};

const STATUS_LABELS: Record<Transfer["status"], string> = {
  in_transit: "IN TRANSIT",
  received: "RECEIVED",
  cancelled: "CANCELLED",
};

export function TransferManager({
  activeShopId,
  memberships,
  canMove,
}: {
  activeShopId: string;
  memberships: ShopMembership[];
  canMove: boolean;
}) {
  const refreshServerData = useServerRefresh();
  const [data, setData] = useState<TransferPayload | null>(null);
  const [items, setItems] = useState<StockItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const [composing, setComposing] = useState(false);
  const [destinationId, setDestinationId] = useState("");
  const [note, setNote] = useState("");
  const [draftLines, setDraftLines] = useState<DraftLine[]>([{ itemId: "", quantity: "" }]);
  const [submitting, setSubmitting] = useState(false);

  // Every other shop this user belongs to. A transfer needs somewhere to go,
  // so with only one shop the whole feature is meaningless and we say so
  // rather than showing an empty dropdown.
  const otherShops = useMemo(
    () => memberships.filter((m) => m.shop.id !== activeShopId),
    [memberships, activeShopId],
  );

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/transfers");
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || `Could not load transfers (${res.status})`);
      }
      setData(await res.json());
    } catch (err) {
      setData(null);
      setError(errorMessage(err, "Something went wrong loading transfers."));
    } finally {
      setLoading(false);
    }
  }, []);

  const loadItems = useCallback(async () => {
    try {
      // Every page: a product the picker cannot see is a product that cannot
      // be moved between branches at all.
      const payload = await fetchAllPages<Record<string, unknown>>("/api/inventory");
      const rows: StockItem[] = payload.map(
        (raw: Record<string, unknown>) => ({
          id: String(raw.id),
          name: String(raw.name ?? ""),
          sku: String(raw.sku ?? ""),
          size: String(raw.size ?? ""),
          unit: String(raw.unit ?? ""),
          stock_on_hand: Number(raw.stock_on_hand ?? 0),
        }),
      );
      // Nothing on the shelf cannot be sent, so keep it out of the picker
      // instead of letting the server reject it after the fact.
      setItems(rows.filter((r) => r.stock_on_hand > 0));
    } catch {
      // The picker degrades to empty; the list above still works.
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (composing) void loadItems();
  }, [composing, loadItems]);

  const act = async (transfer: Transfer, verb: "receive" | "cancel") => {
    setBusyId(transfer.id);
    setError(null);
    try {
      const res = await fetch(`/api/transfers/${transfer.id}/${verb}`, { method: "POST" });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || `Could not ${verb} this transfer.`);
      }
      await load();
      refreshServerData();
    } catch (err) {
      setError(errorMessage(err, `Could not ${verb} this transfer.`));
    } finally {
      setBusyId(null);
    }
  };

  const submit = async () => {
    setSubmitting(true);
    setError(null);
    try {
      const lines = draftLines
        .filter((l) => l.itemId && l.quantity.trim())
        .map((l) => ({ item_id: l.itemId, quantity: l.quantity.trim() }));
      if (!destinationId) throw new Error("Choose which shop the stock is going to.");
      if (lines.length === 0) throw new Error("Add at least one item to send.");

      const res = await fetch("/api/transfers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          destination_shop_id: destinationId,
          note: note.trim(),
          lines,
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || `Could not send the stock (${res.status}).`);
      }

      setComposing(false);
      setDestinationId("");
      setNote("");
      setDraftLines([{ itemId: "", quantity: "" }]);
      await load();
      refreshServerData();
    } catch (err) {
      setError(errorMessage(err, "Could not send the stock."));
    } finally {
      setSubmitting(false);
    }
  };

  const transfers = data?.transfers ?? [];

  return (
    <div className="space-y-6">
      {/* Pending counts: the whole reason the feature exists is that stock in
          transit used to be invisible. */}
      <div
        className={`flex flex-wrap items-center justify-between gap-3 ${
          otherShops.length === 0 ? "hidden" : ""
        }`}
      >
        <div className="flex flex-wrap gap-3">
          <PendingBadge
            label="Waiting for you to receive"
            count={data?.incoming_in_transit ?? 0}
            tone="warning"
          />
          <PendingBadge
            label="Sent, not yet confirmed"
            count={data?.outgoing_in_transit ?? 0}
            tone="muted"
          />
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => void load()}
            disabled={loading}
            className="inline-flex items-center gap-2 rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2 text-xs font-extrabold text-[var(--text-secondary)] hover:text-[var(--text-primary)] disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? "animate-spin" : ""}`} />
            Refresh
          </button>
          {canMove && otherShops.length > 0 && (
            <button
              type="button"
              onClick={() => setComposing((v) => !v)}
              className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-4 py-2 text-xs font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] border border-[var(--primary)]/25"
            >
              {composing ? <X className="w-3.5 h-3.5" /> : <Plus className="w-3.5 h-3.5" />}
              {composing ? "Cancel" : "Send stock"}
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {otherShops.length === 0 && (
        <TransfersNotAvailableYet />
      )}

      {composing && (
        <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 sm:p-6 shadow-sm space-y-4">
          <h3 className="text-base font-extrabold text-[var(--text-primary)]">
            Send stock to another shop
          </h3>

          <div>
            <label
              htmlFor="transfer-destination"
              className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mb-1.5"
            >
              Send to
            </label>
            <select
              id="transfer-destination"
              value={destinationId}
              onChange={(e) => setDestinationId(e.target.value)}
              className="w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-3 text-sm font-bold text-[var(--text-primary)]"
            >
              <option value="">Choose a shop…</option>
              {otherShops.map((m) => (
                <option key={m.shop.id} value={m.shop.id}>
                  {m.shop.name}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-2.5">
            <span className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
              Items
            </span>
            {draftLines.map((line, index) => {
              const chosen = items.find((i) => i.id === line.itemId);
              return (
                <div key={index} className="flex flex-wrap items-center gap-2">
                  <select
                    aria-label="Item"
                    value={line.itemId}
                    onChange={(e) =>
                      setDraftLines((prev) =>
                        prev.map((l, i) =>
                          i === index ? { ...l, itemId: e.target.value } : l,
                        ),
                      )
                    }
                    className="flex-1 min-w-[180px] rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-2.5 text-sm font-semibold text-[var(--text-primary)]"
                  >
                    <option value="">Choose an item…</option>
                    {items.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.name}
                        {item.size ? ` (${item.size})` : ""} — {formatQty(item.stock_on_hand)}
                        {item.unit ? ` ${item.unit}` : ""} in stock
                      </option>
                    ))}
                  </select>
                  <input
                    aria-label="Quantity"
                    type="number"
                    min="0"
                    step="any"
                    inputMode="decimal"
                    placeholder="Qty"
                    value={line.quantity}
                    onChange={(e) =>
                      setDraftLines((prev) =>
                        prev.map((l, i) =>
                          i === index ? { ...l, quantity: e.target.value } : l,
                        ),
                      )
                    }
                    className="w-24 rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-3 py-2.5 text-sm font-bold text-[var(--text-primary)]"
                  />
                  {chosen && (
                    <span className="text-[10px] font-bold text-[var(--text-tertiary)]">
                      max {formatQty(chosen.stock_on_hand)}
                    </span>
                  )}
                  {draftLines.length > 1 && (
                    <button
                      type="button"
                      aria-label="Remove item"
                      onClick={() =>
                        setDraftLines((prev) => prev.filter((_, i) => i !== index))
                      }
                      className="p-2 rounded-xl text-[var(--text-tertiary)] hover:text-[var(--error-strong)]"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  )}
                </div>
              );
            })}
            <button
              type="button"
              onClick={() =>
                setDraftLines((prev) => [...prev, { itemId: "", quantity: "" }])
              }
              className="inline-flex items-center gap-1.5 text-xs font-extrabold text-[var(--primary)] hover:underline"
            >
              <Plus className="w-3.5 h-3.5" /> Add another item
            </button>
          </div>

          <div>
            <label
              htmlFor="transfer-note"
              className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mb-1.5"
            >
              Note (optional)
            </label>
            <input
              id="transfer-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Sent with the afternoon van"
              className="w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-3 text-sm font-semibold text-[var(--text-primary)]"
            />
          </div>

          <p className="text-[11px] font-semibold text-[var(--text-secondary)]">
            The stock leaves this shop now. It only appears at the other shop
            once someone there confirms it arrived.
          </p>

          <button
            type="button"
            onClick={() => void submit()}
            disabled={submitting}
            className="w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-[var(--primary)]/12 px-6 py-3.5 text-sm font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] disabled:opacity-50 border border-[var(--primary)]/25"
          >
            <TruckIcon className="w-4 h-4" />
            {submitting ? "Sending…" : "Send stock"}
          </button>
        </div>
      )}

      {otherShops.length === 0 ? null : loading && !data ? (
        <div className="py-12 text-center text-xs font-bold text-[var(--text-tertiary)]">
          Loading transfers…
        </div>
      ) : transfers.length === 0 ? (
        <div className="rounded-[16px] border border-dashed border-[var(--border-soft)] bg-[var(--bg-base)] px-6 py-12 text-center">
          <p className="m-0 text-[13px] font-extrabold text-[var(--text-secondary)]">
            Nothing has been sent between your shops yet.
          </p>
          <p className="m-0 mt-1.5 text-[12px] font-semibold text-[var(--text-tertiary)]">
            Use <strong>Send stock</strong> when one shop runs short and another has spare.
          </p>
        </div>
      ) : null}

      {otherShops.length > 0 && transfers.length === 0 && !loading ? (
        <div>
          <p className="m-0 mb-2 font-mono text-[10px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
            How it works
          </p>
          <TransferFlow />
        </div>
      ) : (
        <div className="space-y-3.5">
          {transfers.map((transfer) => {
            const isIncoming = transfer.destination_shop.id === activeShopId;
            const pending = transfer.status === "in_transit";
            return (
              <div
                key={transfer.id}
                className="rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-4 sm:p-5 shadow-sm"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-mono text-xs font-extrabold text-[var(--text-primary)]">
                        {transfer.reference}
                      </span>
                      <span
                        className={`px-2.5 py-0.5 rounded-full border text-[10px] font-extrabold ${STATUS_STYLES[transfer.status]}`}
                      >
                        {STATUS_LABELS[transfer.status]}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 mt-1.5 text-xs font-bold text-[var(--text-secondary)]">
                      <span>{transfer.source_shop.name}</span>
                      <ArrowRight className="w-3.5 h-3.5 text-[var(--text-tertiary)]" />
                      <span>{transfer.destination_shop.name}</span>
                    </div>
                    <span className="block text-[10px] font-semibold text-[var(--text-tertiary)] mt-1">
                      Sent {formatWhen(transfer.dispatched_at)}
                      {transfer.received_at && ` · Received ${formatWhen(transfer.received_at)}`}
                    </span>
                  </div>

                  {pending && canMove && (
                    <div className="flex items-center gap-2">
                      {isIncoming ? (
                        <button
                          type="button"
                          onClick={() => void act(transfer, "receive")}
                          disabled={busyId === transfer.id}
                          className="inline-flex items-center gap-1.5 rounded-xl bg-[var(--success)] px-4 py-2 text-xs font-extrabold text-white hover:opacity-90 disabled:opacity-50"
                        >
                          <Check className="w-3.5 h-3.5" />
                          {busyId === transfer.id ? "Receiving…" : "Receive"}
                        </button>
                      ) : (
                        <button
                          type="button"
                          onClick={() => void act(transfer, "cancel")}
                          disabled={busyId === transfer.id}
                          className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--border)] px-4 py-2 text-xs font-extrabold text-[var(--text-secondary)] hover:border-[var(--error)] hover:text-[var(--error-strong)] disabled:opacity-50"
                        >
                          <X className="w-3.5 h-3.5" />
                          {busyId === transfer.id ? "Cancelling…" : "Cancel"}
                        </button>
                      )}
                    </div>
                  )}
                </div>

                <div className="mt-3.5 pt-3.5 border-t border-[var(--border-soft)] space-y-2">
                  {transfer.lines.map((line) => (
                    <div
                      key={line.id}
                      className="flex items-center justify-between gap-3 text-xs"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <Package className="w-3.5 h-3.5 text-[var(--text-tertiary)] shrink-0" />
                        <span className="font-bold text-[var(--text-primary)] truncate">
                          {line.name}
                          {line.size && (
                            <span className="text-[var(--text-tertiary)]"> ({line.size})</span>
                          )}
                        </span>
                      </div>
                      <span className="font-extrabold text-[var(--text-primary)] shrink-0">
                        {formatQty(line.quantity)}
                        {line.unit ? ` ${line.unit}` : ""}
                      </span>
                    </div>
                  ))}
                </div>

                {transfer.note && (
                  <p className="mt-3 text-[11px] font-semibold text-[var(--text-secondary)]">
                    {transfer.note}
                  </p>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

/** The three states a transfer passes through, said once and plainly.
 *
 *  The whole feature exists because the middle one used to be invisible: two
 *  unrelated manual adjustments, and a forgotten second half left the numbers
 *  wrong with nothing to point at. A screen that does not name that state
 *  cannot explain why it is worth the extra step.
 */
const TRANSFER_STEPS = [
  {
    icon: Package,
    title: "You send it",
    body: "Stock leaves the sending shop straight away, so it cannot be sold twice.",
  },
  {
    icon: TruckIcon,
    title: "It is on its way",
    body: "Both shops can see it in transit. Nowhere yet - counted out of one, not into the other.",
  },
  {
    icon: Check,
    title: "The other shop confirms",
    body: "Only then does it land on their shelf. Their cost and selling price update with it.",
  },
];

function TransferFlow() {
  return (
    <div className="grid gap-2.5 sm:grid-cols-3">
      {TRANSFER_STEPS.map((step, index) => (
        <div
          key={step.title}
          className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-4"
        >
          <div className="flex items-center gap-2">
            <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-[var(--primary)]/12 text-[var(--primary-dark)]">
              <step.icon className="h-3.5 w-3.5" />
            </span>
            {/* Numbered because the order is the point: a step skipped is the
                bug this feature was built to stop. */}
            <span className="font-mono text-[10px] font-bold tracking-[0.14em] text-[var(--text-tertiary)]">
              STEP {index + 1}
            </span>
          </div>
          <p className="m-0 mt-2.5 text-[13px] font-extrabold text-[var(--text-primary)]">
            {step.title}
          </p>
          <p className="m-0 mt-1 text-[12px] font-semibold leading-relaxed text-[var(--text-tertiary)]">
            {step.body}
          </p>
        </div>
      ))}
    </div>
  );
}

/** What this screen is, for a shop that cannot use it yet.
 *
 *  Two zero counters above an empty list read as a screen that is broken.
 *  This one is not broken - it has nowhere to send stock, which is a
 *  different thing and worth saying out loud.
 */
function TransfersNotAvailableYet() {
  return (
    <div className="flex flex-col gap-4">
      <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 sm:p-6">
        <div className="flex items-start gap-3">
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-[var(--primary)]/12 text-[var(--primary-dark)]">
            <Store className="h-4 w-4" />
          </span>
          <div className="min-w-0">
            <h3 className="m-0 text-[15px] font-extrabold text-[var(--text-primary)]">
              You have one shop, so there is nowhere to send stock
            </h3>
            <p className="m-0 mt-1.5 max-w-[62ch] text-[13px] font-semibold leading-relaxed text-[var(--text-secondary)]">
              Transfers move stock between two shops you own - when one runs
              short and another has spare. Nothing here is broken; it switches
              on by itself the moment you have a second shop.
            </p>
            <p className="m-0 mt-2 text-[12px] font-semibold text-[var(--text-tertiary)]">
              Until then, use <strong>Stock</strong> to correct a count, and{" "}
              <strong>Purchase orders</strong> to bring goods in from a supplier.
            </p>
          </div>
        </div>
      </div>

      <div>
        <p className="m-0 mb-2 font-mono text-[10px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
          How it will work
        </p>
        <TransferFlow />
      </div>

      <p className="m-0 flex items-center gap-1.5 text-[12px] font-semibold text-[var(--text-tertiary)]">
        <Undo2 className="h-3.5 w-3.5 shrink-0" />
        A transfer can be cancelled while it is still in transit, and the stock
        goes straight back to the shop that sent it.
      </p>
    </div>
  );
}

function PendingBadge({
  label,
  count,
  tone,
}: {
  label: string;
  count: number;
  tone: "warning" | "muted";
}) {
  const active = count > 0;
  const classes =
    active && tone === "warning"
      ? "border-[var(--warning)]/30 bg-[var(--warning)]/10 text-[var(--warning-strong)]"
      : "border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)]";
  return (
    <div
      className={`flex items-baseline gap-2 rounded-[16px] border px-4 py-2.5 transition-colors duration-200 ${classes}`}
    >
      {/* Tabular, so two counters side by side do not shift as they change. */}
      <span className="tnum text-lg font-black leading-none">{count}</span>
      <span className="text-[11px] font-extrabold uppercase tracking-wide">
        {label}
      </span>
      {/* Only when there is something to act on. A dot beside a zero is
          decoration pretending to be a status. */}
      {active && tone === "warning" && (
        <span
          aria-hidden="true"
          className="motion-safe:animate-pulse ml-0.5 h-1.5 w-1.5 shrink-0 self-center rounded-full bg-[var(--warning-strong)]"
        />
      )}
    </div>
  );
}
