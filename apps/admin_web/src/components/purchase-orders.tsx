"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  ClipboardList,
  Mail,
  Package,
  Plus,
  RefreshCw,
  Trash2,
  X,
} from "lucide-react";
import { formatCurrency } from "@/lib/formatters";
import { formatQuantity } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

type OrderLine = {
  id: string;
  inventory_item_id: string | null;
  name: string;
  sku: string;
  quantity_ordered: string;
  quantity_received: string;
  quantity_outstanding: string;
  unit_cost: string;
};

type Order = {
  id: string;
  reference: string;
  status: "draft" | "ordered" | "partially_received" | "received" | "cancelled";
  supplier_id: string | null;
  supplier_name: string;
  expected_date: string | null;
  is_overdue: boolean;
  note: string;
  outstanding_value: string;
  lines: OrderLine[];
};

type OrdersPayload = {
  orders: Order[];
  open_count: number;
  overdue_count: number;
};

type Supplier = { id: string; name: string };
type StockItem = {
  id: string;
  name: string;
  sku: string;
  size: string;
  /** Null when no cost was ever recorded, or when this role cannot see one. */
  costPrice: number | null;
  stock: number;
};

type DraftLine = { itemId: string; quantity: string; unitCost: string };

const STATUS_STYLES: Record<Order["status"], string> = {
  draft: "bg-[var(--text-tertiary)]/10 text-[var(--text-tertiary)] border-[var(--border)]",
  ordered: "bg-[var(--primary)]/10 text-[var(--primary-hover)] border-[var(--primary)]/30",
  partially_received:
    "bg-[var(--warning)]/10 text-[var(--warning-strong)] border-[var(--warning)]/30",
  received: "bg-[var(--success)]/10 text-[var(--success-strong)] border-[var(--success)]/30",
  cancelled:
    "bg-[var(--text-tertiary)]/10 text-[var(--text-tertiary)] border-[var(--border)]",
};

const STATUS_LABELS: Record<Order["status"], string> = {
  draft: "DRAFT",
  ordered: "ON ORDER",
  partially_received: "PART RECEIVED",
  received: "RECEIVED",
  cancelled: "CANCELLED",
};

function num(value: string | number): number {
  const n = typeof value === "number" ? value : parseFloat(String(value ?? "0"));
  return Number.isFinite(n) ? n : 0;
}

function qty(value: string): string {
  const n = num(value);
  return Number.isInteger(n) ? String(n) : String(n);
}

