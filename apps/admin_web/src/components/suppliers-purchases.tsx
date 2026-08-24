"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  Truck,
  Plus,
  Building,
  X,
} from "lucide-react";
import { formatCurrency, formatDate } from "@/lib/utils";

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

  // New PO form
  const [poSupplierId, setPoSupplierId] = useState(suppliers[0]?.id || "");
  const [poInvoiceNo, setPoInvoiceNo] = useState("");
  const [poTotalAmount, setPoTotalAmount] = useState("");
  const [poPaidAmount, setPoPaidAmount] = useState("");

  // New Supplier form
  const [supName, setSupName] = useState("");
  const [supContact, setSupContact] = useState("");
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

  const handleCreatePo = async (e: React.FormEvent) => {
    e.preventDefault();
    const sup = suppliers.find((s) => s.id === poSupplierId);
    const total = parseFloat(poTotalAmount) || 0;
    const paid = parseFloat(poPaidAmount) || 0;

    // The label says "Supplier *", and it meant nothing: supplier_id fell
    // through as null and the purchase was filed against no vendor at all.
    if (!sup) {
      setSaveError("Choose the supplier this invoice came from.");
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
          purchase_date: new Date().toISOString().slice(0, 10),
          // One summary line for the whole invoice, matching what the mobile
          // app sends: the backend requires at least one item, and this form
          // records an invoice total rather than a line-by-line delivery.
          items: [
            {
              name: invoice || "Stock purchase",
              quantity: "1",
              unit_cost: total.toFixed(2),
            },
          ],
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => null);
        throw new Error(body?.error || `Could not save the purchase (${res.status})`);
      }
      setIsNewPoOpen(false);
      setPoInvoiceNo("");
      setPoTotalAmount("");
      setPoPaidAmount("");
      // Re-read rather than patch local state: the supplier's payable balance
      // is recalculated server-side from its ledger.
      await load();
    } catch (err) {
      setSaveError(errorMessage(err, "Could not save the purchase."));
    } finally {
      setIsSaving(false);
    }
  };

  const handleCreateSupplier = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    setSaveError(null);
    try {
      const res = await fetch("/api/suppliers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: supName.trim(),
          phone: supPhone.trim(),
          gstin: supGstin.trim(),
          address: supAddress.trim(),
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => null);
        throw new Error(body?.error || `Could not save the supplier (${res.status})`);
      }
      setIsNewSupplierOpen(false);
      setSupName("");
      setSupContact("");
      setSupPhone("");
      setSupGstin("");
      setSupAddress("");
      await load();
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
                  return (
                    <tr key={po.id} className="hover:bg-bg-base transition-colors">
                      <td className="py-3 px-4 font-mono font-semibold text-text-primary">
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
              onClick={() => setIsNewSupplierOpen(true)}
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
                  {sup.gstin && <div>GSTIN: {sup.gstin}</div>}
                  {sup.address && <div>Address: {sup.address}</div>}
                </div>
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
                <select
                  value={poSupplierId}
                  onChange={(e) => setPoSupplierId(e.target.value)}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                >
                  {/* Without this the browser renders the FIRST supplier as
                      selected while React's value is still "", because the
                      state was initialised before suppliers finished loading.
                      The shopkeeper saw a vendor highlighted, saved, and the
                      purchase was recorded against nobody — quietly wrong in
                      the payables ledger. */}
                  <option value="">Choose a supplier…</option>
                  {suppliers.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.name}
                    </option>
                  ))}
                </select>
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

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Total Inward Bill (₹) *
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    required
                    value={poTotalAmount}
                    onChange={(e) => setPoTotalAmount(e.target.value)}
                    placeholder="₹0.00"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
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
          onClick={() => setIsNewSupplierOpen(false)}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-[var(--bg-soft)]">
              <div className="flex items-center gap-2">
                <Building className="w-5 h-5 text-[var(--primary-light)]" />
                <span className="font-semibold text-sm text-text-primary">Add New Supplier</span>
              </div>
              <button
                onClick={() => setIsNewSupplierOpen(false)}
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
                    Contact Person
                  </label>
                  <input
                    type="text"
                    value={supContact}
                    onChange={(e) => setSupContact(e.target.value)}
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
                  onClick={() => setIsNewSupplierOpen(false)}
                  className="px-4 py-2 text-xs text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSaving}
                  className="px-5 py-2 text-xs font-semibold text-[var(--primary-dark)] bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 rounded-xl shadow-md disabled:opacity-50 border border-[var(--primary)]/25"
                >
                  {isSaving ? "Saving…" : "Save Supplier"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
