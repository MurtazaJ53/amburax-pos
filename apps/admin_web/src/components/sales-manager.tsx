"use client";

import { useT } from "@/lib/i18n";

import React, { useState, useMemo } from "react";
import {
  Receipt,
  Search,
  RotateCcw,
  Lock,
  Undo2,
} from "lucide-react";
import { formatCurrency, formatDate } from "@/lib/utils";
import { SaleReturnSheet } from "@/components/sale-return-sheet";
import { ThermalReceiptModal } from "@/components/thermal-receipt-modal";
import type { CartItem, SplitPaymentTender } from "@/lib/types";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



export interface SaleOrder {
  id: string;
  receipt_number: string;
  shop: string;
  cashier_name: string;
  customer_name?: string;
  customer_phone?: string;
  subtotal: number;
  tax_amount: number;
  discount_amount: number;
  total_amount: number;
  payment_mode: "cash" | "upi" | "card" | "khata" | string;
  payment_breakdown: SplitPaymentTender;
  status: string;
  items_count: number;
  /** The actual lines that were sold. Reprinted receipts used to show a
   *  hardcoded mock item, so every duplicate bill handed to a customer named a
   *  product they had not bought. */
  items: CartItem[];
  created_at: string;
}

interface SalesManagerProps {
  initialSales: ApiSale[];
  initialSummary?: unknown;
  shopId: string;
}

/** A sale row as the API returns it. Only the fields this screen reads. */
type ApiSalePayment = { payment_method: string; amount: string };
type ApiSale = {
  id: string;
  receipt_number?: string;
  shop?: string;
  actor_name?: string | null;
  customer_name?: string;
  customer_phone?: string;
  subtotal_amount?: string;
  tax_amount?: string;
  discount_amount?: string;
  total_amount?: string;
  payment_mode?: string;
  status?: string;
  item_count?: number;
  occurred_at?: string;
  payments?: ApiSalePayment[];
  items?: ApiSaleLine[];
};

/** One line of a sale, as DRF returns it.
 *
 *  Deliberately loose: DRF serialises DecimalField as a string, but the
 *  server-rendered page passes the already-typed SaleItem where quantity is a
 *  number. Accepting both keeps one mapping function for both entry points
 *  rather than two that can drift. */
type ApiSaleLine = {
  id: string;
  inventory_item_id?: string | null;
  name?: string;
  sku?: string;
  quantity?: number | string;
  unit_price?: string;
  line_total?: string;
  line_discount?: string;
  gst_rate?: string;
};

/** Total the tenders of one method. Amounts arrive as strings from DRF. */
function tenderTotal(payments: ApiSalePayment[], method: string): number {
  return payments
    .filter((p) => p.payment_method === method)
    .reduce((sum, p) => sum + (parseFloat(p.amount) || 0), 0);
}

/** Map one API sale onto the shape this screen renders. */
/** DRF sale line -> the cart shape the receipt component renders. */
function toReceiptLine(line: ApiSaleLine): CartItem {
  const quantity = Number(line.quantity ?? 0) || 0;
  const unitPrice = parseFloat(line.unit_price || "0") || 0;
  const discount = parseFloat(line.line_discount || "0") || 0;
  return {
    id: line.id,
    product_id: line.inventory_item_id || "",
    name: line.name || "Item",
    sku: line.sku || "",
    barcode: "",
    unit_price: unitPrice,
    cost_price: 0,
    quantity,
    tax_rate: parseFloat(line.gst_rate || "0") || 0,
    discount_amount: discount,
    total_price:
      parseFloat(line.line_total || "0") || quantity * unitPrice - discount,
    available_stock: 0,
  };
}

function toSaleOrder(item: ApiSale): SaleOrder {
  const payments = item.payments ?? [];
  return {
    id: item.id,
    receipt_number:
      item.receipt_number ||
      `INV-${item.id.replace(/-/g, "").slice(0, 6).toUpperCase()}`,
    shop: item.shop || "",
    cashier_name: item.actor_name || "Cashier",
    customer_name: item.customer_name || "Walk-in Guest",
    customer_phone: item.customer_phone || "",
    subtotal: parseFloat(item.subtotal_amount || "0"),
    tax_amount: parseFloat(item.tax_amount || "0"),
    discount_amount: parseFloat(item.discount_amount || "0"),
    total_amount: parseFloat(item.total_amount || "0"),
    payment_mode: (item.payment_mode || "cash").toLowerCase(),
    payment_breakdown: {
      cash: tenderTotal(payments, "CASH"),
      card: tenderTotal(payments, "CARD"),
      upi: tenderTotal(payments, "UPI"),
      khata_due: tenderTotal(payments, "CREDIT"),
    },
    status: item.status || "completed",
    items: (item.items ?? []).map(toReceiptLine),
    items_count: item.item_count || 1,
    created_at: item.occurred_at || new Date().toISOString(),
  } as SaleOrder;
}