export function PurchaseOrders({ canOrder }: { canOrder: boolean }) {
  const [data, setData] = useState<OrdersPayload | null>(null);
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [pickerError, setPickerError] = useState<string | null>(null);
  const [items, setItems] = useState<StockItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [sentNote, setSentNote] = useState<string | null>(null);

  const [composing, setComposing] = useState(false);
  const [supplierId, setSupplierId] = useState("");
  const [expectedDate, setExpectedDate] = useState("");
  const [note, setNote] = useState("");
  const [draftLines, setDraftLines] = useState<DraftLine[]>([
    { itemId: "", quantity: "", unitCost: "" },
  ]);
  const [submitting, setSubmitting] = useState(false);

  /** Per-order map of line id -> quantity being booked in right now. */
  const [receiving, setReceiving] = useState<Record<string, Record<string, string>>>({});

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/purchase-orders");
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || `Could not load orders (${res.status})`);
      }
      setData(await res.json());
    } catch (err) {
      setData(null);
      setError(errorMessage(err, "Something went wrong loading purchase orders."));
    } finally {
      setLoading(false);
    }
  }, []);

  const loadPickers = useCallback(async () => {
    try {
      const [supplierRes, itemRes] = await Promise.all([
        fetch("/api/suppliers"),
        fetch("/api/inventory"),
      ]);
      if (supplierRes.ok) {
        const payload = await supplierRes.json();
        // The proxy returns { items, summary }. This looked for .suppliers,
        // then .results, then the payload itself - and the payload is an
        // OBJECT, so .map threw and the catch below ate it. The dropdown was
        // empty every time, with no error, so no order could be created.
        const rows = Array.isArray(payload)
          ? payload
          : Array.isArray(payload?.items)
            ? payload.items
            : Array.isArray(payload?.results)
              ? payload.results
              : [];
        setSuppliers(
          rows.map((raw: Record<string, unknown>) => ({
            id: String(raw.id),
            name: String(raw.name ?? ""),
            phone: String(raw.phone ?? ""),
          })),
        );
      }
      if (itemRes.ok) {
        const payload = await itemRes.json();
        const rows = Array.isArray(payload)
          ? payload
          : Array.isArray(payload?.items)
            ? payload.items
            : [];
        setItems(
          rows.map((raw: Record<string, unknown>) => ({
            id: String(raw.id),
            name: String(raw.name ?? ""),
            sku: String(raw.sku ?? ""),
            size: String(raw.size ?? ""),
            // What the shop last paid, so the line does not ask for a cost
            // the app already knows. Null when it was never recorded, or when
            // this role may not see costs - and null must stay null, because
            // a zero here becomes the cost price of everything received.
            costPrice:
              raw.cost_price === null || raw.cost_price === undefined
                ? null
                : Number(raw.cost_price),
            stock: Number(raw.stock_on_hand ?? 0),
          })),
        );
      }
    } catch (err) {
      // Said out loud. An empty dropdown with no explanation is why this
      // screen looked broken rather than merely unloaded.
      setPickerError(
        errorMessage(err, "Could not load your suppliers and stock for this order."),
      );
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (composing) void loadPickers();
  }, [composing, loadPickers]);

  const place = async () => {
    setSubmitting(true);
    setError(null);
    try {
      const lines = draftLines
        .filter((l) => l.itemId && l.quantity.trim())
        .map((l) => ({
          item_id: l.itemId,
          quantity: l.quantity.trim(),
          unit_cost: l.unitCost.trim() || "0",
        }));
      if (lines.length === 0) throw new Error("Add at least one item to order.");

      const res = await fetch("/api/purchase-orders", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          supplier_id: supplierId || null,
          expected_date: expectedDate || null,
          note: note.trim(),
          lines,
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || `Could not place the order (${res.status}).`);
      }

      setComposing(false);
      setSupplierId("");
      setExpectedDate("");
      setNote("");
      setDraftLines([{ itemId: "", quantity: "", unitCost: "" }]);
      await load();
    } catch (err) {
      setError(errorMessage(err, "Could not place the order."));
    } finally {
      setSubmitting(false);
    }
  };

  const receive = async (order: Order) => {
    const entered = receiving[order.id] ?? {};
    const lines = Object.entries(entered)
      .filter(([, value]) => value.trim() && num(value) > 0)
      .map(([lineId, value]) => ({ line_id: lineId, quantity: value.trim() }));

    if (lines.length === 0) {
      setError("Enter how much of each item actually arrived.");
      return;
    }

    setBusyId(order.id);
    setError(null);
    try {
      const res = await fetch(`/api/purchase-orders/${order.id}/receive`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ lines }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || "Could not book in this delivery.");
      }
      setReceiving((prev) => ({ ...prev, [order.id]: {} }));
      await load();
    } catch (err) {
      setError(errorMessage(err, "Could not book in this delivery."));
    } finally {
      setBusyId(null);
    }
  };

  /**
   * Email the order to the supplier.
   *
   * The provider's own outcome is surfaced rather than a blanket "sent": a
   * shop whose sending domain is unverified needs to know the supplier never
   * received it, instead of waiting for goods nobody was asked for.
   */
  const send = async (order: Order) => {
    setBusyId(order.id);
    setError(null);
    setSentNote(null);
    try {
      const res = await fetch(`/api/purchase-orders/${order.id}/send`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || "Could not send this order.");
      setSentNote(
        body.sent
          ? `Order ${order.reference} emailed to ${body.to}.`
          : `Not sent — ${body.detail || "email is not configured on the server."}`,
      );
      await load();
    } catch (err) {
      setError(errorMessage(err, "Could not send this order."));
    } finally {
      setBusyId(null);
    }
  };

  const cancel = async (order: Order) => {
    setBusyId(order.id);
    setError(null);
    try {
      const res = await fetch(`/api/purchase-orders/${order.id}`, { method: "DELETE" });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || "Could not cancel this order.");
      }
      await load();
    } catch (err) {
      setError(errorMessage(err, "Could not cancel this order."));
    } finally {
      setBusyId(null);
    }
  };

  const orders = data?.orders ?? [];
  const openValue = useMemo(
    () =>
      orders
        .filter((o) => o.status === "ordered" || o.status === "partially_received")
        .reduce((sum, o) => sum + num(o.outstanding_value), 0),
    [orders],
  );

  return (
    <div className="flex flex-col gap-4">
      {/* What this screen is for. A purchase order is the one thing in the
          app that moves no stock and no money, which makes it the hardest to
          guess at from the outside. */}
      <section className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm animate-fade-in-up">
        <h2 className="m-0 text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
          What a purchase order is
        </h2>
        <p className="m-0 mt-2 max-w-[72ch] text-[13px] font-medium leading-[1.6] text-[var(--text-secondary)]">
          It is what you have <b>asked a supplier to send</b>, before it turns
          up. Recording a purchase is the moment goods arrive — it adds stock
          and it adds to what you owe. An order does neither. It is the gap in
          between, and without it an order that never arrived looks exactly
          like an order never placed.
        </p>
        <ol className="m-0 mt-3 flex list-none flex-col gap-1.5 p-0 text-[12.5px] font-medium text-[var(--text-secondary)]">
          {[
            "Write the order and send it to the supplier.",
            "When the delivery comes, enter how much of each item actually arrived - part of it is fine, the order stays open for the rest.",
            "Booking it in records the purchase for you: stock, cost price and what you owe all move then, and not before.",
          ].map((line, index) => (
            <li key={line} className="flex gap-2">
              <span aria-hidden="true" className="font-mono text-[var(--text-tertiary)]">
                {index + 1}.
              </span>
              {line}
            </li>
          ))}
        </ol>
        <p className="m-0 mt-3 rounded-[10px] border border-[var(--primary)]/20 bg-[var(--primary)]/8 px-3 py-2 text-[12px] font-semibold text-[var(--primary-dark)]">
          The buying list already knows about these. An item on its way stops
          being suggested for reorder, so you are not asked to buy the same
          crate twice while it is on a van.
        </p>
      </section>

      {/* One row, matching every other screen. Three loose Stat blocks beside
          two buttons wrapped into a second line on a narrow window. */}
      <div className="flex flex-wrap items-center gap-4 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm animate-fade-in-up">
        <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
          {[
            {
              label: "on order",
              value: String(data?.open_count ?? 0),
              detail: "not arrived yet",
              tone: "text-[var(--text-primary)]",
            },
            {
              label: "overdue",
              value: String(data?.overdue_count ?? 0),
              detail:
                (data?.overdue_count ?? 0) > 0 ? "past the date promised" : "none late",
              tone:
                (data?.overdue_count ?? 0) > 0
                  ? "text-[var(--error-strong)]"
                  : "text-[var(--success-strong)]",
            },
            {
              label: "value awaited",
              value: formatCurrency(openValue),
              detail: "not yet owed",
              tone: "text-[var(--text-primary)]",
            },
          ].map((stat, index) => (
            <div
              key={stat.label}
              className={`flex shrink-0 flex-col justify-center ${
                index > 0 ? "border-l border-[var(--border-soft)] pl-4" : ""
              }`}
            >
              <dt className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                {stat.label}
              </dt>
              <dd className="m-0 flex items-baseline gap-1.5">
                <span
                  className={`tnum font-mono text-[17px] font-bold leading-tight ${stat.tone}`}
                >
                  {stat.value}
                </span>
                <span className="whitespace-nowrap text-[11px] font-semibold text-[var(--text-tertiary)]">
                  {stat.detail}
                </span>
              </dd>
            </div>
          ))}
        </dl>

        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            onClick={() => void load()}
            disabled={loading}
            aria-label="Refresh"
            className="focus-ring grid h-9 w-9 cursor-pointer place-items-center rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)] disabled:opacity-50"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? "animate-spin" : ""}`} />
          </button>
          {canOrder && (
            <button
              type="button"
              onClick={() => setComposing((v) => !v)}
              className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3.5 py-2 text-[12px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20"
            >
              {composing ? <X className="h-4 w-4" /> : <Plus className="h-4 w-4" />}
              {composing ? "Cancel" : "New order"}
            </button>
          )}
        </div>
      </div>

      {sentNote && (
        <div className="rounded-2xl border border-[var(--primary)]/30 bg-[var(--primary)]/10 px-5 py-3 text-xs font-bold text-[var(--text-primary)]">
          {sentNote}
        </div>
      )}

      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {composing && (
        <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 sm:p-6 shadow-sm space-y-4">
          <h3 className="text-base font-extrabold text-[var(--text-primary)]">
            New purchase order
          </h3>

          {pickerError && (
            <p
              role="alert"
              className="m-0 rounded-[10px] border border-[var(--error)]/40 bg-[var(--error)]/10 px-3 py-2 text-[12px] font-bold text-[var(--error-strong)]"
            >
              {pickerError}
            </p>
          )}

          {/* An empty list with no reason is indistinguishable from a broken
              screen, which is exactly how this one read. */}
          {!pickerError && suppliers.length === 0 && (
            <p className="m-0 rounded-[10px] border border-[var(--warning)]/40 bg-[var(--warning)]/10 px-3 py-2 text-[12px] font-bold text-[var(--warning-strong)]">
              No suppliers yet. Add one on the Suppliers screen first - an
              order has to be addressed to somebody.
            </p>
          )}

          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <label
                htmlFor="po-supplier"
                className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mb-1.5"
              >
                Supplier
              </label>
              <select
                id="po-supplier"
                value={supplierId}
                onChange={(e) => setSupplierId(e.target.value)}
                className="w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-3 text-sm font-bold text-[var(--text-primary)]"
              >
                <option value="">Choose a supplier…</option>
                {suppliers.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label
                htmlFor="po-expected"
                className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mb-1.5"
              >
                Expected by
              </label>
              <input
                id="po-expected"
                type="date"
                value={expectedDate}
                onChange={(e) => setExpectedDate(e.target.value)}
                className="w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-3 text-sm font-bold text-[var(--text-primary)]"
              />
            </div>
          </div>

          <div className="space-y-2.5">
            <span className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
              Items
            </span>
            {draftLines.map((line, index) => (
              <div key={index} className="flex flex-wrap items-center gap-2">
                <select
                  aria-label="Item"
                  value={line.itemId}
                  onChange={(e) => {
                    const picked = items.find((it) => it.id === e.target.value);
                    setDraftLines((prev) =>
                      prev.map((l, i) =>
                        i === index
                          ? {
                              ...l,
                              itemId: e.target.value,
                              // Only when the line is still blank: a cost
                              // typed by hand is a decision, and overwriting
                              // it with an old one would undo a negotiation.
                              unitCost:
                                l.unitCost.trim() === "" && picked?.costPrice != null
                                  ? String(picked.costPrice)
                                  : l.unitCost,
                            }
                          : l,
                      ),
                    );
                  }}
                  className="flex-1 min-w-[180px] rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-2.5 text-sm font-semibold text-[var(--text-primary)]"
                >
                  <option value="">Choose an item…</option>
                  {items.map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.name}
                      {item.size ? ` (${item.size})` : ""}
                      {` - ${formatQuantity(item.stock)} in stock`}
                    </option>
                  ))}
                </select>
                <input
                  aria-label="Quantity"
                  type="number"
                  min="0"
                  step="any"
                  placeholder="Qty"
                  value={line.quantity}
                  onChange={(e) =>
                    setDraftLines((prev) =>
                      prev.map((l, i) => (i === index ? { ...l, quantity: e.target.value } : l)),
                    )
                  }
                  className="w-24 rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-3 py-2.5 text-sm font-bold text-[var(--text-primary)]"
                />
                <input
                  aria-label="Unit cost"
                  type="number"
                  min="0"
                  step="any"
                  placeholder="₹ cost"
                  value={line.unitCost}
                  onChange={(e) =>
                    setDraftLines((prev) =>
                      prev.map((l, i) => (i === index ? { ...l, unitCost: e.target.value } : l)),
                    )
                  }
                  className="w-28 rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-3 py-2.5 text-sm font-bold text-[var(--text-primary)]"
                />
                {draftLines.length > 1 && (
                  <button
                    type="button"
                    aria-label="Remove item"
                    onClick={() => setDraftLines((prev) => prev.filter((_, i) => i !== index))}
                    className="p-2 rounded-xl text-[var(--text-tertiary)] hover:text-[var(--error-strong)]"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                )}
              </div>
            ))}
            <button
              type="button"
              onClick={() =>
                setDraftLines((prev) => [...prev, { itemId: "", quantity: "", unitCost: "" }])
              }
              className="inline-flex items-center gap-1.5 text-xs font-extrabold text-[var(--primary)] hover:underline"
            >
              <Plus className="w-3.5 h-3.5" /> Add another item
            </button>
          </div>

          <input
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Note (optional)"
            className="w-full rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-3 text-sm font-semibold text-[var(--text-primary)]"
          />

          <p className="text-[11px] font-semibold text-[var(--text-secondary)]">
            Placing an order changes no stock and owes the supplier nothing. Both
            happen when you book in the delivery.
          </p>

          <button
            type="button"
            onClick={() => void place()}
            disabled={submitting}
            className="w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-[var(--primary)]/12 px-6 py-3.5 text-sm font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] disabled:opacity-50 border border-[var(--primary)]/25"
          >
            <ClipboardList className="w-4 h-4" />
            {submitting ? "Placing…" : "Place order"}
          </button>
        </div>
      )}

      {loading && !data ? (
        <div className="py-12 text-center text-xs font-bold text-[var(--text-tertiary)]">
          Loading purchase orders…
        </div>
      ) : orders.length === 0 ? (
        <div className="py-12 text-center text-xs font-bold text-[var(--text-tertiary)] border border-dashed border-[var(--border-soft)] rounded-2xl bg-[var(--bg-base)]">
          No purchase orders yet.
        </div>
      ) : (
        <div className="space-y-3.5">
          {orders.map((order) => {
            const receivable =
              order.status === "ordered" || order.status === "partially_received";
            const entered = receiving[order.id] ?? {};
            return (
              <div
                key={order.id}
                className="rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] p-4 shadow-sm"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-mono text-xs font-extrabold text-[var(--text-primary)]">
                        {order.reference}
                      </span>
                      <span
                        className={`px-2.5 py-0.5 rounded-full border text-[10px] font-extrabold ${STATUS_STYLES[order.status]}`}
                      >
                        {STATUS_LABELS[order.status]}
                      </span>
                      {order.is_overdue && (
                        <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full border border-[var(--error)]/30 bg-[var(--error)]/10 text-[10px] font-extrabold text-[var(--error-strong)]">
                          <AlertTriangle className="w-3 h-3" />
                          OVERDUE
                        </span>
                      )}
                    </div>
                    <span className="block text-xs font-bold text-[var(--text-secondary)] mt-1.5">
                      {order.supplier_name || "No supplier"}
                    </span>
                    {order.expected_date && (
                      <span className="block text-[10px] font-semibold text-[var(--text-tertiary)] mt-0.5">
                        Expected {new Date(order.expected_date).toLocaleDateString("en-IN")}
                      </span>
                    )}
                  </div>

                  {receivable && canOrder && (
                    <button
                      type="button"
                      onClick={() => void cancel(order)}
                      disabled={busyId === order.id}
                      className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--border)] px-3.5 py-2 text-xs font-extrabold text-[var(--text-secondary)] hover:border-[var(--error)] hover:text-[var(--error-strong)] disabled:opacity-50"
                    >
                      <X className="w-3.5 h-3.5" />
                      Cancel order
                    </button>
                  )}
                </div>

                <div className="mt-3.5 pt-3.5 border-t border-[var(--border-soft)] space-y-2.5">
                  {order.lines.map((line) => (
                    <div
                      key={line.id}
                      className="flex flex-wrap items-center justify-between gap-3 text-xs"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <Package className="w-3.5 h-3.5 text-[var(--text-tertiary)] shrink-0" />
                        <span className="font-bold text-[var(--text-primary)] truncate">
                          {line.name}
                        </span>
                      </div>
                      <div className="flex items-center gap-3 shrink-0">
                        <span className="font-semibold text-[var(--text-secondary)]">
                          {qty(line.quantity_received)} of {qty(line.quantity_ordered)}
                        </span>
                        {receivable && canOrder && num(line.quantity_outstanding) > 0 && (
                          <input
                            aria-label={`Received now for ${line.name}`}
                            type="number"
                            min="0"
                            max={line.quantity_outstanding}
                            step="any"
                            placeholder={`+${qty(line.quantity_outstanding)}`}
                            value={entered[line.id] ?? ""}
                            onChange={(e) =>
                              setReceiving((prev) => ({
                                ...prev,
                                [order.id]: {
                                  ...(prev[order.id] ?? {}),
                                  [line.id]: e.target.value,
                                },
                              }))
                            }
                            className="w-20 rounded-xl border border-[var(--border)] bg-[var(--bg-base)] px-2.5 py-1.5 text-xs font-bold text-[var(--text-primary)]"
                          />
                        )}
                      </div>
                    </div>
                  ))}
                </div>

                {canOrder && order.status !== "cancelled" && (
                  <button
                    type="button"
                    onClick={() => void send(order)}
                    disabled={busyId === order.id}
                    className="mt-3.5 w-full inline-flex items-center justify-center gap-2 rounded-2xl border border-[var(--border)] px-6 py-2.5 text-xs font-extrabold text-[var(--text-secondary)] hover:border-[var(--primary)] hover:text-[var(--text-primary)] disabled:opacity-50"
                  >
                    <Mail className="w-3.5 h-3.5" />
                    {busyId === order.id ? "Sending…" : "Email to supplier"}
                  </button>
                )}

                {receivable && canOrder && (
                  <button
                    type="button"
                    onClick={() => void receive(order)}
                    disabled={busyId === order.id}
                    className="mt-2 w-full rounded-2xl bg-[var(--success)] px-6 py-3 text-xs font-extrabold text-white hover:opacity-90 disabled:opacity-50"
                  >
                    {busyId === order.id ? "Booking in…" : "Book in what arrived"}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

