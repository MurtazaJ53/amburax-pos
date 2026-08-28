"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import { fetchAllPages } from "@/lib/fetch-all";
import {
  Truck,
  Plus,
  Building,
  X,
} from "lucide-react";
import { formatCurrency, formatDate } from "@/lib/utils";
import {
  BLANK_LINE,
  type DraftLine,
  type StockItem,
  linesSubtotal,
  readStockItems,
  toPayload,
  validateLines,
} from "@/lib/item-lines";
import { ItemLinesEditor } from "@/components/ui/item-lines-editor";
import { useServerRefresh } from "@/lib/use-server-refresh";
import { todayKey } from "@/lib/local-date";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



export interface SupplierRecord {
  id: string;
  shop?: string;
  name: string;
  contact_person?: string;
  phone: string;
  email?: string;
  gstin?: string;
  address?: string;
  balance_due: number;
  created_at: string;
}

export interface BillLine {
  id: string;
  name: string;
  sku: string;
  quantity: number;
  unit_cost: number;
  line_total: number;
  /** False for a bill booked before lines named real products - those moved
   *  no stock, and saying so is more use than showing a blank. */
  linked: boolean;
}

export interface PurchaseOrderRecord {
  id: string;
  shop?: string;
  supplier_id: string;
  supplier_name: string;
  invoice_number: string;
  total_amount: number;
  paid_amount: number;
  status: "received" | "draft" | "ordered" | "cancelled" | string;
  items_count: number;
  created_at: string;
}

function num(value: unknown): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = parseFloat(String(value ?? "0"));
  return Number.isFinite(parsed) ? parsed : 0;
}

/** The API may hand back a bare array or a {results: []} envelope. */
function asArray<T>(value: unknown): T[] {
  if (Array.isArray(value)) return value as T[];
  const results = (value as { results?: unknown })?.results;
  return Array.isArray(results) ? (results as T[]) : [];
}

/** Read a string field from a loosely-typed API row. */
function text(value: unknown, fallback = ""): string {
  return typeof value === "string" && value ? value : fallback;
}

function toSupplier(row: Record<string, unknown>): SupplierRecord {
  return {
    id: String(row.id),
    name: text(row.name, "Unnamed supplier"),
    // The backend has no contact_person column; showing an empty line is
    // honest, inventing a name is not.
    contact_person: "",
    phone: text(row.phone, ""),
    email: text(row.email, ""),
    gstin: text(row.gstin, ""),
    address: text(row.address, ""),
    balance_due: num(row.balance),
    created_at: text(row.created_at, ""),
  };
}

function toPurchase(row: Record<string, unknown>): PurchaseOrderRecord {
  return {
    id: String(row.id),
    supplier_id: row.supplier_id ? String(row.supplier_id) : "",
    supplier_name: text(row.supplier_name, "Supplier"),
    invoice_number: text(row.invoice_number) || text(row.reference, "-"),
    total_amount: num(row.total_amount),
    paid_amount: num(row.amount_paid),
    status: row.status === "void" ? "cancelled" : "received",
    items_count: num(row.item_count),
    created_at: text(row.purchase_date) || text(row.occurred_at),
  };
}

