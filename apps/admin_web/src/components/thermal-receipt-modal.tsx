"use client";

import React, { useRef } from "react";
import { Printer, X, CheckCircle2 } from "lucide-react";
import { formatDate } from "@/lib/utils";
import type { CartItem, SplitPaymentTender } from "@/lib/types";

type ThermalReceiptModalProps = {
  isOpen: boolean;
  onClose: () => void;
  shopName: string;
  shopAddress?: string;
  shopGstin?: string;
  shopPhone?: string;
  receiptNumber: string;
  cashierName: string;
  customerName?: string;
  customerPhone?: string;
  items: CartItem[];
  subtotal: number;
  taxAmount: number;
  /** Whether this supply is within the shop's own state.
   *
   *  Decides CGST+SGST versus IGST on the printed invoice. This was hardcoded
   *  to the intra-state wording, so an inter-state sale printed a legally
   *  wrong tax breakdown while the backend stored the right one. Defaults true
   *  because a walk-in sale is intra-state. */
  intraState?: boolean;
  /** The buyer's GSTIN, required on the invoice for a B2B supply. */
  buyerGstin?: string;
  /** regular | composition | unregistered.
   *
   *  Decides what this document IS. A composition dealer must issue a Bill of
   *  Supply, never a Tax Invoice, and must carry the declaration required by
   *  Rule 5(1)(f). Printing a Tax Invoice with GST on it is not a cosmetic
   *  error for them — collecting tax is something s.10 forbids. */
  gstRegistrationType?: string;
  discountAmount: number;
  totalAmount: number;
  payments: SplitPaymentTender;
  changeDue?: number;
  createdDate?: string;
};

