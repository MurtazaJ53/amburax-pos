"use client";

import React, { useCallback, useEffect, useState } from "react";
import {
  Building2,
  Receipt,
  Printer,
  CreditCard,
  CheckCircle2,
  Download,
  Save,
} from "lucide-react";

import {
  BUSINESS_TYPE_OPTIONS,
  FEATURE_TOGGLES,
  businessTypeLabel,
  isOfferedBusinessType,
} from "@/lib/business-types";
import { useServerRefresh } from "@/lib/use-server-refresh";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}




export function StoreSettings({
  currentShopName = "Business Hub Supermarket",
  planTier = "starter",
}: {
  currentShopName?: string;
  planTier?: string;
}) {
  const refreshServerData = useServerRefresh();
  const [activeTab, setActiveTab] = useState<"general" | "tax" | "hardware" | "plan">("general");

  // Form State
  const [shopName, setShopName] = useState(currentShopName);
  const [legalName, setLegalName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [address, setAddress] = useState("");
  const [currency, setCurrency] = useState("INR");
  // Printed on the khata reminder as a one-tap pay link.
  const [upiVpa, setUpiVpa] = useState("");

  // What kind of shop this is, and the three things that answer changes.
  // Chosen at signup in the first thirty seconds, so it has to be fixable here.
  const [businessType, setBusinessType] = useState("retail");
  const [features, setFeatures] = useState<Record<string, boolean>>({});

  // Tax State
  const [gstin, setGstin] = useState("");
  const [invoicePrefix, setInvoicePrefix] = useState("");
  const [footerNotes, setFooterNotes] = useState("");

  // Hardware State
  const [paperWidth, setPaperWidth] = useState<"58mm" | "80mm">("80mm");
  const [autoPrint, setAutoPrint] = useState(true);
  const [scannerDelay, setScannerDelay] = useState("50");

  const [savedSuccess, setSavedSuccess] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/settings");
      if (!res.ok) throw new Error(`Could not load settings (${res.status})`);
      const data = await res.json();
      setShopName(data.name ?? "");
      setLegalName(data.legal_name ?? "");
      setPhone(data.business_phone ?? "");
      setEmail(data.business_email ?? "");
      setAddress(data.address ?? "");
      setCurrency(data.currency_code || "INR");
      setUpiVpa(data.upi_vpa ?? "");
      setGstin(data.gstin ?? "");
      setInvoicePrefix(data.invoice_prefix ?? "");
      setFooterNotes(data.footer ?? "");
      setBusinessType(data.business_type ?? "retail");
      // Resolved server-side from type + plan + any override, so the switches
      // show what is actually true rather than what has been explicitly set.
      setFeatures(data.features ?? {});
    } catch (err) {
      setError(errorMessage(err, "Something went wrong loading settings."));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    setError(null);
    setSavedSuccess(false);
    try {
      const res = await fetch("/api/settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: shopName,
          legal_name: legalName,
          business_phone: phone,
          business_email: email,
          address,
          currency_code: currency,
          upi_vpa: upiVpa,
          gstin,
          invoice_prefix: invoicePrefix,
          footer: footerNotes,
          business_type: businessType,
          features,
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => null);
        // The backend explains exactly which field is wrong (GSTIN shape, UPI
        // shape, empty name); showing its message beats a generic failure.
        throw new Error(
          typeof body?.error === "string" ? body.error : `Could not save (${res.status})`
        );
      }
      // Re-read so the form shows exactly what was stored (the server trims and
      // uppercases the GSTIN).
      await load();
      refreshServerData();
      setSavedSuccess(true);
      setTimeout(() => setSavedSuccess(false), 3000);
    } catch (err) {
      setError(errorMessage(err, "Could not save settings."));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="space-y-6 max-w-4xl">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-text-primary tracking-tight">Store & POS Settings</h2>
          <p className="text-xs text-[var(--text-tertiary)]">
            Configure store profile, GSTIN parameters, thermal receipt layout, and hardware
          </p>
        </div>

        {savedSuccess && (
          <div className="flex items-center gap-1.5 px-3 py-1.5 bg-[var(--success)]/10 border border-[var(--success)]/30 text-[var(--success)] text-xs font-semibold rounded-xl animate-in fade-in">
            <CheckCircle2 className="w-4 h-4" />
            <span>Settings Saved!</span>
          </div>
        )}
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 border-b border-[var(--border-soft)]">
        <button
          onClick={() => setActiveTab("general")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-2 ${
            activeTab === "general"
              ? "border-[var(--primary)] text-text-primary"
              : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
          }`}
        >
          <Building2 className="w-3.5 h-3.5" />
          <span>Store Profile</span>
        </button>
        <button
          onClick={() => setActiveTab("tax")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-2 ${
            activeTab === "tax"
              ? "border-[var(--primary)] text-text-primary"
              : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
          }`}
        >
          <Receipt className="w-3.5 h-3.5" />
          <span>GST & Invoicing</span>
        </button>
        <button
          onClick={() => setActiveTab("hardware")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-2 ${
            activeTab === "hardware"
              ? "border-[var(--primary)] text-text-primary"
              : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
          }`}
        >
          <Printer className="w-3.5 h-3.5" />
          <span>Printers & Barcode</span>
        </button>
        <button
          onClick={() => setActiveTab("plan")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-2 ${
            activeTab === "plan"
              ? "border-[var(--primary)] text-text-primary"
              : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
          }`}
        >
          <CreditCard className="w-3.5 h-3.5" />
          <span>Plan & Subscription</span>
        </button>
      </div>

      {error && (
        <div className="rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}
      {isLoading && (
        <div className="rounded-2xl border border-border-soft bg-surface px-5 py-4 text-sm font-semibold text-[var(--text-secondary)]">
          Loading settings&hellip;
        </div>
      )}

      <form onSubmit={handleSave} className="space-y-6">
        {/* General Store Tab */}
        {activeTab === "general" && (
          <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl p-6 space-y-4 shadow-xl">
            <h3 className="text-sm font-bold text-text-primary mb-4 pb-2 border-b border-[var(--border-soft)]">
              Store Identity & Contact Information
            </h3>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Store Display Name *
                </label>
                <input
                  type="text"
                  required
                  value={shopName}
                  onChange={(e) => setShopName(e.target.value)}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Legal Entity / Business Name
                </label>
                <input
                  type="text"
                  value={legalName}
                  onChange={(e) => setLegalName(e.target.value)}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Store Phone
                </label>
                <input
                  type="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Contact Email
                </label>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>
            </div>

            <div className="pt-4 border-t border-[var(--border-soft)]">
              <h3 className="text-sm font-bold text-text-primary mb-1">
                What kind of shop is this?
              </h3>
              <p className="text-xs text-[var(--text-tertiary)] mb-4">
                This sets the three switches below. Change either — the switches
                are yours to keep once you touch them.
              </p>

              <div className="max-w-xs">
                <label
                  htmlFor="business-type"
                  className="block text-xs font-semibold text-[var(--text-secondary)] mb-1"
                >
                  Business type
                </label>
                <select
                  id="business-type"
                  value={businessType}
                  onChange={(e) => setBusinessType(e.target.value)}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                >
                  {BUSINESS_TYPE_OPTIONS.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                  {/* A shop already set to a type we no longer offer keeps it.
                      Without this the select would fall back to the first
                      option and silently rewrite their type on the next save. */}
                  {!isOfferedBusinessType(businessType) && (
                    <option value={businessType}>
                      {businessTypeLabel(businessType)}
                    </option>
                  )}
                </select>
              </div>

              <div className="mt-4 space-y-3">
                {FEATURE_TOGGLES.map((toggle) => (
                  <label
                    key={toggle.key}
                    htmlFor={`feature-${toggle.key}`}
                    className="flex items-start gap-3 cursor-pointer"
                  >
                    <input
                      id={`feature-${toggle.key}`}
                      type="checkbox"
                      checked={features[toggle.key] ?? false}
                      onChange={(e) =>
                        setFeatures((current) => ({
                          ...current,
                          [toggle.key]: e.target.checked,
                        }))
                      }
                      className="mt-0.5 w-4 h-4 rounded text-[var(--primary)] focus:ring-0 bg-bg-soft border-[var(--border-soft)]"
                    />
                    <span>
                      <span className="block text-xs text-text-primary font-medium">
                        {toggle.label}
                      </span>
                      <span className="block text-[11px] text-[var(--text-tertiary)]">
                        {toggle.hint}
                      </span>
                    </span>
                  </label>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                UPI ID
              </label>
              <input
                type="text"
                value={upiVpa}
                onChange={(e) => setUpiVpa(e.target.value)}
                placeholder="shopname@okaxis"
                className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
              />
              <p className="mt-1 text-[11px] font-semibold text-[var(--text-tertiary)]">
                Added to khata reminders as a one-tap pay link, and to the receipt
                QR. Leave blank to send reminders without a pay link.
              </p>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Full Physical Address (Printed on Invoices)
              </label>
              <textarea
                rows={3}
                value={address}
                onChange={(e) => setAddress(e.target.value)}
                className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)] resize-none"
              />
            </div>
          </div>
        )}

        {/* Tax & Invoicing Tab */}
        {activeTab === "tax" && (
          <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl p-6 space-y-4 shadow-xl">
            <h3 className="text-sm font-bold text-text-primary mb-4 pb-2 border-b border-[var(--border-soft)]">
              GSTIN & Invoice Numbering Rules
            </h3>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Store GSTIN
                </label>
                <input
                  type="text"
                  value={gstin}
                  onChange={(e) => setGstin(e.target.value)}
                  placeholder="27AAACB1234F1Z5"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)] uppercase font-mono"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Invoice Sequence Prefix
                </label>
                <input
                  type="text"
                  value={invoicePrefix}
                  onChange={(e) => setInvoicePrefix(e.target.value)}
                  placeholder="INV-"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)] font-mono"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Receipt Footer Terms & Policy
              </label>
              <textarea
                rows={3}
                value={footerNotes}
                onChange={(e) => setFooterNotes(e.target.value)}
                className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)] resize-none"
              />
            </div>
          </div>
        )}

        {/* Hardware & Printer Tab */}
        {activeTab === "hardware" && (
          <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl p-6 space-y-4 shadow-xl">
            <h3 className="text-sm font-bold text-text-primary mb-4 pb-2 border-b border-[var(--border-soft)]">
              Thermal Receipt Printers & USB Scanners
            </h3>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Thermal Paper Width
                </label>
                <select
                  value={paperWidth}
                  onChange={(e) => setPaperWidth(e.target.value as "58mm" | "80mm")}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                >
                  <option value="80mm">80mm Standard POS Thermal Roll</option>
                  <option value="58mm">58mm Compact Handheld Roll</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Barcode Scanner Keystroke Gap (ms)
                </label>
                <input
                  type="number"
                  value={scannerDelay}
                  onChange={(e) => setScannerDelay(e.target.value)}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>
            </div>

            <div className="pt-2">
              <label className="flex items-center gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={autoPrint}
                  onChange={(e) => setAutoPrint(e.target.checked)}
                  className="w-4 h-4 rounded text-[var(--primary)] focus:ring-0 bg-bg-soft border-[var(--border-soft)]"
                />
                <span className="text-xs text-text-primary font-medium">
                  Auto-trigger browser print dialog on completing checkout
                </span>
              </label>
            </div>
          </div>
        )}

        {/* Plan & Subscription Tab */}
        {activeTab === "plan" && (
          <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl p-6 space-y-6 shadow-xl">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-sm font-bold text-text-primary">Current Subscription Tier</h3>
                <p className="text-xs text-[var(--text-tertiary)] mt-0.5">
                  Your store is currently running on the {planTier.toUpperCase()} tier
                </p>
              </div>
              <span className="px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider bg-blue-500/20 text-blue-300 border border-blue-500/30">
                {planTier}
              </span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="p-4 rounded-xl bg-[var(--bg-soft)] border border-[var(--border-soft)]">
                <div className="text-xs text-[var(--text-tertiary)]">Product Catalog</div>
                <div className="text-xl font-bold text-text-primary mt-1">Unlimited</div>
              </div>
              <div className="p-4 rounded-xl bg-[var(--bg-soft)] border border-[var(--border-soft)]">
                <div className="text-xs text-[var(--text-tertiary)]">Staff Terminals</div>
                <div className="text-xl font-bold text-text-primary mt-1">5 POS Desks</div>
              </div>
              <div className="p-4 rounded-xl bg-[var(--bg-soft)] border border-[var(--border-soft)]">
                <div className="text-xs text-[var(--text-tertiary)]">GST Invoicing</div>
                <div className="text-xl font-bold text-[var(--success)] mt-1">Full GSTR-1</div>
              </div>
            </div>
          </div>
        )}

        <div className="flex justify-end">
          <button
            type="submit"
            disabled={isSaving || isLoading}
            className="flex items-center gap-2 px-6 py-2.5 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-semibold rounded-xl shadow-lg shadow-blue-500/25 disabled:opacity-50"
          >
            <Save className="w-4 h-4" />
            <span>{isSaving ? "Saving…" : "Save Store Preferences"}</span>
          </button>
        </div>
      </form>

      {/* The counter app backs its local database up to a file; the website
          holds no local data, so the equivalent is a server-side export. It is
          also the honest answer to "what happens to my data if I leave". */}
      <div className="mt-6 rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
        <h3 className="text-sm font-extrabold text-[var(--text-primary)]">
          Export your data
        </h3>
        <p className="mt-1.5 max-w-prose text-xs font-semibold text-[var(--text-secondary)]">
          Downloads every product, customer, sale, purchase and expense for this
          shop as one JSON file, including the stock ledger behind your current
          stock. Owners only.
        </p>
        <a
          href="/api/export"
          download
          className="mt-3.5 inline-flex items-center gap-2 rounded-xl border border-[var(--border)] px-5 py-2.5 text-xs font-extrabold text-[var(--text-secondary)] hover:border-[var(--primary)] hover:text-[var(--text-primary)]"
        >
          <Download className="w-4 h-4" />
          Download everything
        </a>
      </div>
    </div>
  );
}
