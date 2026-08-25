"use client";

import React, { useRef, useState } from "react";
import { Printer, X, CheckCircle2 } from "lucide-react";
import { formatDate, formatQuantity } from "@/lib/utils";
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
  /** Colour or one-ink. A thermal roll prints one colour, so plain is the
   *  default; colour is for the A4/PDF copy a customer is emailed. */
  const [mode, setMode] = useState<"plain" | "colour">("plain");

  if (!isOpen) return null;

  const handlePrint = () => {
    const printArea = document.getElementById("thermal-receipt-print-area");
    if (printArea && receiptRef.current) {
      printArea.innerHTML = receiptRef.current.innerHTML;
      // The stylesheet keys off this: plain forces every colour to black,
      // colour asks the browser not to drop backgrounds. Without it a colour
      // receipt saved as PDF came out as the plain one with the ink missing.
      printArea.setAttribute("data-receipt-mode", mode);
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
            data-receipt-mode={mode}
            // Three sizes, not five: 12px for the shop and the total, 11px for
            // everything read line by line, 9.5px for the metadata nobody
            // reads unless they are checking something. Tabular figures
            // throughout, because a receipt is a column of numbers and
            // proportional digits make them stagger.
            className="tnum w-[76mm] min-h-[120mm] rounded-lg border border-[var(--border-soft)] bg-white p-5 font-mono text-[11px] leading-[1.45] text-black shadow-md"
          >
            {/* Store Header */}
            <div className="text-center pb-3 border-b border-dashed border-neutral-400">
              <div
                className={`text-[12px] font-bold tracking-[0.06em] ${
                  mode === "colour" ? "text-[#0C4A6E]" : ""
                }`}
              >
                {shopName.toUpperCase()}
              </div>
              {shopAddress && (
                <div className="mt-0.5 text-[9.5px] text-neutral-600">{shopAddress}</div>
              )}
              {shopPhone && <div className="text-[9.5px] text-neutral-600">{shopPhone}</div>}
              {/* An unregistered shop has no GSTIN to print, and printing an
                  empty one looks like a fault. */}
              {gstRegistrationType !== "unregistered" && shopGstin && (
                <div className="mt-1 text-[9.5px] font-semibold">GSTIN {shopGstin}</div>
              )}
              {/* What this document is, stated. Rule 46 wants a Tax Invoice
                  titled as one; a composition dealer must issue a Bill of
                  Supply instead, and there was no title on this receipt at
                  all. */}
              <div
                className={`mt-1.5 text-[10px] font-bold tracking-[0.14em] ${
                  mode === "colour" ? "text-[#0369A1]" : ""
                }`}
              >
                {gstRegistrationType === "composition"
                  ? "BILL OF SUPPLY"
                  : gstRegistrationType === "unregistered"
                    ? "CASH MEMO"
                    : "TAX INVOICE"}
              </div>
            </div>

            {/* Receipt Metadata */}
            <div className="space-y-0.5 border-b border-dashed border-neutral-400 py-2 text-[9.5px]">
              <div className="flex justify-between">
                <span>Bill #{receiptNumber}</span>
                <span>{formatDate(createdDate, true)}</span>
              </div>
              {/* "Type: Retail POS" told the customer nothing they could
                  use and cost a line on a 76mm roll. */}
              <div className="flex justify-between">
                <span>Cashier</span>
                <span className="font-semibold">{cashierName}</span>
              </div>
              {customerName && (
                <div className="flex justify-between">
                  <span>{customerName}</span>
                  {customerPhone && <span className="font-semibold">{customerPhone}</span>}
                </div>
              )}
              {/* Mandatory on a B2B invoice — it is the whole reason the buyer
                  wants the bill, since without it they cannot claim the input
                  credit. It was collected at checkout and never printed. */}
              {buyerGstin && (
                <div className="flex justify-between">
                  <span>Buyer GSTIN</span>
                  <span className="font-semibold">{buyerGstin}</span>
                </div>
              )}
            </div>

            {/* Items Table */}
            <div className="py-2 border-b border-dashed border-neutral-400">
              {/* A real grid, not four flex children on fractional widths.
                  w-1/6 measures the BOX, so the digits inside it landed
                  wherever the text happened to end and the rupee column
                  staggered down the page. Fixed tracks with the amounts
                  right-aligned in their own put every figure on one edge. */}
              <div className="grid grid-cols-[1fr_2.6rem_3.6rem] gap-x-1.5 border-b border-neutral-300 pb-1 text-[9.5px] font-bold tracking-[0.08em]">
                <span>ITEM</span>
                <span className="text-right">QTY</span>
                <span className="text-right">AMOUNT</span>
              </div>
              <div className="space-y-1.5 pt-1.5">
                {items.map((item) => (
                  <div
                    key={item.id}
                    className="grid grid-cols-[1fr_2.6rem_3.6rem] gap-x-1.5"
                  >
                    <span className="col-span-3 font-semibold leading-snug">
                      {item.name}
                    </span>
                    {/* The rate belongs under the name, not in a column of
                        its own: on 76mm a fourth column squeezed every
                        number and the name still wrapped. */}
                    <span className="text-[8.5px] text-neutral-500">
                      {formatQuantity(item.quantity)} &times; {item.unit_price.toFixed(2)}
                      {item.tax_rate ? ` · GST ${item.tax_rate}%` : ""}
                    </span>
                    <span className="text-right text-[9.5px] text-neutral-500">
                      {formatQuantity(item.quantity)}
                    </span>
                    <span className="text-right font-semibold">
                      {item.total_price.toFixed(2)}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            {/* Totals & Tax Breakup */}
            <div className="py-2 border-b border-dashed border-neutral-400 space-y-1 text-[9.5px]">
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
              <div
                className={`mt-1 flex items-baseline justify-between border-t border-neutral-400 pt-1.5 text-[12px] font-bold ${
                  mode === "colour" ? "text-[#0C4A6E]" : ""
                }`}
              >
                <span className="tracking-[0.06em]">TOTAL</span>
                <span>&#8377;{totalAmount.toFixed(2)}</span>
              </div>
            </div>

            {/* Tender & Payment Mode Breakup */}
            <div className="py-2 border-b border-dashed border-neutral-400 space-y-0.5 text-[9.5px]">
              <div className="font-bold text-[9px] uppercase tracking-wider text-neutral-500 mb-0.5">
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
            <div className="space-y-1 pt-3 text-center text-[9.5px]">
              {/* Rule 5(1)(f) requires this wording on every Bill of Supply a
                  composition dealer issues. Not advisory — its absence is a
                  defect in the document. */}
              {gstRegistrationType === "composition" && (
                <div className="font-bold text-[9px] uppercase border border-neutral-500 rounded px-1 py-1 mb-1">
                  Composition taxable person, not eligible to collect tax on
                  supplies
                </div>
              )}
              {/* What is left is what the customer or a tax officer would
                  actually want. Gone: the asterisk banner, an exchange policy
                  hardcoded to seven days that no shop had ever set, and a
                  line advertising the software on the shopkeeper's paper. */}
              <div className="font-semibold">Thank you</div>
            </div>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex flex-wrap items-center gap-3 bg-[var(--bg-base)] p-5">
          {/* One switch, not two buttons that print. A thermal roll has one
              ink, so plain is the default; colour is for the A4 or PDF copy a
              customer gets by email. Both go through the same print dialog,
              which is also where "Save as PDF" lives. */}
          <div className="flex shrink-0 items-center gap-1 rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] p-1">
            {[
              { key: "plain" as const, label: "Plain" },
              { key: "colour" as const, label: "Colour" },
            ].map((option) => (
              <button
                key={option.key}
                type="button"
                onClick={() => setMode(option.key)}
                aria-pressed={mode === option.key}
                className={`focus-ring cursor-pointer rounded-[7px] px-3 py-1.5 text-[11.5px] font-bold transition-colors ${
                  mode === option.key
                    ? "bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                    : "text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
                }`}
              >
                {option.label}
              </button>
            ))}
          </div>

          <button
            onClick={handlePrint}
            className="focus-ring flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-[12px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-5 py-3 text-xs font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20"
          >
            <Printer className="h-4 w-4" />
            <span>Print or save PDF</span>
          </button>
          <button
            onClick={onClose}
            className="focus-ring cursor-pointer rounded-[12px] border border-[var(--border-soft)] bg-[var(--surface)] px-5 py-3 text-xs font-bold text-[var(--text-secondary)] transition-colors hover:bg-[var(--bg-soft)] hover:text-[var(--text-primary)]"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
}
