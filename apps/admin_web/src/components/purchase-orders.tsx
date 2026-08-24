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
type StockItem = { id: string; name: string; sku: string; size: string };

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
        setSuppliers(
          (payload.suppliers ?? payload.results ?? payload ?? []).map(
            (raw: Record<string, unknown>) => ({
              id: String(raw.id),
              name: String(raw.name ?? ""),
            }),
          ),
        );
      }
      if (itemRes.ok) {
        const payload = await itemRes.json();
        setItems(
          (payload.items ?? payload ?? []).map((raw: Record<string, unknown>) => ({
            id: String(raw.id),
            name: String(raw.name ?? ""),
            sku: String(raw.sku ?? ""),
            size: String(raw.size ?? ""),
          })),
        );
      }
    } catch {
      // Pickers degrade to empty; the list still works.
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
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-3">
          <Stat label="On order" value={String(data?.open_count ?? 0)} />
          <Stat
            label="Overdue"
            value={String(data?.overdue_count ?? 0)}
            alarming={(data?.overdue_count ?? 0) > 0}
          />
          <Stat label="Value awaited" value={`₹${openValue.toFixed(2)}`} />
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
          {canOrder && (
            <button
              type="button"
              onClick={() => setComposing((v) => !v)}
              className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)]/12 px-4 py-2 text-xs font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] border border-[var(--primary)]/25"
            >
              {composing ? <X className="w-3.5 h-3.5" /> : <Plus className="w-3.5 h-3.5" />}
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
        <div className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 sm:p-6 shadow-sm space-y-4">
          <h3 className="text-base font-extrabold text-[var(--text-primary)]">
            New purchase order
          </h3>

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
                  onChange={(e) =>
                    setDraftLines((prev) =>
                      prev.map((l, i) => (i === index ? { ...l, itemId: e.target.value } : l)),
                    )
                  }
                  className="flex-1 min-w-[180px] rounded-2xl border border-[var(--border)] bg-[var(--bg-base)] px-4 py-2.5 text-sm font-semibold text-[var(--text-primary)]"
                >
                  <option value="">Choose an item…</option>
                  {items.map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.name}
                      {item.size ? ` (${item.size})` : ""}
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
                className="rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-4 sm:p-5 shadow-sm"
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

function Stat({
  label,
  value,
  alarming = false,
}: {
  label: string;
  value: string;
  alarming?: boolean;
}) {
  return (
    <div
      className={`rounded-2xl border px-4 py-2.5 ${
        alarming
          ? "border-[var(--error)]/30 bg-[var(--error)]/10 text-[var(--error-strong)]"
          : "border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)]"
      }`}
    >
      <span className="text-lg font-black">{value}</span>
      <span className="ml-2 text-[11px] font-extrabold uppercase tracking-wide">{label}</span>
    </div>
  );
}