export function SuppliersPurchases({ initialTab = "purchases" }: { initialTab?: "purchases" | "suppliers" } = {}) {
  const refreshServerData = useServerRefresh();
  const [suppliers, setSuppliers] = useState<SupplierRecord[]>([]);
  const [purchases, setPurchases] = useState<PurchaseOrderRecord[]>([]);
  const [outstandingPayable, setOutstandingPayable] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"purchases" | "suppliers">(initialTab);
  const [_search, _setSearch] = useState("");

  // Modals
  const [isNewPoOpen, setIsNewPoOpen] = useState(false);
  const [isNewSupplierOpen, setIsNewSupplierOpen] = useState(false);
  // The id being corrected, or null when adding. One dialog serves both: a
  // separate edit form is a second place for the field list to go stale.
  const [editingSupplierId, setEditingSupplierId] = useState<string | null>(null);
  // What was actually on a bill. The list only ever carried a count, so a
  // delivery entered line by line could never be read back - and a wrong
  // line is only ever spotted by reading it back.
  const [openBill, setOpenBill] = useState<string | null>(null);
  const [billLines, setBillLines] = useState<Record<string, BillLine[] | "loading" | "error">>({});

  // New PO form
  const [poSupplierId, setPoSupplierId] = useState(suppliers[0]?.id || "");
  const [supplierQuery, setSupplierQuery] = useState("");
  const [supplierListOpen, setSupplierListOpen] = useState(false);
  const [poInvoiceNo, setPoInvoiceNo] = useState("");
  const [poPaidAmount, setPoPaidAmount] = useState("");
  // The bill is entered line by line against real stock, so the total is
  // worked out rather than typed: a typed total that disagrees with the
  // lines is a bill whose money and whose stock tell different stories.
  const [stockItems, setStockItems] = useState<StockItem[]>([]);
  const [draftLines, setDraftLines] = useState<DraftLine[]>([{ ...BLANK_LINE }]);
  const [openLine, setOpenLine] = useState<number | null>(null);
  const [stockError, setStockError] = useState<string | null>(null);
  const poTotal = linesSubtotal(draftLines);

  // New Supplier form
  const [supName, setSupName] = useState("");
  const [supEmail, setSupEmail] = useState("");
  const [supPhone, setSupPhone] = useState("");
  const [supGstin, setSupGstin] = useState("");
  const [supAddress, setSupAddress] = useState("");

  const load = useCallback(async () => {
    setIsLoading(true);
    setLoadError(null);
    try {
      const [supRes, purRes] = await Promise.all([
        fetch("/api/suppliers"),
        fetch("/api/purchases"),
      ]);
      if (!supRes.ok) throw new Error(`Could not load suppliers (${supRes.status})`);
      if (!purRes.ok) throw new Error(`Could not load purchases (${purRes.status})`);

      const supBody = await supRes.json();
      const purBody = await purRes.json();
      setSuppliers(asArray<Record<string, unknown>>(supBody.items).map(toSupplier));
      setPurchases(asArray<Record<string, unknown>>(purBody.items).map(toPurchase));
      // Prefer the server's own total over one summed in the browser: the
      // browser only sees the rows it loaded.
      setOutstandingPayable(
        purBody.summary ? num(purBody.summary.outstanding_payable) : null
      );
    } catch (err) {
      setLoadError(errorMessage(err, "Something went wrong loading suppliers."));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const totalPayables = useMemo(() => {
    if (outstandingPayable !== null) return outstandingPayable;
    return suppliers.reduce((sum, s) => sum + (s.balance_due || 0), 0);
  }, [suppliers, outstandingPayable]);

  useEffect(() => {
    if (!supplierListOpen) return;
    const close = () => setSupplierListOpen(false);
    // Captured on the document, and the picker stops its own clicks below,
    // so choosing from the list does not close it before the click lands.
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [supplierListOpen]);

  const chosenSupplier = suppliers.find((s) => s.id === poSupplierId) ?? null;
  /** Matched on name, phone or GSTIN - a shopkeeper reaches for whichever of
   *  the three they remember. Capped, because this is a picker and not a
   *  directory. */
  const supplierMatches = (() => {
    const q = supplierQuery.trim().toLowerCase();
    const pool = q
      ? suppliers.filter(
          (s) =>
            s.name.toLowerCase().includes(q) ||
            (s.phone ?? "").toLowerCase().includes(q) ||
            (s.gstin ?? "").toLowerCase().includes(q),
        )
      : suppliers;
    return pool.slice(0, 8);
  })();

  // Loaded when the bill opens rather than on mount: the picker is only
  // needed by this one dialog, and the catalogue is a few hundred rows.
  useEffect(() => {
    if (!isNewPoOpen) return;
    let cancelled = false;
    (async () => {
      try {
        // Every page. Half a catalogue in the picker means a purchase gets
        // recorded against the wrong product, or not recorded at all.
        const rows = readStockItems(await fetchAllPages("/api/inventory"));
        if (cancelled) return;
        setStockItems(rows);
        // Said out loud. An empty picker with no explanation is why the
        // purchase-order screen looked broken rather than merely unloaded.
        setStockError(
          rows.length === 0 ? "No products in stock yet. Add them in Stock first." : null,
        );
      } catch (err) {
        if (!cancelled) setStockError(errorMessage(err, "Could not load your stock."));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [isNewPoOpen]);

  const handleCreatePo = async (e: React.FormEvent) => {
    e.preventDefault();
    const sup = suppliers.find((s) => s.id === poSupplierId);
    const paid = parseFloat(poPaidAmount) || 0;

    // The label says "Supplier *", and it meant nothing: supplier_id fell
    // through as null and the purchase was filed against no vendor at all.
    if (!sup) {
      setSaveError("Choose the supplier this invoice came from.");
      return;
    }

    // Every line must name a product in stock. Without one the backend books
    // the money owed and nothing else - no stock, no cost price, no price
    // history - which is exactly what this screen used to do.
    const lineProblem = validateLines(draftLines);
    if (lineProblem) {
      setSaveError(lineProblem);
      return;
    }

    setIsSaving(true);
    setSaveError(null);
    try {
      const invoice = poInvoiceNo.trim();
      const res = await fetch("/api/purchases", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          supplier_id: sup.id,
          supplier_name: sup.name,
          invoice_number: invoice,
          amount_paid: paid.toFixed(2),
          payment_mode: "CASH",
          purchase_date: todayKey(),
          // The real lines. Each one carries the stock item it belongs to,
          // which is what moves stock, rewrites the cost price, stamps the
          // supplier and date on the product, and feeds Supplier prices.
          items: toPayload(draftLines, stockItems),
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => null);
        throw new Error(body?.error || `Could not save the purchase (${res.status})`);
      }
      setIsNewPoOpen(false);
      setPoInvoiceNo("");
      setPoPaidAmount("");
      setDraftLines([{ ...BLANK_LINE }]);
      // Re-read rather than patch local state: the supplier's payable balance
      // is recalculated server-side from its ledger.
      await load();
      refreshServerData();
    } catch (err) {
      setSaveError(errorMessage(err, "Could not save the purchase."));
    } finally {
      setIsSaving(false);
    }
  };

  const toggleBill = async (id: string) => {
    if (openBill === id) {
      setOpenBill(null);
      return;
    }
    setOpenBill(id);
    if (billLines[id] && billLines[id] !== "error") return;
    setBillLines((prev) => ({ ...prev, [id]: "loading" }));
    try {
      const res = await fetch(`/api/purchases/${id}`);
      if (!res.ok) throw new Error(String(res.status));
      const body = await res.json();
      const rows = Array.isArray(body?.items) ? body.items : [];
      setBillLines((prev) => ({
        ...prev,
        [id]: rows.map((raw: Record<string, unknown>) => ({
          id: String(raw.id),
          name: String(raw.name ?? ""),
          sku: String(raw.sku ?? ""),
          quantity: Number(raw.quantity ?? 0),
          unit_cost: Number(raw.unit_cost ?? 0),
          line_total: Number(raw.line_total ?? 0),
          linked: raw.inventory_item_id != null,
        })),
      }));
    } catch {
      setBillLines((prev) => ({ ...prev, [id]: "error" }));
    }
  };

  const closeSupplierDialog = () => {
    setIsNewSupplierOpen(false);
    setEditingSupplierId(null);
    setSaveError(null);
  };

  const handleCreateSupplier = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    setSaveError(null);
    try {
      // Correcting a vendor rather than adding one. Without this the only
      // way past a mistyped number was a second record for the same vendor,
      // which splits their balance and their price history in two.
      const editing = editingSupplierId !== null;
      const res = await fetch(
        editing ? `/api/suppliers/${editingSupplierId}` : "/api/suppliers",
        {
        method: editing ? "PATCH" : "POST",
        headers: { "Content-Type": "application/json" },
        // email was never sent, and "Contact Person" was collected into a
        // field with nowhere to go - typed at the counter and dropped on
        // save. The model has always had email; it simply was not asked for.
        body: JSON.stringify({
          name: supName.trim(),
          phone: supPhone.trim(),
          email: supEmail.trim(),
          gstin: supGstin.trim(),
          address: supAddress.trim(),
        }),
      },
      );
      if (!res.ok) {
        const body = await res.json().catch(() => null);
        throw new Error(body?.error || `Could not save the supplier (${res.status})`);
      }
      // If this was opened from the invoice form, go back to it with the
      // new supplier already selected.
      const created = await res.json().catch(() => null);
      setIsNewSupplierOpen(false);
      if (!editing && created?.id) {
        setPoSupplierId(String(created.id));
        setSupplierQuery("");
        setSupplierListOpen(false);
        setIsNewPoOpen(true);
      }
      setEditingSupplierId(null);
      setSupName("");
      setSupEmail("");
      setSupPhone("");
      setSupGstin("");
      setSupAddress("");
      await load();
      refreshServerData();
    } catch (err) {
      setSaveError(errorMessage(err, "Could not save the supplier."));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="space-y-6">
      {(loadError || saveError) && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {loadError || saveError}
        </div>
      )}
      {isLoading && (
        <div className="rounded-2xl border border-border-soft bg-surface px-5 py-4 text-sm font-semibold text-[var(--text-secondary)]">
          Loading suppliers and purchases&hellip;
        </div>
      )}

      {/* Top Controls */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-text-primary tracking-tight">
            Suppliers & Inward Purchase Orders
          </h2>
          <p className="text-xs text-[var(--text-tertiary)]">
            Manage vendor accounts, record inventory deliveries, and monitor payables
          </p>
        </div>

        <div className="flex items-center gap-3">
          <div className="px-4 py-2 bg-[var(--error)]/10 border border-[var(--error)]/20 rounded-xl flex items-center gap-2 text-xs">
            <span className="text-[var(--text-secondary)]">Total Vendor Payables:</span>
            <span className="font-bold text-[var(--error)] font-mono">
              {formatCurrency(totalPayables)}
            </span>
          </div>

          <button
            onClick={() => setIsNewPoOpen(true)}
            className="flex items-center gap-1.5 px-4 py-2 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-semibold rounded-xl shadow-md shadow-blue-500/20"
          >
            <Plus className="w-4 h-4" />
            <span>Record Inward PO</span>
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 border-b border-[var(--border-soft)]">
        <button
          onClick={() => setActiveTab("purchases")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors ${
            activeTab === "purchases"
              ? "border-[var(--primary)] text-text-primary"
              : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
          }`}
        >
          Purchase Inwards ({purchases.length})
        </button>
        <button
          onClick={() => setActiveTab("suppliers")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors ${
            activeTab === "suppliers"
              ? "border-[var(--primary)] text-text-primary"
              : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
          }`}
        >
          Supplier Directory ({suppliers.length})
        </button>
      </div>

      {activeTab === "purchases" ? (
        /* Purchase Orders Table */
        <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl overflow-hidden shadow-xl">
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-[var(--bg-soft)] border-b border-[var(--border-soft)] text-[var(--text-tertiary)] font-semibold uppercase tracking-wider text-[10px]">
                  <th className="py-3 px-4">Invoice / PO #</th>
                  <th className="py-3 px-4">Date</th>
                  <th className="py-3 px-4">Supplier</th>
                  <th className="py-3 px-4 text-center">Status</th>
                  <th className="py-3 px-4 text-right">Total Inward</th>
                  <th className="py-3 px-4 text-right">Paid Amount</th>
                  <th className="py-3 px-4 text-right">Balance Due</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-soft)]">
                {purchases.map((po) => {
                  const due = po.total_amount - po.paid_amount;
                  const lines = billLines[po.id];
                  const isOpen = openBill === po.id;
                  return (
                    <React.Fragment key={po.id}>
                    <tr
                      className="cursor-pointer transition-colors hover:bg-bg-base"
                      onClick={() => void toggleBill(po.id)}
                    >
                      <td className="py-3 px-4 font-mono font-semibold text-text-primary">
                        <span className="mr-1.5 inline-block text-[var(--text-tertiary)]">
                          {isOpen ? "−" : "+"}
                        </span>
                        {po.invoice_number}
                      </td>
                      <td className="py-3 px-4 text-[var(--text-tertiary)]">
                        {formatDate(po.created_at)}
                      </td>
                      <td className="py-3 px-4 text-text-primary font-medium">{po.supplier_name}</td>
                      <td className="py-3 px-4 text-center">
                        <span className="px-2 py-0.5 rounded text-[10px] font-bold uppercase bg-[var(--success)]/20 text-[var(--success)]">
                          {po.status}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-right font-mono text-text-primary font-semibold">
                        {formatCurrency(po.total_amount)}
                      </td>
                      <td className="py-3 px-4 text-right font-mono text-[var(--success)]">
                        {formatCurrency(po.paid_amount)}
                      </td>
                      <td className="py-3 px-4 text-right font-mono font-bold">
                        <span className={due > 0 ? "text-[var(--error)]" : "text-[var(--text-tertiary)]"}>
                          {formatCurrency(due)}
                        </span>
                      </td>
                    </tr>

                    {isOpen && (
                      <tr>
                        <td colSpan={7} className="bg-[var(--bg-soft)] px-4 py-3">
                          {lines === "loading" && (
                            <p className="m-0 text-[11.5px] font-semibold text-[var(--text-tertiary)]">
                              Reading the bill…
                            </p>
                          )}
                          {lines === "error" && (
                            <p className="m-0 text-[11.5px] font-semibold text-[var(--error-strong)]">
                              Could not read what was on this bill.
                            </p>
                          )}
                          {Array.isArray(lines) && lines.length === 0 && (
                            <p className="m-0 text-[11.5px] font-semibold text-[var(--text-tertiary)]">
                              No lines were recorded on this bill.
                            </p>
                          )}
                          {Array.isArray(lines) && lines.length > 0 && (
                            <div className="space-y-1.5">
                              {lines.map((line) => (
                                <div
                                  key={line.id}
                                  className="flex flex-wrap items-baseline gap-x-3 gap-y-1"
                                >
                                  <span className="min-w-0 flex-1 truncate text-[12px] font-bold text-text-primary">
                                    {line.name || "Unnamed"}
                                    {line.sku ? (
                                      <span className="ml-1.5 font-mono text-[10px] font-semibold text-[var(--text-tertiary)]">
                                        {line.sku}
                                      </span>
                                    ) : null}
                                  </span>
                                  {/* Said out loud, because it is the whole
                                      difference: a line with no product moved
                                      no stock and set no cost price. */}
                                  {!line.linked && (
                                    <span className="rounded border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-1.5 py-0.5 text-[9.5px] font-bold uppercase tracking-wide text-[var(--warning-strong)]">
                                      No stock moved
                                    </span>
                                  )}
                                  <span className="tnum font-mono text-[11.5px] font-semibold text-[var(--text-secondary)]">
                                    {line.quantity} × {formatCurrency(line.unit_cost)}
                                  </span>
                                  <span className="tnum font-mono text-[12px] font-bold text-text-primary">
                                    {formatCurrency(line.line_total)}
                                  </span>
                                </div>
                              ))}
                            </div>
                          )}
                        </td>
                      </tr>
                    )}
                    </React.Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        /* Supplier Directory Table */
        <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl overflow-hidden shadow-xl space-y-4 p-4">
          <div className="flex justify-end">
            <button
              onClick={() => {
                setEditingSupplierId(null);
                setSupName("");
                setSupEmail("");
                setSupPhone("");
                setSupGstin("");
                setSupAddress("");
                setSaveError(null);
                setIsNewSupplierOpen(true);
              }}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-bg-base hover:bg-[var(--surface)] border border-[var(--border-soft)] text-xs text-text-primary rounded-xl"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>Add Supplier</span>
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {suppliers.map((sup) => (
              <div
                key={sup.id}
                className="p-4 bg-[var(--bg-soft)] border border-[var(--border-soft)] rounded-xl space-y-2"
              >
                <div className="flex items-start justify-between">
                  <div>
                    <h4 className="text-sm font-bold text-text-primary">{sup.name}</h4>
                    <div className="text-[11px] text-[var(--text-tertiary)]">
                      Contact: {sup.contact_person || "—"}
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-xs font-mono font-bold text-[var(--error)]">
                      {formatCurrency(sup.balance_due || 0)}
                    </div>
                    <div className="text-[9px] uppercase font-semibold text-[var(--text-tertiary)]">
                      Payable Due
                    </div>
                  </div>
                </div>

                <div className="text-xs text-[var(--text-secondary)] space-y-1 pt-2 border-t border-[var(--border-soft)]">
                  {sup.phone && <div>Phone: {sup.phone}</div>}
                  {sup.email && <div>Email: {sup.email}</div>}
                  {sup.gstin && <div>GSTIN: {sup.gstin}</div>}
                  {sup.address && <div>Address: {sup.address}</div>}
                </div>

                <button
                  type="button"
                  onClick={() => {
                    setEditingSupplierId(sup.id);
                    setSupName(sup.name ?? "");
                    setSupEmail(sup.email ?? "");
                    setSupPhone(sup.phone ?? "");
                    setSupGstin(sup.gstin ?? "");
                    setSupAddress(sup.address ?? "");
                    setSaveError(null);
                    setIsNewSupplierOpen(true);
                  }}
                  className="focus-ring cursor-pointer text-[11.5px] font-bold text-[var(--primary-hover)] hover:underline"
                >
                  Edit details
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* MODAL: Record Inward PO */}
      {isNewPoOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in duration-150"
          onClick={() => setIsNewPoOpen(false)}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-[var(--bg-soft)]">
              <div className="flex items-center gap-2">
                <Truck className="w-5 h-5 text-[var(--primary-light)]" />
                <span className="font-semibold text-sm text-text-primary">Record Inward Delivery</span>
              </div>
              <button
                onClick={() => setIsNewPoOpen(false)}
                className="p-1 text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleCreatePo} className="p-6 space-y-4">
              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Supplier *
                </label>

                {/* Type to find, rather than scroll a list. A shop with forty
                    vendors could only reach one by scrolling a native select,
                    and there was no way to add a new one without abandoning
                    the invoice being entered. */}
                <div
                  className="relative"
                  onMouseDown={(e) => e.stopPropagation()}
                >
                  <input
                    type="text"
                    value={chosenSupplier ? chosenSupplier.name : supplierQuery}
                    onChange={(e) => {
                      setSupplierQuery(e.target.value);
                      setPoSupplierId("");
                    }}
                    onFocus={() => setSupplierListOpen(true)}
                    placeholder="Type a supplier name"
                    className="w-full rounded-xl border border-[var(--border-soft)] bg-bg-soft px-3 py-2 text-xs text-text-primary outline-none focus:border-[var(--primary)]"
                  />
                  {chosenSupplier && (
                    <button
                      type="button"
                      onClick={() => {
                        setPoSupplierId("");
                        setSupplierQuery("");
                        setSupplierListOpen(true);
                      }}
                      aria-label="Choose a different supplier"
                      className="focus-ring absolute right-2 top-1/2 grid h-6 w-6 -translate-y-1/2 cursor-pointer place-items-center rounded-full text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  )}

                  {supplierListOpen && !chosenSupplier && (
                    <div className="animate-fade-in-up absolute left-0 right-0 top-full z-30 mt-1 max-h-[220px] overflow-y-auto rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-1 shadow-lg">
                      {supplierMatches.map((s) => (
                        <button
                          key={s.id}
                          type="button"
                          onClick={() => {
                            setPoSupplierId(s.id);
                            setSupplierListOpen(false);
                          }}
                          className="focus-ring flex w-full cursor-pointer items-center gap-2 rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-[var(--bg-base)]"
                        >
                          <span className="min-w-0 flex-1">
                            <span className="block truncate text-[12px] font-bold text-text-primary">
                              {s.name}
                            </span>
                            <span className="block truncate font-mono text-[10px] text-[var(--text-tertiary)]">
                              {s.phone || "no phone"}
                              {s.gstin ? ` · ${s.gstin}` : ""}
                            </span>
                          </span>
                          {s.balance_due > 0 && (
                            <span className="tnum shrink-0 font-mono text-[10.5px] font-bold text-[var(--warning-strong)]">
                              {formatCurrency(s.balance_due)} due
                            </span>
                          )}
                        </button>
                      ))}

                      {/* A vendor you have never bought from before should not
                          mean abandoning the invoice you are entering. */}
                      <button
                        type="button"
                        onClick={() => {
                          // Adding, never editing: this path exists so a new
                          // vendor does not mean abandoning the invoice.
                          setEditingSupplierId(null);
                          setSupName(supplierQuery.trim());
                          setIsNewPoOpen(false);
                          setIsNewSupplierOpen(true);
                        }}
                        className="focus-ring mt-1 flex w-full cursor-pointer items-center gap-2 rounded-lg border-t border-[var(--border-soft)] px-2.5 py-2 text-[11.5px] font-bold text-[var(--primary-hover)] hover:bg-[var(--bg-base)]"
                      >
                        <Plus className="h-3.5 w-3.5" />
                        {supplierQuery.trim()
                          ? `Add "${supplierQuery.trim()}" as a new supplier`
                          : "Add a new supplier"}
                      </button>
                    </div>
                  )}
                </div>

                {/* Who you actually picked, so a near-identical name is
                    caught before the invoice is filed against it. */}
                {chosenSupplier && (
                  <p className="m-0 mt-1.5 text-[11px] font-medium text-[var(--text-tertiary)]">
                    {chosenSupplier.phone || "no phone"}
                    {chosenSupplier.gstin ? ` · ${chosenSupplier.gstin}` : ""}
                    {chosenSupplier.balance_due > 0
                      ? ` · ${formatCurrency(chosenSupplier.balance_due)} already owed`
                      : ""}
                  </p>
                )}
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Vendor Invoice / Challan Number *
                </label>
                <input
                  type="text"
                  required
                  value={poInvoiceNo}
                  onChange={(e) => setPoInvoiceNo(e.target.value)}
                  placeholder="e.g. INV-2026-901"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>

              <div>
                <div className="mb-1 flex items-baseline justify-between gap-3">
                  <label className="block text-xs font-semibold text-[var(--text-secondary)]">
                    What arrived *
                  </label>
                  {/* Said plainly, because this is the whole point of the
                      screen: these lines are what move stock. */}
                  <span className="text-[11px] font-semibold text-[var(--text-tertiary)]">
                    Each line adds to stock and updates its cost
                  </span>
                </div>
                {stockError && (
                  <p className="mb-2 rounded-xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-3 py-2 text-[11.5px] font-semibold text-[var(--warning-strong)]">
                    {stockError}
                  </p>
                )}
                <ItemLinesEditor
                  items={stockItems}
                  lines={draftLines}
                  onChange={setDraftLines}
                  openLine={openLine}
                  onOpenLine={setOpenLine}
                  quantityLabel="Arrived"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Bill total (₹)
                  </label>
                  {/* Added up from the lines, not typed. A typed total that
                      disagrees with the lines is a bill whose money and whose
                      stock tell two different stories. */}
                  <output className="tnum block w-full rounded-xl border border-[var(--border-soft)] bg-bg-base px-3 py-2 font-mono text-xs font-bold text-text-primary">
                    {formatCurrency(poTotal)}
                  </output>
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Amount Paid Today (₹)
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    value={poPaidAmount}
                    onChange={(e) => setPoPaidAmount(e.target.value)}
                    placeholder="₹0.00"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
              </div>

              <div className="pt-3 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setIsNewPoOpen(false)}
                  className="px-4 py-2 text-xs text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSaving}
                  className="px-5 py-2 text-xs font-semibold text-[var(--primary-dark)] bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 rounded-xl shadow-md disabled:opacity-50 border border-[var(--primary)]/25"
                >
                  {isSaving ? "Saving…" : "Record Inward Stock"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* MODAL: Add New Supplier */}
      {isNewSupplierOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in duration-150"
          onClick={closeSupplierDialog}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-[var(--bg-soft)]">
              <div className="flex items-center gap-2">
                <Building className="w-5 h-5 text-[var(--primary-light)]" />
                <span className="font-semibold text-sm text-text-primary">
                    {editingSupplierId ? "Edit supplier" : "Add new supplier"}
                  </span>
              </div>
              <button
                onClick={closeSupplierDialog}
                className="p-1 text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleCreateSupplier} className="p-6 space-y-4">
              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Supplier / Company Name *
                </label>
                <input
                  type="text"
                  required
                  value={supName}
                  onChange={(e) => setSupName(e.target.value)}
                  placeholder="e.g. Royal Spices & Herbs"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Email
                  </label>
                  <input
                    type="email"
                    inputMode="email"
                    value={supEmail}
                    onChange={(e) => setSupEmail(e.target.value)}
                    placeholder="Manoj"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Phone
                  </label>
                  <input
                    type="tel"
                    value={supPhone}
                    onChange={(e) => setSupPhone(e.target.value)}
                    placeholder="+91 98000 00000"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  GSTIN
                </label>
                <input
                  type="text"
                  value={supGstin}
                  onChange={(e) => setSupGstin(e.target.value)}
                  placeholder="27AABCR..."
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Address
                </label>
                <input
                  type="text"
                  value={supAddress}
                  onChange={(e) => setSupAddress(e.target.value)}
                  placeholder="Market Godown Address"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>

              <div className="pt-3 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={closeSupplierDialog}
                  className="px-4 py-2 text-xs text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSaving}
                  className="px-5 py-2 text-xs font-semibold text-[var(--primary-dark)] bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 rounded-xl shadow-md disabled:opacity-50 border border-[var(--primary)]/25"
                >
                  {isSaving ? "Saving…" : editingSupplierId ? "Save changes" : "Add supplier"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
