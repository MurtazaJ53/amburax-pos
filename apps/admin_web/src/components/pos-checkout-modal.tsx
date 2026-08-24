"use client";

import React, { useState, useEffect, useMemo } from "react";
import {
  X,
  Banknote,
  QrCode,
  Users,
  Split,
  CheckCircle,
  Copy,
  ArrowRight,
} from "lucide-react";
import { formatCurrency } from "@/lib/utils";
import type { SplitPaymentTender, Customer } from "@/lib/types";
import { isValidGstin } from "@/lib/gst-states";
import {
  canIdentifyCustomer,
  customerRequired,
  findExistingCustomer,
} from "@/lib/customer-match";

type PosCheckoutModalProps = {
  isOpen: boolean;
  onClose: () => void;
  totalAmount: number;
  selectedCustomer?: Customer | null;
  shopUpiVpa?: string;
  shopName?: string;
  requireBuyerGstin?: boolean;
  /** Opens the cart's customer field. Khata cannot be offered without a
   *  customer, so the modal needs a way to send the cashier to fix that
   *  rather than just refusing. */
  onAttachCustomer?: () => void;
  /** Everyone already on the books, so a number typed here attaches the
   *  existing account instead of opening a second one. */
  customers?: Customer[];
  /** Opens an account and attaches it. Resolves to the customer actually
   *  used, which may be an existing one. */
  onEnsureCustomer?: (name: string, phone: string) => Promise<Customer | null>;
  onCompleteSale: (
    payments: SplitPaymentTender,
    changeDue: number,
    buyerGstin?: string,
    /** The customer this bill belongs to. Passed explicitly because a
     *  setState in the parent has not landed by the time this fires. */
    customer?: Customer | null,
  ) => void;
};

/** How the bill is being settled.
 *
 *  Four ways of paying used to be four "100%" buttons in a row ABOVE a split
 *  panel that was always visible — so every sale showed every field whether
 *  or not it applied, and the buttons competed with the panel below them for
 *  the same decision. One choice, made once, down the side.
 */
type Mode = "cash" | "online" | "split" | "due";

const MODES: {
  key: Mode;
  label: string;
  hint: string;
  icon: typeof Banknote;
  tone: string;
}[] = [
  { key: "cash", label: "Cash", hint: "Notes and coins", icon: Banknote, tone: "var(--success)" },
  { key: "online", label: "Online", hint: "UPI or card", icon: QrCode, tone: "var(--primary)" },
  {
    key: "split",
    label: "Split",
    hint: "More than one way",
    icon: Split,
    tone: "var(--violet-strong)",
  },
  { key: "due", label: "Khata", hint: "Owed by a customer", icon: Users, tone: "var(--warning)" },
];