export function ThermalReceiptModal({
  isOpen,
  onClose,
  shopName,
  shopAddress = "123 Commercial High Street, Market Complex",
  shopGstin = "27AABCU9603R1ZM",
  shopPhone = "+91 98765 43210",
  receiptNumber,
  cashierName,
  customerName = "Walk-in Guest",
  customerPhone,
  items,
  subtotal,
  taxAmount,
  intraState = true,
  buyerGstin,
  gstRegistrationType = "regular",
  discountAmount,
  totalAmount,
  payments,
  changeDue = 0,
  createdDate = new Date().toISOString(),
}: ThermalReceiptModalProps) {
  const receiptRef = useRef<HTMLDivElement>(null);

  if (!isOpen) return null;

  const handlePrint = () => {
    const printArea = document.getElementById("thermal-receipt-print-area");
    if (printArea && receiptRef.current) {
      printArea.innerHTML = receiptRef.current.innerHTML;
      window.print();
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-[var(--text-primary)]/60 backdrop-blur-sm animate-in fade-in duration-150"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md bg-[var(--surface)] border border-[var(--border-soft)] rounded-[28px] shadow-2xl overflow-hidden flex flex-col max-h-[90vh]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="p-5 border-b border-[var(--bg-soft)] flex items-center justify-between bg-[var(--bg-base)]">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-[var(--success)]/10 text-[var(--success-strong)] flex items-center justify-center">
              <CheckCircle2 className="w-5 h-5" />
            </div>
            <span className="font-[900] text-sm text-[var(--text-primary)]">
              Sale Completed Successfully
            </span>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-xl text-[var(--text-tertiary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-app)]"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Scrollable Receipt Preview (Paper look) */}
        <div className="flex-1 overflow-y-auto p-6 bg-[var(--bg-soft)] flex justify-center border-b border-[var(--bg-soft)]">
          <div
            ref={receiptRef}
            className="w-[76mm] min-h-[120mm] bg-white text-black p-5 font-mono text-[11px] leading-tight shadow-md border border-[var(--border-soft)] rounded-lg"
            style={{ fontFamily: "'Courier New', Courier, monospace" }}
          >
            {/* Store Header */}
            <div className="text-center pb-3 border-b border-dashed border-neutral-400">
              <div className="font-bold text-xs tracking-wide">{shopName.toUpperCase()}</div>
              <div className="text-[10px] text-neutral-600 mt-0.5">{shopAddress}</div>
              <div className="text-[10px] text-neutral-600">Phone: {shopPhone}</div>
              {/* An unregistered shop has no GSTIN to print, and printing an
                  empty one looks like a fault. */}
              {gstRegistrationType !== "unregistered" && shopGstin && (
                <div className="text-[10px] font-semibold mt-1">GSTIN: {shopGstin}</div>
              )}
              {/* What this document is, stated. Rule 46 wants a Tax Invoice
                  titled as one; a composition dealer must issue a Bill of
                  Supply instead, and there was no title on this receipt at
                  all. */}
              <div className="text-[10px] font-bold mt-1 tracking-wider">
                {gstRegistrationType === "composition"
                  ? "BILL OF SUPPLY"
                  : gstRegistrationType === "unregistered"
                    ? "CASH MEMO"
                    : "TAX INVOICE"}
              </div>
            </div>

            {/* Receipt Metadata */}
            <div className="py-2 border-b border-dashed border-neutral-400 text-[9px] space-y-0.5">
              <div className="flex justify-between">
                <span>Receipt: #{receiptNumber}</span>
                <span>{formatDate(createdDate, true)}</span>
              </div>
              <div className="flex justify-between">
                <span>Cashier: {cashierName}</span>
                <span>Type: Retail POS</span>
              </div>
              {customerName && (
                <div className="flex justify-between">
                  <span>Customer: {customerName}</span>
                  {customerPhone && <span>{customerPhone}</span>}
                </div>
              )}
              {/* Mandatory on a B2B invoice — it is the whole reason the buyer
                  wants the bill, since without it they cannot claim the input
                  credit. It was collected at checkout and never printed. */}
              {buyerGstin && (
                <div className="flex justify-between">
                  <span>Buyer GSTIN:</span>
                  <span>{buyerGstin}</span>
                </div>
              )}
            </div>

            {/* Items Table */}
            <div className="py-2 border-b border-dashed border-neutral-400">
              <div className="flex justify-between font-bold pb-1 text-[9px] border-b border-neutral-300">
                <span className="w-1/2">ITEM</span>
                <span className="w-1/6 text-center">QTY</span>
                <span className="w-1/6 text-right">RATE</span>
                <span className="w-1/6 text-right">TOTAL</span>
              </div>
              <div className="space-y-1.5 pt-1.5">
                {items.map((item) => (
                  <div key={item.id}>
                    <div className="font-semibold text-[10px]">{item.name}</div>
                    <div className="flex justify-between text-[9px] text-neutral-600">
                      <span className="w-1/2 text-[8px] text-neutral-500 truncate">
                        SKU: {item.sku || "—"} | GST {item.tax_rate}%
                      </span>
                      <span className="w-1/6 text-center">{item.quantity}</span>
                      <span className="w-1/6 text-right">₹{item.unit_price.toFixed(2)}</span>
                      <span className="w-1/6 text-right font-medium">
                        ₹{item.total_price.toFixed(2)}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Totals & Tax Breakup */}
            <div className="py-2 border-b border-dashed border-neutral-400 space-y-1 text-[9px]">
              {/* Line count, not summed quantity. A grocer selling 0.75 kg
                  would otherwise read "0.75 items", and floats made it worse. */}
              <div className="flex justify-between">
                <span>
                  Subtotal ({items.length} item{items.length === 1 ? "" : "s"}):
                </span>
                <span>₹{subtotal.toFixed(2)}</span>
              </div>
              {discountAmount > 0 && (
                <div className="flex justify-between text-neutral-700">
                  <span>Discount:</span>
                  <span>-₹{discountAmount.toFixed(2)}</span>
                </div>
              )}
              {/* Taxable value + GST = total, the format a GST invoice is
                  expected to take — and, unlike what was here before, one that
                  adds up. It printed "Subtotal 150 / Tax 7.14 / TOTAL 150",
                  because the tax was already inside the price and the receipt
                  never said so. This is the copy the customer keeps and the
                  one produced in a dispute. */}
              {taxAmount > 0 && gstRegistrationType === "regular" && (
                <>
                  <div className="flex justify-between">
                    <span>Taxable value:</span>
                    <span>₹{(totalAmount - taxAmount).toFixed(2)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>{intraState ? "GST (CGST + SGST):" : "IGST:"}</span>
                    <span>₹{taxAmount.toFixed(2)}</span>
                  </div>
                  {/* Shown split, because Rule 46 wants the tax stated by
                      component and by rate, not as one lump. */}
                  {intraState ? (
                    <div className="flex justify-between text-neutral-600">
                      <span className="pl-2">CGST / SGST:</span>
                      <span>
                        ₹{(taxAmount / 2).toFixed(2)} / ₹
                        {(taxAmount - taxAmount / 2).toFixed(2)}
                      </span>
                    </div>
                  ) : null}
                </>
              )}
              <div className="flex justify-between font-bold text-xs pt-1 border-t border-neutral-300">
                <span>TOTAL AMOUNT:</span>
                <span>₹{totalAmount.toFixed(2)}</span>
              </div>
            </div>

            {/* Tender & Payment Mode Breakup */}
            <div className="py-2 border-b border-dashed border-neutral-400 space-y-0.5 text-[9px]">
              <div className="font-bold text-[8px] uppercase tracking-wider text-neutral-500 mb-0.5">
                Payment Breakdown:
              </div>
              {payments.cash > 0 && (
                <div className="flex justify-between">
                  <span>Cash Paid:</span>
                  <span>₹{payments.cash.toFixed(2)}</span>
                </div>
              )}
              {payments.card > 0 && (
                <div className="flex justify-between">
                  <span>Card {payments.card_ref ? `(${payments.card_ref})` : ""}:</span>
                  <span>₹{payments.card.toFixed(2)}</span>
                </div>
              )}
              {payments.upi > 0 && (
                <div className="flex justify-between">
                  <span>UPI / QR {payments.upi_ref ? `(${payments.upi_ref})` : ""}:</span>
                  <span>₹{payments.upi.toFixed(2)}</span>
                </div>
              )}
              {payments.khata_due > 0 && (
                <div className="flex justify-between font-semibold">
                  <span>Credit / Khata Balance Due:</span>
                  <span>₹{payments.khata_due.toFixed(2)}</span>
                </div>
              )}
              {changeDue > 0 && (
                <div className="flex justify-between font-semibold text-[var(--success-strong)] pt-0.5">
                  <span>Change Returned:</span>
                  <span>₹{changeDue.toFixed(2)}</span>
                </div>
              )}
            </div>

            {/* Footer */}
            <div className="pt-3 text-center text-[9px] space-y-1">
              {/* Rule 5(1)(f) requires this wording on every Bill of Supply a
                  composition dealer issues. Not advisory — its absence is a
                  defect in the document. */}
              {gstRegistrationType === "composition" && (
                <div className="font-bold text-[8px] uppercase border border-neutral-400 rounded px-1 py-1 mb-1">
                  Composition taxable person, not eligible to collect tax on
                  supplies
                </div>
              )}
              <div className="font-semibold">*** THANK YOU FOR YOUR VISIT! ***</div>
              <div className="text-[8px] text-neutral-500">
                Items once sold can be exchanged within 7 days with original invoice.
              </div>
              <div className="pt-1 text-[8px] text-neutral-400">
                Powered by Business Hub Cloud POS
              </div>
            </div>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="p-5 bg-[var(--bg-base)] flex items-center gap-3">
          <button
            onClick={handlePrint}
            className="flex-1 flex items-center justify-center gap-2 py-3 px-5 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 rounded-2xl font-extrabold text-xs shadow-[0_8px_20px_rgba(14,165,233,0.35)] transition-all cursor-pointer"
          >
            <Printer className="w-4 h-4" />
            <span>Print Receipt</span>
          </button>
          <button
            onClick={onClose}
            className="py-3 px-5 bg-[var(--surface)] hover:bg-[var(--bg-soft)] border border-[var(--border-soft)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] rounded-2xl font-bold text-xs transition-colors"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
}
