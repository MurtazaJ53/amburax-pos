"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchAllPages } from "@/lib/fetch-all";
import {
  AlertTriangle,
  ClipboardList,
  Mail,
  Package,
  Plus,
  RefreshCw,
  X,
} from "lucide-react";
import { formatCurrency } from "@/lib/formatters";
import { BLANK_LINE, type DraftLine, type StockItem } from "@/lib/item-lines";
import { ItemLinesEditor } from "@/components/ui/item-lines-editor";
import { useServerRefresh } from "@/lib/use-server-refresh";

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

type Supplier = { id: string; name: string; phone: string };
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
  const refreshServerData = useServerRefresh();
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
  const [supplierQuery, setSupplierQuery] = useState("");
  const [supplierOpen, setSupplierOpen] = useState(false);
  const [newSupplierOpen, setNewSupplierOpen] = useState(false);
  const [newSupplierName, setNewSupplierName] = useState("");
  const [newSupplierPhone, setNewSupplierPhone] = useState("");
  const [creatingSupplier, setCreatingSupplier] = useState(false);
  const [expectedDate, setExpectedDate] = useState("");
  const [note, setNote] = useState("");
  const [draftLines, setDraftLines] = useState<DraftLine[]>([{ ...BLANK_LINE }]);
  const [openLine, setOpenLine] = useState<number | null>(null);
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

  const chosenSupplier = suppliers.find((sup) => sup.id === supplierId) ?? null;
  const supplierMatches = (() => {
    const q = supplierQuery.trim().toLowerCase();
    const pool = q
      ? suppliers.filter(
          (sup) =>
            sup.name.toLowerCase().includes(q) ||
            (sup.phone ?? "").toLowerCase().includes(q),
        )
      : suppliers;
    return pool.slice(0, 6);
  })();

  /** Create a vendor without leaving the order, and select it.
   *
   *  A first order from somebody new is the commonest reason to be on this
   *  screen at all, and it was the one thing the screen could not do. */
  const createSupplier = async () => {
    const name = newSupplierName.trim();
    if (!name) return;
    setCreatingSupplier(true);
    setPickerError(null);
    try {
      const res = await fetch("/api/suppliers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, phone: newSupplierPhone.trim() }),
      });
      const body = await res.json().catch(() => null);
      if (!res.ok) {
        throw new Error(body?.error || "Could not save that supplier.");
      }
      const created = body as { id?: unknown; name?: unknown; phone?: unknown };
      if (!created?.id) throw new Error("The supplier was saved without an id.");
      const record: Supplier = {
        id: String(created.id),
        name: String(created.name ?? name),
        phone: String(created.phone ?? newSupplierPhone.trim()),
      };
      setSuppliers((prev) => [record, ...prev]);
      setSupplierId(record.id);
      setSupplierQuery("");
      setNewSupplierOpen(false);
      setNewSupplierName("");
      setNewSupplierPhone("");
      setSupplierOpen(false);
    } catch (err) {
      setPickerError(errorMessage(err, "Could not save that supplier."));
    } finally {
      setCreatingSupplier(false);
    }
  };


  const loadPickers = useCallback(async () => {
    try {
      // The catalogue comes back a page at a time. A picker holding only the
      // first page cannot reorder the products further down it, which is
      // exactly the long tail a shop runs out of.
      const [supplierRes, itemRows] = await Promise.all([
        fetch("/api/suppliers"),
        fetchAllPages<Record<string, unknown>>("/api/inventory"),
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
      setItems(
        itemRows.map((raw: Record<string, unknown>) => ({
          id: String(raw.id),
          name: String(raw.name ?? ""),
          sku: String(raw.sku ?? ""),
          size: String(raw.size ?? ""),
          unit: String(raw.unit ?? ""),
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

  // Close any open item list on a click elsewhere.
  useEffect(() => {
    if (!supplierOpen) return;
    const close = () => setSupplierOpen(false);
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [supplierOpen]);

  useEffect(() => {
    if (openLine === null) return;
    const close = () => setOpenLine(null);
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [openLine]);

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
      setDraftLines([{ ...BLANK_LINE }]);
      await load();
      refreshServerData();
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
      refreshServerData();
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
      refreshServerData();
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
      refreshServerData();
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
              No suppliers yet. Type a name in the supplier box below and add
              them there - an order has to be addressed to somebody.
            </p>
          )}

          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <label className="mb-1.5 block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)]">
                Supplier
              </label>

              {/* Same control as the Suppliers screen, because it is the same
                  question. A native select could not be searched and had no
                  way to add a vendor, so a first order from somebody new
                  meant abandoning the order to go and create them. */}
              <div className="relative" onMouseDown={(e) => e.stopPropagation()}>
                <input
                  type="text"
                  value={chosenSupplier ? chosenSupplier.name : supplierQuery}
                  onChange={(e) => {
                    setSupplierQuery(e.target.value);
                    setSupplierId("");
                  }}
                  onFocus={() => setSupplierOpen(true)}
                  placeholder="Type a supplier name"
                  className="w-full rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-base)] px-3 py-2.5 text-[13px] font-semibold text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
                />
                {chosenSupplier && (
                  <button
                    type="button"
                    onClick={() => {
                      setSupplierId("");
                      setSupplierQuery("");
                      setSupplierOpen(true);
                    }}
                    aria-label="Choose a different supplier"
                    className="focus-ring absolute right-2 top-1/2 grid h-6 w-6 -translate-y-1/2 cursor-pointer place-items-center rounded-full text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                )}

                {supplierOpen && !chosenSupplier && (
                  <div className="animate-fade-in-up absolute left-0 right-0 top-full z-30 mt-1 max-h-[220px] overflow-y-auto rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] p-1 shadow-lg">
                    {supplierMatches.map((sup) => (
                      <button
                        key={sup.id}
                        type="button"
                        onClick={() => {
                          setSupplierId(sup.id);
                          setSupplierOpen(false);
                        }}
                        className="focus-ring flex w-full cursor-pointer items-center gap-2 rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-[var(--bg-base)]"
                      >
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-[12px] font-bold text-[var(--text-primary)]">
                            {sup.name}
                          </span>
                          <span className="block truncate font-mono text-[10px] text-[var(--text-tertiary)]">
                            {sup.phone || "no phone"}
                          </span>
                        </span>
                      </button>
                    ))}

                    {newSupplierOpen ? (
                      <div className="border-t border-[var(--border-soft)] p-2">
                        <p className="m-0 mb-1.5 font-mono text-[9.5px] font-bold uppercase tracking-[0.12em] text-[var(--text-tertiary)]">
                          New supplier
                        </p>
                        <input
                          type="text"
                          value={newSupplierName}
                          onChange={(e) => setNewSupplierName(e.target.value)}
                          placeholder="Name"
                          className="mb-1.5 w-full rounded-lg border border-[var(--border-soft)] bg-[var(--bg-base)] px-2.5 py-2 text-[12px] font-semibold text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
                        />
                        <input
                          type="tel"
                          inputMode="tel"
                          value={newSupplierPhone}
                          onChange={(e) => setNewSupplierPhone(e.target.value)}
                          placeholder="Phone (optional)"
                          className="mb-2 w-full rounded-lg border border-[var(--border-soft)] bg-[var(--bg-base)] px-2.5 py-2 text-[12px] font-semibold text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
                        />
                        <button
                          type="button"
                          disabled={!newSupplierName.trim() || creatingSupplier}
                          onClick={() => void createSupplier()}
                          className="focus-ring w-full cursor-pointer rounded-lg border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3 py-2 text-[12px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20 disabled:cursor-not-allowed disabled:opacity-50"
                        >
                          {creatingSupplier ? "Saving..." : "Save and use"}
                        </button>
                      </div>
                    ) : (
                      <button
                        type="button"
                        onClick={() => {
                          setNewSupplierName(supplierQuery.trim());
                          setNewSupplierOpen(true);
                        }}
                        className="focus-ring mt-1 flex w-full cursor-pointer items-center gap-2 rounded-lg border-t border-[var(--border-soft)] px-2.5 py-2 text-[11.5px] font-bold text-[var(--primary-hover)] hover:bg-[var(--bg-base)]"
                      >
                        <Plus className="h-3.5 w-3.5" />
                        {supplierQuery.trim()
                          ? `Add "${supplierQuery.trim()}" as a new supplier`
                          : "Add a new supplier"}
                      </button>
                    )}
                  </div>
                )}
              </div>

              {chosenSupplier?.phone && (
                <p className="m-0 mt-1.5 font-mono text-[11px] text-[var(--text-tertiary)]">
                  {chosenSupplier.phone}
                </p>
              )}
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
            <ItemLinesEditor
              items={items}
              lines={draftLines}
              onChange={setDraftLines}
              openLine={openLine}
              onOpenLine={setOpenLine}
            />
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