export function PosCheckoutModal({
  isOpen,
  onClose,
  totalAmount,
  selectedCustomer,
  shopUpiVpa = "merchant@upi",
  shopName = "Business Hub Store",
  requireBuyerGstin = false,
  onAttachCustomer,
  customers = [],
  onEnsureCustomer,
  onCompleteSale,
}: PosCheckoutModalProps) {
  const [mode, setMode] = useState<Mode>("cash");
  const [cashAmount, setCashAmount] = useState<string>("");
  const [cashReceived, setCashReceived] = useState<string>("");
  const [cardAmount, setCardAmount] = useState<string>("");
  const [cardRef, setCardRef] = useState<string>("");
  const [upiAmount, setUpiAmount] = useState<string>("");
  const [upiRef, setUpiRef] = useState<string>("");
  const [khataAmount, setKhataAmount] = useState<string>("");
  const [copiedUpi, setCopiedUpi] = useState(false);
  const [buyerGstin, setBuyerGstin] = useState("");
  const [typedName, setTypedName] = useState("");
  const [typedPhone, setTypedPhone] = useState("");
  const [savingCustomer, setSavingCustomer] = useState(false);
  const [customerError, setCustomerError] = useState("");

  // Only blocks the sale when the shop asked for it. A retail counter must
  // never be stopped by a field its customers do not have.
  const gstinTouched = buyerGstin.trim().length > 0;
  const gstinLooksWrong = gstinTouched && !isValidGstin(buyerGstin);
  const gstinBlocksSale = requireBuyerGstin && !isValidGstin(buyerGstin);

  const numCash = parseFloat(cashAmount) || 0;
  const numCashReceived = parseFloat(cashReceived) || numCash;
  const numCard = parseFloat(cardAmount) || 0;
  const numUpi = parseFloat(upiAmount) || 0;
  const numKhata = parseFloat(khataAmount) || 0;

  const totalAllocated = numCash + numCard + numUpi + numKhata;
  const remaining = Math.max(0, totalAmount - totalAllocated);
  const changeDue = numCash > 0 && numCashReceived > numCash ? numCashReceived - numCash : 0;
  const isValid = Math.abs(totalAllocated - totalAmount) < 0.01;

  /** Credit needs somebody to collect from. Cash, card and UPI do not, so a
   *  walk-in is never interrogated for a name to hand over a hundred rupees. */
  const needsCustomer = customerRequired(numKhata);
  const matchedCustomer = useMemo(
    () => findExistingCustomer(customers, typedName, typedPhone),
    [customers, typedName, typedPhone],
  );
  const haveCustomer =
    Boolean(selectedCustomer) || Boolean(matchedCustomer) || canIdentifyCustomer(typedName, typedPhone);
  const customerBlocksSale = needsCustomer && !haveCustomer;

  /** Regulars matching what is being typed. Capped, because a till does not
   *  need a directory — it needs the few people this might be. "I will pay
   *  later" is said at this screen, not before it, so the owner has to be
   *  able to find a regular from here. */
  const suggestions = useMemo(() => {
    const name = typedName.trim().toLowerCase();
    const phone = typedPhone.replace(/\D/g, "");
    if (!name && !phone) return [];
    return customers
      .filter((c) => {
        const matchesName = name && (c.name ?? "").toLowerCase().includes(name);
        const matchesPhone = phone && (c.phone ?? "").replace(/\D/g, "").includes(phone);
        return Boolean(matchesName || matchesPhone);
      })
      .slice(0, 4);
  }, [customers, typedName, typedPhone]);

  /** Puts the whole bill on the chosen way of paying. Split is the exception:
   *  it starts empty because the cashier is about to divide it themselves. */
  const applyMode = (next: Mode) => {
    setMode(next);
    setCashAmount("");
    setCashReceived("");
    setCardAmount("");
    setUpiAmount("");
    setKhataAmount("");

    const whole = totalAmount.toString();
    if (next === "cash") {
      setCashAmount(whole);
      setCashReceived(whole);
    } else if (next === "online") {
      setUpiAmount(whole);
    } else if (next === "due") {
      setKhataAmount(whole);
    }
  };

  useEffect(() => {
    if (isOpen) {
      setMode("cash");
      setCashAmount(totalAmount.toString());
      setCashReceived(totalAmount.toString());
      setCardAmount("");
      setCardRef("");
      setUpiAmount("");
      setUpiRef("");
      setKhataAmount("");
      setCopiedUpi(false);
      setTypedName("");
      setTypedPhone("");
      setCustomerError("");
    }
  }, [isOpen, totalAmount]);

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

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isValid || gstinBlocksSale || customerBlocksSale || savingCustomer) return;

    // Attach whoever this is before the sale is written, so a khata lands on
    // one account. An existing number wins over opening a new one.
    let customerForSale: Customer | null = selectedCustomer ?? null;

    if (!customerForSale && (typedName.trim() || typedPhone.trim()) && onEnsureCustomer) {
      setSavingCustomer(true);
      setCustomerError("");
      try {
        customerForSale = await onEnsureCustomer(typedName.trim(), typedPhone.trim());
        if (!customerForSale && needsCustomer) {
          setCustomerError("Could not save that customer, so the credit has nowhere to go.");
          return;
        }
      } catch {
        if (needsCustomer) {
          setCustomerError("Could not save that customer, so the credit has nowhere to go.");
          return;
        }
      } finally {
        setSavingCustomer(false);
      }
    }

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
      buyerGstin.trim().toUpperCase() || undefined,
      customerForSale,
    );
  };

  if (!isOpen) return null;

  const fieldClass =
    "tnum w-full max-w-[220px] rounded-[9px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 font-mono text-sm font-bold text-[var(--text-primary)] outline-none transition-colors focus:border-[var(--primary)] disabled:opacity-50";
  const refClass =
    "w-full max-w-[260px] rounded-[9px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 text-xs font-semibold text-[var(--text-primary)] outline-none transition-colors placeholder:text-[var(--text-tertiary)] focus:border-[var(--primary)]";
  const labelClass =
    "mb-1.5 block font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]";

  /** Who this is.
   *
   *  Optional on a paid bill — a walk-in should not be asked for a name to
   *  hand over cash — and required the moment any of it goes on khata,
   *  because credit needs someone to collect from. Typing a number already
   *  on the books attaches that account rather than opening a second one.
   */
  const customerBlock = selectedCustomer ? null : (
                <div className="rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-3.5">
                  <div className="mb-2 flex flex-wrap items-center gap-2">
                    <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
                      Customer
                    </span>
                    <span
                      className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${
                        needsCustomer
                          ? "bg-[var(--warning)]/12 text-[var(--warning-strong)]"
                          : "bg-[var(--bg-soft)] text-[var(--text-tertiary)]"
                      }`}
                    >
                      {needsCustomer ? "Required for khata" : "Optional"}
                    </span>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    <input
                      type="text"
                      value={typedName}
                      onChange={(e) => setTypedName(e.target.value)}
                      placeholder="Name"
                      className={refClass}
                    />
                    <input
                      type="tel"
                      inputMode="tel"
                      value={typedPhone}
                      onChange={(e) => setTypedPhone(e.target.value)}
                      placeholder="Phone"
                      className={refClass}
                    />
                  </div>

                  {suggestions.length > 0 && !matchedCustomer && (
                    <ul className="m-0 mt-2 flex list-none flex-col gap-1 p-0">
                      {suggestions.map((c) => (
                        <li key={c.id}>
                          <button
                            type="button"
                            onClick={() => {
                              setTypedName(c.name);
                              setTypedPhone(c.phone ?? "");
                            }}
                            className="focus-ring flex w-full items-center gap-2.5 rounded-[9px] border border-[var(--border-soft)] bg-[var(--surface)] px-2.5 py-1.5 text-left transition-colors hover:border-[var(--primary)]"
                          >
                            <span className="min-w-0 flex-1">
                              <span className="block truncate text-[12px] font-extrabold text-[var(--text-primary)]">
                                {c.name}
                              </span>
                              <span className="block font-mono text-[10px] font-semibold text-[var(--text-tertiary)]">
                                {c.phone || "no phone"}
                              </span>
                            </span>
                            <span className="tnum flex-none font-mono text-[10.5px] font-bold text-[var(--warning-strong)]">
                              Due {formatCurrency(c.balance_amount ?? 0)}
                            </span>
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}

                  {matchedCustomer ? (
                    <p className="m-0 mt-2 text-[11.5px] font-semibold text-[var(--success-dark)]">
                      Already on the books — this bill will go to{" "}
                      <b>{matchedCustomer.name}</b>, not a new account.
                    </p>
                  ) : canIdentifyCustomer(typedName, typedPhone) ? (
                    <p className="m-0 mt-2 text-[11.5px] font-medium text-[var(--text-tertiary)]">
                      A new account will be opened when the sale is confirmed.
                    </p>
                  ) : null}

                  {customerError && (
                    <p className="m-0 mt-2 text-[11.5px] font-bold text-[var(--error-strong)]">
                      {customerError}
                    </p>
                  )}
                </div>
  );

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-[#0F2942]/45 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="checkout-title"
    >
      <div className="flex max-h-[92vh] w-full max-w-4xl flex-col overflow-hidden rounded-[22px] border border-[var(--border-soft)] bg-[var(--surface)] shadow-2xl animate-fade-in-up">
        {/* The amount leads. It is the one number both people at the counter
            are looking at, so it is the largest thing on the dialog. */}
        <header className="flex shrink-0 items-center gap-4 border-b border-[var(--border-soft)] px-6 py-4">
          <div>
            <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
              Amount to collect
            </span>
            <p
              id="checkout-title"
              className="tnum m-0 mt-1 font-mono text-[34px] font-bold leading-none tracking-tight text-[var(--text-primary)]"
            >
              {formatCurrency(totalAmount)}
            </p>
          </div>

          {selectedCustomer && (
            <span className="ml-auto rounded-full bg-[var(--primary)]/10 px-3 py-1.5 text-[11.5px] font-bold text-[var(--primary-hover)]">
              {selectedCustomer.name}
            </span>
          )}

          <button
            type="button"
            onClick={onClose}
            aria-label="Close checkout"
            className={`focus-ring grid h-9 w-9 cursor-pointer place-items-center rounded-[10px] text-[var(--text-tertiary)] transition-colors hover:bg-[var(--bg-soft)] hover:text-[var(--text-primary)] ${
              selectedCustomer ? "" : "ml-auto"
            }`}
          >
            <X className="h-5 w-5" />
          </button>
        </header>

        <form onSubmit={handleSubmit} className="flex min-h-0 flex-1 flex-col">
          <div className="grid min-h-0 flex-1 grid-cols-1 sm:grid-cols-[190px_minmax(0,1fr)]">
            {/* How it is being paid. One decision, made once, down the side. */}
            <nav className="flex shrink-0 gap-2 overflow-x-auto border-b border-[var(--border-soft)] bg-[var(--bg-base)] p-3 sm:flex-col sm:overflow-visible sm:border-b-0 sm:border-r">
              {MODES.map(({ key, label, hint, icon: Icon, tone }) => {
                const blocked = key === "due" && !selectedCustomer;
                const active = mode === key;
                return (
                  <button
                    key={key}
                    type="button"
                    disabled={blocked}
                    onClick={() => applyMode(key)}
                    aria-pressed={active}
                    title={blocked ? "Attach a customer first" : undefined}
                    className={`focus-ring relative flex shrink-0 items-center gap-2.5 rounded-[12px] px-3 py-2.5 text-left transition-colors sm:w-full ${
                      blocked
                        ? "cursor-not-allowed opacity-45"
                        : active
                          ? "bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                          : "cursor-pointer text-[var(--text-secondary)] hover:bg-[var(--surface)]"
                    }`}
                  >
                    {active && (
                      <span className="absolute left-0 top-2 bottom-2 w-[3px] rounded-full bg-[var(--primary)]" />
                    )}
                    <Icon
                      className="h-4 w-4 shrink-0"
                      style={{ color: blocked ? "var(--text-disabled)" : tone }}
                    />
                    <span className="min-w-0">
                      <span className="block text-[13px] font-extrabold">{label}</span>
                      <span className="hidden text-[10.5px] font-semibold text-[var(--text-tertiary)] sm:block">
                        {hint}
                      </span>
                    </span>
                  </button>
                );
              })}
            </nav>

            {/* Only the fields this way of paying actually needs. */}
            <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-5">
              {/* On khata and split the customer is a precondition, not an
                  afterthought — you cannot allocate credit until it is known
                  who owes it, so it is asked first. On a paid bill it stays
                  below, where it belongs as an optional extra. */}
              {(mode === "split" || mode === "due") && customerBlock}

              {mode === "cash" && (
                <>
                  <div>
                    <label className={labelClass} htmlFor="cash-received">
                      Cash received
                    </label>
                    <input
                      id="cash-received"
                      type="number"
                      inputMode="decimal"
                      min="0"
                      step="0.01"
                      value={cashReceived}
                      onChange={(e) => setCashReceived(e.target.value)}
                      className={fieldClass}
                    />
                  </div>

                  {/* The number the customer is standing there waiting for. */}
                  <div
                    className={`flex max-w-[360px] items-center justify-between gap-4 rounded-[12px] border px-4 py-2.5 ${
                      changeDue > 0
                        ? "border-[var(--success)]/40 bg-[var(--success)]/12"
                        : "border-[var(--border-soft)] bg-[var(--bg-base)]"
                    }`}
                  >
                    <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
                      Change to return
                    </span>
                    <span
                      className={`tnum font-mono text-[22px] font-bold leading-none tracking-tight ${
                        changeDue > 0 ? "text-[var(--success-dark)]" : "text-[var(--text-tertiary)]"
                      }`}
                    >
                      {formatCurrency(changeDue)}
                    </span>
                  </div>

                  <p className="m-0 text-[11.5px] font-medium text-[var(--text-tertiary)]">
                    The whole bill is settled in cash. Enter what the customer handed
                    over and the change works itself out.
                  </p>
                </>
              )}

              {mode === "online" && (
                <>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <div>
                      <label className={labelClass} htmlFor="upi-amount">
                        UPI / QR
                      </label>
                      <input
                        id="upi-amount"
                        type="number"
                        inputMode="decimal"
                        min="0"
                        step="0.01"
                        value={upiAmount}
                        onChange={(e) => setUpiAmount(e.target.value)}
                        placeholder="0.00"
                        className={fieldClass}
                      />
                      <input
                        type="text"
                        value={upiRef}
                        onChange={(e) => setUpiRef(e.target.value)}
                        placeholder="UTR / txn number (optional)"
                        className={`${refClass} mt-2`}
                      />
                    </div>

                    <div>
                      <label className={labelClass} htmlFor="card-amount">
                        Card
                      </label>
                      <input
                        id="card-amount"
                        type="number"
                        inputMode="decimal"
                        min="0"
                        step="0.01"
                        value={cardAmount}
                        onChange={(e) => setCardAmount(e.target.value)}
                        placeholder="0.00"
                        className={fieldClass}
                      />
                      <input
                        type="text"
                        value={cardRef}
                        onChange={(e) => setCardRef(e.target.value)}
                        placeholder="Auth / ref number (optional)"
                        className={`${refClass} mt-2`}
                      />
                    </div>
                  </div>

                  <div className="flex flex-wrap items-center gap-3 rounded-[14px] border border-[var(--border-soft)] bg-[var(--bg-base)] px-4 py-3">
                    <QrCode className="h-4 w-4 shrink-0 text-[var(--primary-hover)]" />
                    <span className="flex-1 font-mono text-[11px] font-semibold text-[var(--text-secondary)]">
                      {shopUpiVpa}
                    </span>
                    <button
                      type="button"
                      onClick={handleCopyUpi}
                      className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-1.5 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
                    >
                      <Copy className="h-3.5 w-3.5" />
                      {copiedUpi ? "Copied" : "Copy pay link"}
                    </button>
                  </div>
                </>
              )}

              {mode === "split" && (
                <>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <div>
                      <label className={labelClass} htmlFor="split-cash">
                        Cash
                      </label>
                      <input
                        id="split-cash"
                        type="number"
                        inputMode="decimal"
                        min="0"
                        step="0.01"
                        value={cashAmount}
                        onChange={(e) => {
                          setCashAmount(e.target.value);
                          if (
                            !cashReceived ||
                            parseFloat(cashReceived) < parseFloat(e.target.value)
                          ) {
                            setCashReceived(e.target.value);
                          }
                        }}
                        placeholder="0.00"
                        className={fieldClass}
                      />
                    </div>
                    <div>
                      <label className={labelClass} htmlFor="split-upi">
                        UPI / QR
                      </label>
                      <input
                        id="split-upi"
                        type="number"
                        inputMode="decimal"
                        min="0"
                        step="0.01"
                        value={upiAmount}
                        onChange={(e) => setUpiAmount(e.target.value)}
                        placeholder="0.00"
                        className={fieldClass}
                      />
                    </div>
                    <div>
                      <label className={labelClass} htmlFor="split-card">
                        Card
                      </label>
                      <input
                        id="split-card"
                        type="number"
                        inputMode="decimal"
                        min="0"
                        step="0.01"
                        value={cardAmount}
                        onChange={(e) => setCardAmount(e.target.value)}
                        placeholder="0.00"
                        className={fieldClass}
                      />
                    </div>
                    <div>
                      <label className={labelClass} htmlFor="split-khata">
                        Khata (owed)
                      </label>
                      <input
                        id="split-khata"
                        type="number"
                        inputMode="decimal"
                        min="0"
                        step="0.01"
                        disabled={!haveCustomer}
                        value={khataAmount}
                        onChange={(e) => setKhataAmount(e.target.value)}
                        placeholder={haveCustomer ? "0.00" : "Name the customer below"}
                        className={fieldClass}
                      />
                    </div>
                  </div>

                  {remaining > 0 && selectedCustomer && (
                    <button
                      type="button"
                      onClick={() => setKhataAmount(remaining.toFixed(2))}
                      className="focus-ring cursor-pointer rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-1.5 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
                    >
                      Put the remaining {formatCurrency(remaining)} on khata
                    </button>
                  )}
                </>
              )}

              {mode === "due" && (
                <>
                  <div>
                    <label className={labelClass} htmlFor="khata-amount">
                      Owed by {selectedCustomer?.name}
                    </label>
                    <input
                      id="khata-amount"
                      type="number"
                      inputMode="decimal"
                      min="0"
                      step="0.01"
                      value={khataAmount}
                      onChange={(e) => setKhataAmount(e.target.value)}
                      className={fieldClass}
                    />
                  </div>
                  {selectedCustomer && (
                    <p className="m-0 text-[11.5px] font-medium text-[var(--text-tertiary)]">
                      Already owed: {formatCurrency(selectedCustomer.balance_amount ?? 0)}. This
                      bill adds to that.
                    </p>
                  )}
                </>
              )}

              {(mode === "cash" || mode === "online") && customerBlock}

              {/* Khata is the one way of paying with a precondition, so the way
                  to meet it sits with it rather than as a dead control. */}
              {!selectedCustomer && mode === "due" && !haveCustomer && (
                <div className="flex flex-wrap items-center gap-2.5 rounded-[14px] border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-4 py-3">
                  <Users className="h-4 w-4 shrink-0 text-[var(--warning-strong)]" />
                  <p className="m-0 flex-1 text-[12.5px] font-semibold text-[var(--warning-strong)]">
                    Khata is money owed by a named customer. Attach one to put this bill
                    on credit.
                  </p>
                  {onAttachCustomer && (
                    <button
                      type="button"
                      onClick={() => {
                        onClose();
                        onAttachCustomer();
                      }}
                      className="focus-ring cursor-pointer rounded-[10px] border border-[var(--warning)]/40 bg-[var(--surface)] px-3 py-1.5 text-[11.5px] font-bold text-[var(--warning-strong)] transition-colors hover:bg-[var(--warning)]/15"
                    >
                      Attach customer
                    </button>
                  )}
                </div>
              )}

              {requireBuyerGstin && (
                <div>
                  <label className={labelClass} htmlFor="buyer-gstin">
                    Buyer GSTIN
                  </label>
                  <input
                    id="buyer-gstin"
                    type="text"
                    value={buyerGstin}
                    onChange={(e) => setBuyerGstin(e.target.value.toUpperCase())}
                    placeholder="22AAAAA0000A1Z5"
                    maxLength={15}
                    aria-invalid={gstinLooksWrong}
                    aria-describedby="buyer-gstin-help"
                    className={`${refClass} font-mono ${
                      gstinLooksWrong ? "border-[var(--error)]" : ""
                    }`}
                  />
                  <p
                    id="buyer-gstin-help"
                    className={`mt-1.5 text-[11px] font-semibold ${
                      gstinLooksWrong
                        ? "text-[var(--error-strong)]"
                        : "text-[var(--text-tertiary)]"
                    }`}
                  >
                    {gstinLooksWrong
                      ? "That is not a valid GSTIN."
                      : "Required for this shop, so the buyer can claim input credit."}
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Where the bill stands, then the one action that finishes it. */}
          <footer className="shrink-0 border-t border-[var(--border-soft)] bg-[var(--bg-base)] px-5 py-4">
            <div className="mb-3 flex flex-wrap items-center gap-3">
              <span className="tnum font-mono text-[12.5px] font-bold text-[var(--text-secondary)]">
                {formatCurrency(totalAllocated)}
                <span className="text-[var(--text-tertiary)]">
                  {" "}
                  / {formatCurrency(totalAmount)}
                </span>
              </span>

              <span className="ml-auto">
                {remaining > 0 ? (
                  <span className="tnum font-mono text-[13px] font-bold text-[var(--warning-strong)]">
                    {formatCurrency(remaining)} still to allocate
                  </span>
                ) : totalAllocated > totalAmount ? (
                  <span className="tnum font-mono text-[13px] font-bold text-[var(--error-strong)]">
                    Over by {formatCurrency(totalAllocated - totalAmount)}
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1.5 text-[13px] font-extrabold text-[var(--success-dark)]">
                    <CheckCircle className="h-4 w-4" />
                    Ready
                  </span>
                )}
              </span>
            </div>

            <div className="mb-4 h-1.5 overflow-hidden rounded-full bg-[var(--border-soft)]">
              <div
                className={`h-full rounded-full transition-[width] duration-200 ${
                  totalAllocated > totalAmount
                    ? "bg-[var(--error)]"
                    : remaining > 0
                      ? "bg-[var(--warning)]"
                      : "bg-[var(--success)]"
                }`}
                style={{
                  width: `${
                    totalAmount > 0 ? Math.min(100, (totalAllocated / totalAmount) * 100) : 0
                  }%`,
                }}
              />
            </div>

            <div className="flex gap-3">
              <button
                type="button"
                onClick={onClose}
                className="focus-ring cursor-pointer rounded-[12px] border border-[var(--border-soft)] bg-[var(--surface)] px-5 py-3 text-xs font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={!isValid || gstinBlocksSale || customerBlocksSale || savingCustomer}
                className="focus-ring flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-[12px] border border-[var(--success)]/40 bg-[var(--success)]/20 py-3 text-xs font-extrabold text-[var(--success-dark)] transition-colors hover:bg-[var(--success)]/30 disabled:cursor-not-allowed disabled:opacity-45"
              >
                {savingCustomer ? "Saving customer…" : "Confirm & print receipt"}
                <ArrowRight className="h-4 w-4" />
              </button>
            </div>
          </footer>
        </form>
      </div>
    </div>
  );
}