export function SalesManager({ initialSales }: SalesManagerProps) {
  const t = useT();
  const mappedInitial = React.useMemo(() => {
    return (initialSales ?? []).map(toSaleOrder);
  }, [initialSales]);

  const [sales, setSales] = useState<SaleOrder[]>(mappedInitial);
  const [isLoading, setIsLoading] = useState(false);
  const [_error, setError] = useState<string | null>(null);
  
  const [search, setSearch] = useState("");
  const [paymentFilter, setPaymentFilter] = useState("all");
  const [activeView, setActiveView] = useState<"history" | "dayclose">("history");

  // Receipt Modal state
  const [viewingReceipt, setViewingReceipt] = useState<SaleOrder | null>(null);
  const [returningSaleId, setReturningSaleId] = useState<string | null>(null);

  // Day Close Form state
  const [openingCash] = useState(5000);
  const [actualCountedCash, setActualCountedCash] = useState("6450");
  const [dayCloseNotes, setDayCloseNotes] = useState("");
  const [isDayClosed, setIsDayClosed] = useState(false);

  async function fetchSales() {
    try {
      setIsLoading(true);
      const res = await fetch("/api/sales");
      if (!res.ok) throw new Error("Failed to load sales history");
      const data = await res.json();
      
      const mappedSales: SaleOrder[] = data.map(toSaleOrder);
      setSales(mappedSales);
    } catch (err) {
      setError(errorMessage(err, "Failed to load sales"));
    } finally {
      setIsLoading(false);
    }
  }

  const handleVoidSale = async (saleId: string) => {
    if (!confirm("Are you sure you want to void this sale? This will reverse the transaction and restock inventory.")) return;
    try {
      const res = await fetch(`/api/sales/${saleId}/void`, { method: "POST" });
      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || "Failed to void transaction");
      }
      await fetchSales();
    } catch (err) {
      alert(errorMessage(err, "An error occurred while voiding sale."));
    }
  };

  // Filtered sales
  const filteredSales = useMemo(() => {
    return sales.filter((s) => {
      if (paymentFilter !== "all" && s.payment_mode !== paymentFilter) return false;
      if (search.trim()) {
        const q = search.toLowerCase();
        return (
          s.receipt_number.toLowerCase().includes(q) ||
          (s.customer_name && s.customer_name.toLowerCase().includes(q))
        );
      }
      return true;
    });
  }, [sales, paymentFilter, search]);

  // Aggregate metrics
  const metrics = useMemo(() => {
    const totalRev = sales.reduce((sum, s) => sum + s.total_amount, 0);
    const count = sales.length;
    const aov = count > 0 ? totalRev / count : 0;
    const cashTotal = sales
      .filter((s) => s.payment_mode === "cash")
      .reduce((sum, s) => sum + s.total_amount, 0);
    const upiTotal = sales
      .filter((s) => s.payment_mode === "upi")
      .reduce((sum, s) => sum + s.total_amount, 0);
    const cardTotal = sales
      .filter((s) => s.payment_mode === "card")
      .reduce((sum, s) => sum + s.total_amount, 0);

    return { totalRev, count, aov, cashTotal, upiTotal, cardTotal };
  }, [sales]);

  // Day close calculations
  const expectedCashInDrawer = openingCash + metrics.cashTotal;
  const countedNum = parseFloat(actualCountedCash) || 0;
  const cashDifference = countedNum - expectedCashInDrawer;

  return (
    <div className="space-y-6">
      {/* Top Header & View Tabs */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-[var(--text-primary)] tracking-tight">
            Sales Orders & Register Reconciliation
          </h2>
          <p className="text-xs text-[var(--text-tertiary)]">
            Review past transactions, print tax invoices, and complete daily register close
          </p>
        </div>

        <div className="flex items-center p-1 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl">
          <button
            onClick={() => setActiveView("history")}
            className={`px-4 py-1.5 rounded-lg text-xs font-semibold transition-all ${
              activeView === "history"
                ? "bg-[var(--primary)] text-white shadow-sm"
                : "text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
            }`}
          >
            Sales History
          </button>
          <button
            onClick={() => setActiveView("dayclose")}
            className={`px-4 py-1.5 rounded-lg text-xs font-semibold transition-all ${
              activeView === "dayclose"
                ? "bg-[var(--primary)] text-white shadow-sm"
                : "text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
            }`}
          >
            Day Close Register
          </button>
        </div>
      </div>

      {activeView === "history" ? (
        <>
          {/* Metrics Summary Strip */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="p-4 bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl">
              <div className="text-xs text-[var(--text-tertiary)] font-medium">
                Today&apos;s Gross Sales
              </div>
              <div className="text-2xl font-black text-[var(--text-primary)] font-mono mt-1">
                {formatCurrency(metrics.totalRev)}
              </div>
              <div className="text-[11px] text-[var(--success-dark)] font-semibold mt-1">
                {metrics.count} completed orders
              </div>
            </div>

            <div className="p-4 bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl">
              <div className="text-xs text-[var(--text-tertiary)] font-medium">
                Average Order Value (AOV)
              </div>
              <div className="text-2xl font-black text-[var(--text-primary)] font-mono mt-1">
                {formatCurrency(metrics.aov)}
              </div>
              <div className="text-[11px] text-[var(--text-tertiary)] mt-1">
                Basket size per checkout
              </div>
            </div>

            <div className="p-4 bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl">
              <div className="text-xs text-[var(--text-tertiary)] font-medium">
                UPI vs Cash Collection
              </div>
              <div className="text-lg font-bold text-[var(--info-strong)] font-mono mt-1">
                UPI: {formatCurrency(metrics.upiTotal)} | Cash: {formatCurrency(metrics.cashTotal)}
              </div>
              <div className="text-[11px] text-[var(--text-tertiary)] mt-1">
                Card: {formatCurrency(metrics.cardTotal)}
              </div>
            </div>
          </div>

          {/* Filter Bar */}
          <div className="p-4 bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl flex flex-col md:flex-row items-center gap-3">
            <div className="relative flex-1 w-full">
              <Search className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search by invoice # or customer name..."
                className="w-full pl-10 pr-4 py-2 bg-[var(--surface-muted)] border border-[var(--border-soft)] focus:border-[var(--primary)] rounded-xl text-xs text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
              />
            </div>

            <select
              value={paymentFilter}
              onChange={(e) => setPaymentFilter(e.target.value)}
              className="px-3 py-2 bg-[var(--surface-muted)] border border-[var(--border-soft)] text-xs text-[var(--text-primary)] rounded-xl outline-none"
            >
              <option value="all">All Payment Methods</option>
              <option value="cash">Cash Only</option>
              <option value="upi">UPI / QR Only</option>
              <option value="card">Card Only</option>
              <option value="khata">Khata Credit Only</option>
            </select>
          </div>

          {/* Sales History Data Table */}
          <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl overflow-hidden shadow-xl">
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse text-xs">
                <thead>
                  <tr className="bg-[var(--bg-soft)] border-b border-[var(--border-soft)] text-[var(--text-tertiary)] font-semibold uppercase tracking-wider text-[10px]">
                    <th className="py-3 px-4">Invoice #</th>
                    <th className="py-3 px-4">Date & Time</th>
                    <th className="py-3 px-4">Customer</th>
                    <th className="py-3 px-4 text-center">Items</th>
                    <th className="py-3 px-4 text-center">Payment Mode</th>
                    <th className="py-3 px-4 text-right">GST Tax</th>
                    <th className="py-3 px-4 text-right">{t("webGrandTotal", "Grand Total")}</th>
                    <th className="py-3 px-4 text-right">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border-soft)] text-[var(--text-primary)]">
                   {isLoading ? (
                    <tr>
                      <td colSpan={8} className="py-12 text-center text-[var(--text-tertiary)]">
                        <div className="flex flex-col items-center gap-2">
                          <div className="w-6 h-6 border-2 border-[var(--info)]/30 border-t-transparent rounded-full animate-spin"></div>
                          <span>Loading transaction ledger...</span>
                        </div>
                      </td>
                    </tr>
                  ) : filteredSales.length === 0 ? (
                    <tr>
                      <td colSpan={8} className="py-12 text-center text-[var(--text-tertiary)]">
                        No sales found matching your criteria.
                      </td>
                    </tr>
                  ) : (
                    filteredSales.map((sale) => (
                      <tr key={sale.id} className="hover:bg-bg-base transition-colors">
                        <td className="py-3 px-4 font-mono font-semibold text-[var(--text-primary)]">
                          {sale.receipt_number}
                        </td>
                        <td className="py-3 px-4 text-[var(--text-tertiary)]">
                          {formatDate(sale.created_at, true)}
                        </td>
                        <td className="py-3 px-4">
                          <div className="font-semibold text-[var(--text-primary)]">{sale.customer_name}</div>
                          {sale.customer_phone && (
                            <div className="text-[10px] text-[var(--text-tertiary)]">
                              {sale.customer_phone}
                            </div>
                          )}
                        </td>
                        <td className="py-3 px-4 text-center font-mono text-[var(--text-secondary)]">
                          {sale.items_count}
                        </td>
                        <td className="py-3 px-4 text-center">
                          <span
                            className={`px-2 py-0.5 rounded text-[10px] font-bold uppercase ${
                              sale.payment_mode === "upi"
                                ? "bg-[var(--info)]/15 text-[var(--info-strong)] border border-[var(--info)]/30"
                                : sale.payment_mode === "cash"
                                ? "bg-[var(--success)]/15 text-[var(--success-strong)] border border-[var(--success)]/30"
                                : "bg-purple-100 text-purple-800 border border-purple-200"
                            }`}
                          >
                            {sale.payment_mode}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-right font-mono text-[var(--text-tertiary)]">
                          {formatCurrency(sale.tax_amount)}
                        </td>
                        <td className="py-3 px-4 text-right font-mono font-bold text-[var(--text-primary)]">
                          {formatCurrency(sale.total_amount)}
                        </td>
                        <td className="py-3 px-4 text-right">
                          <div className="flex items-center justify-end gap-2">
                            <button
                              onClick={() => setViewingReceipt(sale)}
                              className="inline-flex items-center gap-1 px-2.5 py-1 bg-[var(--surface-muted)] hover:bg-bg-base text-[var(--primary)] hover:text-[var(--primary-hover)] rounded-lg text-[11px] transition-colors border border-[var(--border-soft)]"
                            >
                              <Receipt className="w-3 h-3" />
                              <span>Invoice</span>
                            </button>

                            {sale.status === "voided" ? (
                              <span className="px-2 py-0.5 text-[10px] font-bold uppercase rounded bg-[var(--error)]/20 text-[var(--error)] border border-[var(--error)]/30">
                                Voided
                              </span>
                            ) : (
                              <>
                              {/* Return takes back individual lines and leaves
                                  the bill intact; Void cancels the whole sale.
                                  Different jobs, so both are offered. */}
                              <button
                                onClick={() => setReturningSaleId(sale.id)}
                                className="inline-flex items-center gap-1 px-2 py-1 bg-[var(--warning)]/10 hover:bg-[var(--warning)]/20 text-[var(--warning-strong)] rounded-lg text-[11px] transition-colors border border-[var(--warning)]/20"
                              >
                                <Undo2 className="w-3 h-3" />
                                <span>Return</span>
                              </button>
                              <button
                                onClick={() => handleVoidSale(sale.id)}
                                className="inline-flex items-center gap-1 px-2 py-1 bg-[var(--error)]/10 hover:bg-[var(--error)]/20 text-[var(--error)] hover:text-[var(--error)] rounded-lg text-[11px] transition-colors border border-[var(--error)]/20"
                              >
                                <RotateCcw className="w-3 h-3" />
                                <span>Void</span>
                              </button>
                              </>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </>
      ) : (
        /* ========================================================= */
        /* DAY CLOSE REGISTER AUDIT                                  */
        /* ========================================================= */
        <div className="max-w-2xl mx-auto bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl p-6 shadow-2xl space-y-6">
          <div className="flex items-center justify-between pb-4 border-b border-[var(--border-soft)]">
            <div className="flex items-center gap-2">
              <Lock className="w-5 h-5 text-[var(--warning-strong)]" />
              <div>
                <h3 className="font-bold text-sm text-[var(--text-primary)]">End of Day Register Close</h3>
                <div className="text-[11px] text-[var(--text-tertiary)]">
                  Session Date: {new Date().toLocaleDateString("en-IN", { dateStyle: "full" })}
                </div>
              </div>
            </div>
            {isDayClosed && (
              <span className="px-2.5 py-1 bg-[var(--success)]/15 text-[var(--success-strong)] border border-[var(--success)]/30 rounded-full text-xs font-bold">
                Day Closed & Locked
              </span>
            )}
          </div>

          <div className="space-y-3 bg-[var(--surface-muted)] p-4 rounded-xl border border-[var(--border-soft)] text-xs">
            <div className="flex justify-between py-1">
              <span className="text-[var(--text-tertiary)]">Opening Cash Float:</span>
              <span className="font-mono font-semibold text-[var(--text-primary)]">
                {formatCurrency(openingCash)}
              </span>
            </div>
            <div className="flex justify-between py-1 border-t border-[var(--border-soft)]">
              <span className="text-[var(--text-tertiary)]">+ Cash Sales Received:</span>
              <span className="font-mono font-semibold text-[var(--success-strong)]">
                +{formatCurrency(metrics.cashTotal)}
              </span>
            </div>
            <div className="flex justify-between py-1 border-t border-[var(--border-soft)]">
              <span className="text-[var(--text-tertiary)]">Digital UPI / QR Collections:</span>
              <span className="font-mono font-semibold text-[var(--info-strong)]">
                {formatCurrency(metrics.upiTotal)}
              </span>
            </div>
            <div className="flex justify-between py-1 border-t border-[var(--border-soft)]">
              <span className="text-[var(--text-tertiary)]">Card POS Collections:</span>
              <span className="font-mono font-semibold text-purple-600">
                {formatCurrency(metrics.cardTotal)}
              </span>
            </div>
            <div className="flex justify-between py-2 border-t border-[var(--border-soft)] font-bold text-sm text-[var(--text-primary)]">
              <span>Calculated Cash Expected in Till:</span>
              <span className="font-mono">{formatCurrency(expectedCashInDrawer)}</span>
            </div>
          </div>

          <div className="space-y-4">
            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Actual Physical Cash Counted (₹) *
              </label>
              <input
                type="number"
                disabled={isDayClosed}
                value={actualCountedCash}
                onChange={(e) => setActualCountedCash(e.target.value)}
                className="w-full px-4 py-2.5 bg-[var(--surface-muted)] border border-[var(--border-soft)] rounded-xl text-base font-mono font-bold text-[var(--text-primary)] focus:outline-none focus:border-[var(--primary)]"
              />
            </div>

            {/* Discrepancy Flag */}
            <div
              className={`p-3 rounded-xl border flex items-center justify-between text-xs ${
                cashDifference === 0
                  ? "bg-[var(--success)]/15 border-[var(--success)]/30 text-[var(--success-strong)]"
                  : cashDifference > 0
                  ? "bg-[var(--info)]/15 border-[var(--info)]/30 text-[var(--info-strong)]"
                  : "bg-[var(--error)]/15 border-[var(--error)]/30 text-[var(--error-strong)]"
              }`}
            >
              <span>Cash Discrepancy (Over / Short):</span>
              <strong className="font-mono text-sm">
                {cashDifference === 0
                  ? "Exact Match (₹0.00)"
                  : cashDifference > 0
                  ? `+${formatCurrency(cashDifference)} (Cash Over)`
                  : `${formatCurrency(cashDifference)} (Cash Short)`}
              </strong>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Closing Manager Notes
              </label>
              <textarea
                rows={3}
                disabled={isDayClosed}
                value={dayCloseNotes}
                onChange={(e) => setDayCloseNotes(e.target.value)}
                placeholder="Add any notes regarding cash variance, till handover, or exceptional refunds..."
                className="w-full px-3 py-2 bg-[var(--surface-muted)] border border-[var(--border-soft)] rounded-xl text-xs text-[var(--text-primary)] placeholder-[var(--text-tertiary)] focus:outline-none"
              />
            </div>

            {!isDayClosed && (
              <button
                onClick={() => setIsDayClosed(true)}
                className="w-full py-3 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white font-bold text-xs rounded-xl shadow-lg shadow-blue-500/25 transition-all active:scale-98"
              >
                Submit & Lock Day Close Register
              </button>
            )}
          </div>
        </div>
      )}

      {/* Viewing Receipt Modal */}
      {returningSaleId && (
        <SaleReturnSheet
          saleId={returningSaleId}
          onClose={() => setReturningSaleId(null)}
          // Balances and stock have moved, so the list must be re-read rather
          // than patched locally.
          onDone={() => void fetchSales()}
        />
      )}

      {viewingReceipt && (
        <ThermalReceiptModal
          isOpen={true}
          onClose={() => setViewingReceipt(null)}
          shopName="Business Hub Superstore"
          receiptNumber={viewingReceipt.receipt_number}
          cashierName={viewingReceipt.cashier_name}
          customerName={viewingReceipt.customer_name}
          customerPhone={viewingReceipt.customer_phone}
          items={viewingReceipt.items}
          subtotal={viewingReceipt.subtotal}
          taxAmount={viewingReceipt.tax_amount}
          discountAmount={viewingReceipt.discount_amount}
          totalAmount={viewingReceipt.total_amount}
          payments={viewingReceipt.payment_breakdown}
          createdDate={viewingReceipt.created_at}
        />
      )}
    </div>
  );
}
