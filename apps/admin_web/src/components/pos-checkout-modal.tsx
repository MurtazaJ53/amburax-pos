"use client";

import React, { useState, useEffect, useMemo } from "react";
import {
  X,
  CreditCard,
  Banknote,
  QrCode,
  Users,
  CheckCircle,
  Copy,
  ArrowRight,
} from "lucide-react";
import { formatCurrency } from "@/lib/utils";
import type { SplitPaymentTender, Customer } from "@/lib/types";
import { useT } from "@/lib/i18n";
import { isValidGstin } from "@/lib/gst-states";

type PosCheckoutModalProps = {
  isOpen: boolean;
  onClose: () => void;
  totalAmount: number;
  selectedCustomer: Customer | null;
  shopUpiVpa?: string;
  shopName?: string;
  /** Whether this shop bills other businesses and needs the buyer's GSTIN on
   *  every invoice. Driven by the gstin_on_every_bill flag, which wholesale
   *  turns on by default. */
  requireBuyerGstin?: boolean;
  onCompleteSale: (
    payments: SplitPaymentTender,
    changeDue: number,
    buyerGstin?: string,
  ) => void;
};

export function PosCheckoutModal({
  isOpen,
  onClose,
  totalAmount,
  selectedCustomer,
  shopUpiVpa = "merchant@upi",
  shopName = "Business Hub Store",
  requireBuyerGstin = false,
  onCompleteSale,
}: PosCheckoutModalProps) {
  const t = useT();
  const [cashAmount, setCashAmount] = useState<string>("");
  const [cashReceived, setCashReceived] = useState<string>("");
  const [cardAmount, setCardAmount] = useState<string>("");
  const [cardRef, setCardRef] = useState<string>("");
  const [upiAmount, setUpiAmount] = useState<string>("");
  const [upiRef, setUpiRef] = useState<string>("");
  const [khataAmount, setKhataAmount] = useState<string>("");
  const [activeTab, setActiveTab] = useState<"cash" | "card" | "upi" | "khata">("cash");
  const [copiedUpi, setCopiedUpi] = useState(false);
  const [buyerGstin, setBuyerGstin] = useState("");

  // Only blocks the sale when the shop asked for it. A retail counter must
  // never be stopped by a field its customers do not have.
  const gstinTouched = buyerGstin.trim().length > 0;
  const gstinLooksWrong = gstinTouched && !isValidGstin(buyerGstin);
  const gstinBlocksSale = requireBuyerGstin && !isValidGstin(buyerGstin);

  useEffect(() => {
    if (isOpen) {
      setCashAmount(totalAmount.toString());
      setCashReceived(totalAmount.toString());
      setCardAmount("");
      setCardRef("");
      setUpiAmount("");
      setUpiRef("");
      setKhataAmount("");
      setActiveTab("cash");
      setCopiedUpi(false);
    }
  }, [isOpen, totalAmount]);

  const numCash = parseFloat(cashAmount) || 0;
  const numCashReceived = parseFloat(cashReceived) || numCash;
  const numCard = parseFloat(cardAmount) || 0;
  const numUpi = parseFloat(upiAmount) || 0;
  const numKhata = parseFloat(khataAmount) || 0;

  const totalAllocated = useMemo(() => {
    return numCash + numCard + numUpi + numKhata;
  }, [numCash, numCard, numUpi, numKhata]);

  const remaining = useMemo(() => {
    return Math.max(0, totalAmount - totalAllocated);
  }, [totalAmount, totalAllocated]);

  const changeDue = useMemo(() => {
    if (numCash > 0 && numCashReceived > numCash) {
      return numCashReceived - numCash;
    }
    return 0;
  }, [numCash, numCashReceived]);

  const isValid = Math.abs(totalAllocated - totalAmount) < 0.01;

  const upiIntentUri = useMemo(() => {
    const amt = numUpi > 0 ? numUpi.toFixed(2) : totalAmount.toFixed(2);
    const encShop = encodeURIComponent(shopName);
    return `upi://pay?pa=${shopUpiVpa}&pn=${encShop}&am=${amt}&cu=INR&tn=Invoice+Payment`;
  }, [shopUpiVpa, shopName, numUpi, totalAmount]);

  const handleCopyUpi = () => {
    navigator.clipboard.writeText(upiIntentUri);
    setCopiedUpi(true);
    setTimeout(() => setCopiedUpi(false), 2000);
  };

  const handleExactPayment = (mode: "cash" | "card" | "upi" | "khata") => {
    setCashAmount("");
    setCardAmount("");
    setUpiAmount("");
    setKhataAmount("");

    if (mode === "cash") {
      setCashAmount(totalAmount.toString());
      setCashReceived(totalAmount.toString());
    } else if (mode === "card") {
      setCardAmount(totalAmount.toString());
    } else if (mode === "upi") {
      setUpiAmount(totalAmount.toString());
    } else if (mode === "khata") {
      setKhataAmount(totalAmount.toString());
    }
    setActiveTab(mode);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!isValid) return;
    if (gstinBlocksSale) return;

    onCompleteSale(
      {
        cash: numCash,
        card: numCard,
        upi: numUpi,
        khata_due: numKhata,
        card_ref: cardRef.trim() || undefined,
        upi_ref: upiRef.trim() || undefined,
      },
      changeDue,
      buyerGstin.trim().toUpperCase() || undefined
    );
  };

  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-[var(--text-primary)]/60 backdrop-blur-sm animate-in fade-in duration-150"
      onClick={onClose}
    >
      <div
        className="w-full max-w-2xl bg-[var(--surface)] border border-[var(--border-soft)] rounded-[28px] shadow-2xl overflow-hidden flex flex-col max-h-[90vh]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="p-5 border-b border-[var(--bg-soft)] flex items-center justify-between bg-[var(--bg-base)]">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-[var(--primary)]/10 text-[var(--primary-hover)] flex items-center justify-center">
              <CreditCard className="w-5 h-5" />
            </div>
            <div>
              <span className="font-[900] text-base text-[var(--text-primary)]">
                {t("webCheckoutPayment")}
              </span>
              <div className="text-xs font-bold text-[var(--text-secondary)]">
                Total Payable: <strong className="text-[var(--primary-hover)]">{formatCurrency(totalAmount)}</strong>
              </div>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-xl text-[var(--text-tertiary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-app)]"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Modal Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-6">
          {/* Quick 1-Click Fill Buttons */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
            <button
              type="button"
              onClick={() => handleExactPayment("cash")}
              className={`p-3.5 rounded-2xl border flex flex-col items-center gap-1.5 transition-all ${
                activeTab === "cash" && numCash === totalAmount
                  ? "border-[var(--primary)] bg-[var(--primary)]/10 text-[var(--primary-hover)] shadow-sm font-extrabold"
                  : "border-[var(--border-soft)] bg-[var(--bg-base)] text-[var(--text-secondary)] hover:border-[var(--border)]"
              }`}
            >
              <Banknote className="w-5 h-5 text-[var(--success-strong)]" />
              <span className="text-xs font-bold">100% Cash</span>
            </button>

            <button
              type="button"
              onClick={() => handleExactPayment("upi")}
              className={`p-3.5 rounded-2xl border flex flex-col items-center gap-1.5 transition-all ${
                activeTab === "upi" && numUpi === totalAmount
                  ? "border-[var(--primary)] bg-[var(--primary)]/10 text-[var(--primary-hover)] shadow-sm font-extrabold"
                  : "border-[var(--border-soft)] bg-[var(--bg-base)] text-[var(--text-secondary)] hover:border-[var(--border)]"
              }`}
            >
              <QrCode className="w-5 h-5 text-[var(--primary-hover)]" />
              <span className="text-xs font-bold">100% UPI QR</span>
            </button>

            <button
              type="button"
              onClick={() => handleExactPayment("card")}
              className={`p-3.5 rounded-2xl border flex flex-col items-center gap-1.5 transition-all ${
                activeTab === "card" && numCard === totalAmount
                  ? "border-[var(--primary)] bg-[var(--primary)]/10 text-[var(--primary-hover)] shadow-sm font-extrabold"
                  : "border-[var(--border-soft)] bg-[var(--bg-base)] text-[var(--text-secondary)] hover:border-[var(--border)]"
              }`}
            >
              <CreditCard className="w-5 h-5 text-purple-600" />
              <span className="text-xs font-bold">100% Card</span>
            </button>

            <button
              type="button"
              disabled={!selectedCustomer}
              onClick={() => handleExactPayment("khata")}
              className={`p-3.5 rounded-2xl border flex flex-col items-center gap-1.5 transition-all ${
                !selectedCustomer
                  ? "opacity-40 cursor-not-allowed border-[var(--border-soft)] bg-[var(--bg-base)] text-[var(--text-tertiary)]"
                  : activeTab === "khata" && numKhata === totalAmount
                  ? "border-[var(--primary)] bg-[var(--primary)]/10 text-[var(--primary-hover)] shadow-sm font-extrabold"
                  : "border-[var(--border-soft)] bg-[var(--bg-base)] text-[var(--text-secondary)] hover:border-[var(--border)]"
              }`}
            >
              <Users className="w-5 h-5 text-[var(--warning-strong)]" />
              <span className="text-xs font-bold">100% Khata Due</span>
            </button>
          </div>

          {/* Payment Method Split Rows */}
          <div className="space-y-3.5 bg-[var(--bg-base)] p-5 rounded-2xl border border-[var(--border-soft)]">
            <h4 className="text-[11px] font-extrabold text-[var(--text-tertiary)] uppercase tracking-wider">
              Split Tender Allocation
            </h4>

            {/* Cash Input */}
            <div className="flex flex-col sm:flex-row sm:items-center gap-2 pt-1">
              <div className="w-32 flex items-center gap-2 text-xs font-bold text-[var(--text-primary)]">
                <Banknote className="w-4 h-4 text-[var(--success-strong)]" />
                <span>Cash:</span>
              </div>
              <div className="flex-1 flex gap-2">
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={cashAmount}
                  onChange={(e) => {
                    setCashAmount(e.target.value);
                    if (!cashReceived || parseFloat(cashReceived) < parseFloat(e.target.value)) {
                      setCashReceived(e.target.value);
                    }
                  }}
                  placeholder="₹0.00"
                  className="flex-1 px-3.5 py-2.5 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl text-xs font-bold text-[var(--text-primary)] focus:outline-none focus:border-[var(--primary)]"
                />
                {numCash > 0 && (
                  <input
                    type="number"
                    step="0.01"
                    min={numCash}
                    value={cashReceived}
                    onChange={(e) => setCashReceived(e.target.value)}
                    placeholder="Tendered"
                    title="Physical cash received from customer"
                    className="w-32 px-3.5 py-2.5 bg-[var(--surface)] border border-[var(--success)]/30 rounded-xl text-xs font-bold text-[var(--success-strong)] focus:outline-none"
                  />
                )}
              </div>
            </div>

            {/* Change Due Indicator */}
            {changeDue > 0 && (
              <div className="sm:ml-34 p-3 rounded-xl bg-[var(--success)]/10 border border-[var(--success)]/30 text-xs font-bold text-[var(--success-strong)] flex justify-between items-center">
                <span>Return Change to Customer:</span>
                <strong className="text-base font-black">{formatCurrency(changeDue)}</strong>
              </div>
            )}

            {/* Card Input */}
            <div className="flex flex-col sm:flex-row sm:items-center gap-2">
              <div className="w-32 flex items-center gap-2 text-xs font-bold text-[var(--text-primary)]">
                <CreditCard className="w-4 h-4 text-purple-600" />
                <span>Card:</span>
              </div>
              <div className="flex-1 flex gap-2">
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={cardAmount}
                  onChange={(e) => setCardAmount(e.target.value)}
                  placeholder="₹0.00"
                  className="flex-1 px-3.5 py-2.5 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl text-xs font-bold text-[var(--text-primary)] focus:outline-none focus:border-[var(--primary)]"
                />
                <input
                  type="text"
                  value={cardRef}
                  onChange={(e) => setCardRef(e.target.value)}
                  placeholder="Auth/Ref # (optional)"
                  className="w-36 px-3.5 py-2.5 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl text-xs font-medium text-[var(--text-primary)] focus:outline-none"
                />
              </div>
            </div>

            {/* UPI QR Input & QR Code Box */}
            <div className="flex flex-col sm:flex-row sm:items-start gap-2">
              <div className="w-32 flex items-center gap-2 text-xs font-bold text-[var(--text-primary)] pt-2.5">
                <QrCode className="w-4 h-4 text-[var(--primary-hover)]" />
                <span>UPI / QR:</span>
              </div>
              <div className="flex-1 space-y-2">
                <div className="flex gap-2">
                  <input
                    type="number"
                    step="0.01"
                    min="0"
                    value={upiAmount}
                    onChange={(e) => setUpiAmount(e.target.value)}
                    placeholder="₹0.00"
                    className="flex-1 px-3.5 py-2.5 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl text-xs font-bold text-[var(--text-primary)] focus:outline-none focus:border-[var(--primary)]"
                  />
                  <input
                    type="text"
                    value={upiRef}
                    onChange={(e) => setUpiRef(e.target.value)}
                    placeholder="UTR/Txn # (optional)"
                    className="w-36 px-3.5 py-2.5 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl text-xs font-medium text-[var(--text-primary)] focus:outline-none"
                  />
                </div>

                {numUpi > 0 && (
                  <div className="p-4 bg-[var(--surface)] border border-[#BAE6FD] rounded-2xl flex items-center gap-4 shadow-sm">
                    <div className="w-20 h-20 bg-[var(--text-primary)] p-2 rounded-xl flex flex-col items-center justify-center text-white text-[8px] text-center font-mono">
                      <QrCode className="w-8 h-8 text-[var(--primary-light)] mb-0.5" />
                      <span>UPI SCAN</span>
                    </div>
                    <div className="flex-1 text-xs space-y-1">
                      <div className="font-extrabold text-[var(--text-primary)]">
                        Scan to Pay {formatCurrency(numUpi)}
                      </div>
                      <div className="text-[11px] text-[var(--text-secondary)] font-mono truncate">
                        VPA: {shopUpiVpa}
                      </div>
                      <button
                        type="button"
                        onClick={handleCopyUpi}
                        className="inline-flex items-center gap-1 text-[11px] font-bold text-[var(--primary-hover)] hover:underline"
                      >
                        {copiedUpi ? (
                          <CheckCircle className="w-3.5 h-3.5 text-[var(--success-strong)]" />
                        ) : (
                          <Copy className="w-3.5 h-3.5" />
                        )}
                        <span>{copiedUpi ? "Copied UPI link" : "Copy Payment Link"}</span>
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* Khata Credit Due Input */}
            <div className="flex flex-col sm:flex-row sm:items-center gap-2">
              <div className="w-32 flex items-center gap-2 text-xs font-bold text-[var(--text-primary)]">
                <Users className="w-4 h-4 text-[var(--warning-strong)]" />
                <span>Khata Due:</span>
              </div>
              <div className="flex-1">
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  disabled={!selectedCustomer}
                  value={khataAmount}
                  onChange={(e) => setKhataAmount(e.target.value)}
                  placeholder={
                    selectedCustomer ? "₹0.00" : "Select a customer to allow Khata credit"
                  }
                  className="w-full px-3.5 py-2.5 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl text-xs font-bold text-[var(--text-primary)] focus:outline-none focus:border-[var(--primary)] disabled:opacity-50 disabled:cursor-not-allowed"
                />
                {selectedCustomer && (
                  <div className="text-[10px] font-bold text-[var(--text-secondary)] mt-1">
                    Customer Khata: <strong>{selectedCustomer.name}</strong> (Current Due:{" "}
                    {formatCurrency(selectedCustomer.balance_amount ?? 0)})
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Allocation Validation & Remaining Counter */}
          <div className="p-4 rounded-2xl border border-[var(--border-soft)] bg-[var(--bg-base)] flex items-center justify-between">
            <div>
              <div className="text-[11px] font-bold text-[var(--text-secondary)]">Total Allocated:</div>
              <div className="text-sm font-extrabold text-[var(--text-primary)]">
                {formatCurrency(totalAllocated)} / {formatCurrency(totalAmount)}
              </div>
            </div>
            {remaining > 0 ? (
              <div className="text-right">
                <div className="text-xs text-[var(--warning-strong)] font-bold">Remaining to allocate:</div>
                <div className="text-sm font-black text-[var(--warning-strong)]">
                  {formatCurrency(remaining)}
                </div>
              </div>
            ) : totalAllocated > totalAmount ? (
              <div className="text-right text-xs text-[var(--error-strong)] font-bold">
                Exceeds total by {formatCurrency(totalAllocated - totalAmount)}
              </div>
            ) : (
              <div className="flex items-center gap-1.5 text-xs text-[var(--success-strong)] font-extrabold">
                <CheckCircle className="w-4 h-4" />
                <span>Ready to Charge</span>
              </div>
            )}
          </div>
        </form>

        {/* Actions Footer */}
        {requireBuyerGstin && (
          <div className="px-5 pt-4 border-t border-[var(--bg-soft)]">
            <label
              htmlFor="buyer-gstin"
              className="block text-[11px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mb-1.5"
            >
              Buyer&apos;s GSTIN
            </label>
            <input
              id="buyer-gstin"
              type="text"
              value={buyerGstin}
              maxLength={15}
              autoComplete="off"
              spellCheck={false}
              onChange={(e) => setBuyerGstin(e.target.value.toUpperCase())}
              placeholder="27AABCU9603R1ZM"
              aria-invalid={gstinLooksWrong}
              aria-describedby="buyer-gstin-help"
              className={`w-full px-3.5 py-3 bg-[var(--surface)] border rounded-2xl text-xs font-bold tracking-wide text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none transition-colors ${
                gstinLooksWrong
                  ? "border-[var(--error-strong)]"
                  : "border-[var(--border-soft)] focus:border-[var(--primary)]"
              }`}
            />
            <p
              id="buyer-gstin-help"
              className={`mt-1.5 text-[11px] font-semibold ${
                gstinLooksWrong ? "text-[var(--error-strong)]" : "text-[var(--text-tertiary)]"
              }`}
            >
              {gstinLooksWrong
                ? "That is not a valid 15-character GSTIN."
                : "Your buyer needs this on the invoice to claim input credit."}
            </p>
          </div>
        )}

        <div className="p-5 border-t border-[var(--bg-soft)] bg-[var(--bg-base)] flex items-center justify-between gap-3">
          <button
            type="button"
            onClick={onClose}
            className="py-3 px-5 bg-[var(--surface)] hover:bg-[var(--bg-soft)] border border-[var(--border-soft)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] rounded-2xl font-bold text-xs transition-colors"
          >
            Cancel
          </button>

          <button
            type="button"
            disabled={!isValid || gstinBlocksSale}
            onClick={handleSubmit}
            className="flex-1 flex items-center justify-center gap-2 py-3 px-5 bg-gradient-to-r from-[var(--primary-light)] to-[var(--primary-hover)] hover:from-[var(--primary)] hover:to-[var(--primary-dark)] disabled:opacity-40 text-white rounded-2xl font-extrabold text-xs shadow-[0_8px_20px_rgba(14,165,233,0.35)] transition-all cursor-pointer"
          >
            <span>CONFIRM & PRINT RECEIPT</span>
            <ArrowRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
