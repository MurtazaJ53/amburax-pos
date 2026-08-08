"use client";

import { useT } from "@/lib/i18n";

import React, { useState, useEffect } from "react";
import {
  Wallet,
  Plus,
  Search,
  DollarSign,
  X,
  Loader2,
} from "lucide-react";
import { formatCurrency, formatDate } from "@/lib/utils";
import type { Expense, ExpenseSummaryPayload } from "@/lib/types";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



interface ExpensesManagerProps {
  initialExpenses: Expense[];
  initialSummary: ExpenseSummaryPayload;
  shopId: string;
}

export function ExpensesManager({ initialExpenses, initialSummary }: ExpensesManagerProps) {
  const t = useT();
  const [expenses, setExpenses] = useState<Expense[]>(initialExpenses ?? []);
  const [summary, setSummary] = useState<ExpenseSummaryPayload>(initialSummary ?? { total_expenses: 0, total_amount: "0.00", categories: {} });
  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("all");
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  // Add Expense form state
  const [title, setTitle] = useState("");
  const [category, setCategory] = useState("Tea & Refreshments");
  const [amount, setAmount] = useState("");
  const [paymentMode, setPaymentMode] = useState<"CASH" | "BANK" | "UPI">("CASH");
  const [refNum, setRefNum] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");

  const categories = [
    "Rent",
    "Utilities",
    "Staff Salaries",
    "Tea & Refreshments",
    "Packaging",
    "Maintenance",
    "Logistics & Freight",
    "Municipal & Taxes",
  ];

  // Debounced search and filter effect
  useEffect(() => {
    let active = true;
    const fetchFilteredData = async () => {
      setIsLoading(true);
      try {
        const catQuery = categoryFilter === "all" ? "" : categoryFilter;
        const qUrl = `/api/expenses?q=${encodeURIComponent(search)}&category=${encodeURIComponent(catQuery)}`;
        const sUrl = `/api/expenses/summary?q=${encodeURIComponent(search)}&category=${encodeURIComponent(catQuery)}`;

        const [resList, resSum] = await Promise.all([
          fetch(qUrl).then((r) => {
            if (!r.ok) throw new Error("Failed to fetch expenses");
            return r.json() as Promise<Expense[]>;
          }),
          fetch(sUrl).then((r) => {
            if (!r.ok) throw new Error("Failed to fetch summary");
            return r.json() as Promise<ExpenseSummaryPayload>;
          }),
        ]);

        if (active) {
          setExpenses(resList);
          setSummary(resSum);
        }
      } catch (err) {
        console.error(err);
      } finally {
        if (active) setIsLoading(false);
      }
    };

    const debounceTimer = setTimeout(fetchFilteredData, 300);
    return () => {
      active = false;
      clearTimeout(debounceTimer);
    };
  }, [search, categoryFilter]);

  const metrics = React.useMemo(() => {
    const total = parseFloat(summary.total_amount || "0");
    const cashOutflow = expenses
      .filter((e) => e.payment_method === "CASH")
      .reduce((s, e) => s + parseFloat(e.amount || "0"), 0);
    return { total, cashOutflow };
  }, [expenses, summary]);

  const handleAddExpense = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    setSubmitError("");

    const payload = {
      category,
      amount: parseFloat(amount) || 0,
      description: title,
      payment_method: paymentMode,
      payment_reference: refNum,
      expense_date: new Date().toISOString().split("T")[0],
    };

    try {
      const res = await fetch("/api/expenses", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || "Failed to save expense record.");
      }

      // Close modal and reset fields
      setIsAddOpen(false);
      setTitle("");
      setAmount("");
      setRefNum("");
      
      // Refresh list
      const updatedList = await fetch("/api/expenses").then((r) => r.json());
      const updatedSummary = await fetch("/api/expenses/summary").then((r) => r.json());
      setExpenses(updatedList);
      setSummary(updatedSummary);
    } catch (err) {
      setSubmitError(errorMessage(err, "An error occurred while saving the expense."));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-text-primary tracking-tight">
            Expenses & Petty Cash Register
          </h2>
          <p className="text-xs text-[var(--text-tertiary)]">
            Log overhead operating expenses, utility payments, and till cash outflows
          </p>
        </div>

        <div className="flex items-center gap-3">
          <div className="px-4 py-2 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl text-xs">
            <span className="text-[var(--text-secondary)]">Total Recorded Expenses: </span>
            <strong className="text-text-primary font-mono">{formatCurrency(metrics.total)}</strong>
          </div>

          <button
            onClick={() => setIsAddOpen(true)}
            className="flex items-center gap-1.5 px-4 py-2 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white text-xs font-semibold rounded-xl shadow-md shadow-blue-500/20"
          >
            <Plus className="w-4 h-4" />
            <span>Record Expense</span>
          </button>
        </div>
      </div>

      {/* Metrics Row */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="p-4 bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl flex items-center justify-between">
          <div>
            <div className="text-xs text-[var(--text-tertiary)] font-medium">
              Till Cash Outflows
            </div>
            <div className="text-2xl font-black text-[var(--warning-strong)] font-mono mt-1">
              {formatCurrency(metrics.cashOutflow)}
            </div>
            <div className="text-[10px] text-[var(--text-tertiary)] mt-0.5">
              Deducted automatically from daily cash float
            </div>
          </div>
          <Wallet className="w-8 h-8 text-[var(--warning)]/40" />
        </div>

        <div className="p-4 bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl flex items-center justify-between">
          <div>
            <div className="text-xs text-[var(--text-tertiary)] font-medium">
              Digital / Bank Transfers
            </div>
            <div className="text-2xl font-black text-blue-500 font-mono mt-1">
              {formatCurrency(metrics.total - metrics.cashOutflow)}
            </div>
            <div className="text-[10px] text-[var(--text-tertiary)] mt-0.5">
              Paid via NEFT / RTGS / UPI
            </div>
          </div>
          <DollarSign className="w-8 h-8 text-blue-400/40" />
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
            placeholder="Search expense by description or receipt reference..."
            className="w-full pl-10 pr-4 py-2 bg-bg-soft border border-[var(--border-soft)] focus:border-[var(--primary)] rounded-xl text-xs text-text-primary placeholder-[var(--text-tertiary)] outline-none"
          />
        </div>

        <select
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          className="px-3 py-2 bg-bg-soft border border-[var(--border-soft)] text-xs text-text-primary rounded-xl outline-none"
        >
          <option value="all">All Expense Categories</option>
          {categories.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </div>

      {/* Expenses Table */}
      <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl overflow-hidden shadow-xl relative">
        {isLoading && (
          <div className="absolute inset-0 bg-surface/50 backdrop-blur-[1px] flex items-center justify-center z-10">
            <Loader2 className="w-6 h-6 text-primary animate-spin" />
          </div>
        )}
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse text-xs">
            <thead>
              <tr className="bg-bg-soft border-b border-[var(--border-soft)] text-[var(--text-tertiary)] font-semibold uppercase tracking-wider text-[10px]">
                <th className="py-3 px-4">Expense Title</th>
                <th className="py-3 px-4">{t("webCategory", "Category")}</th>
                <th className="py-3 px-4">Date</th>
                <th className="py-3 px-4 text-center">Payment Mode</th>
                <th className="py-3 px-4">Reference / Voucher</th>
                <th className="py-3 px-4 text-right">Amount</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-soft)]">
              {expenses.length === 0 ? (
                <tr>
                  <td colSpan={6} className="py-10 text-center text-xs text-[var(--text-tertiary)]">
                    No expense entries found.
                  </td>
                </tr>
              ) : (
                expenses.map((exp) => (
                  <tr key={exp.id} className="hover:bg-bg-base transition-colors">
                    <td className="py-3 px-4 font-semibold text-text-primary">
                      {exp.description || exp.category}
                    </td>
                    <td className="py-3 px-4 text-[var(--text-secondary)]">
                      <span className="px-2 py-0.5 rounded-full bg-bg-base border border-[var(--border-soft)] text-[10px]">
                        {exp.category}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-[var(--text-tertiary)]">
                      {formatDate(exp.expense_date)}
                    </td>
                    <td className="py-3 px-4 text-center">
                      <span
                        className={`px-2 py-0.5 rounded text-[10px] font-bold uppercase ${
                          exp.payment_method === "CASH"
                            ? "bg-[var(--warning)]/10 text-[var(--warning-strong)] dark:text-[var(--warning)]"
                            : "bg-blue-500/10 text-blue-600 dark:text-blue-400"
                        }`}
                      >
                        {exp.payment_method}
                      </span>
                    </td>
                    <td className="py-3 px-4 font-mono text-[var(--text-tertiary)]">
                      {exp.payment_reference || "—"}
                    </td>
                    <td className="py-3 px-4 text-right font-mono font-bold text-[var(--error-strong)]">
                      {formatCurrency(parseFloat(exp.amount || "0"))}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* MODAL: Record Expense */}
      {isAddOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          onClick={() => setIsAddOpen(false)}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-bg-soft">
              <div className="flex items-center gap-2">
                <Wallet className="w-5 h-5 text-primary" />
                <span className="font-semibold text-sm text-text-primary">Record Operating Expense</span>
              </div>
              <button
                onClick={() => setIsAddOpen(false)}
                className="p-1 text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleAddExpense} className="p-6 space-y-4">
              {submitError && (
                <div className="p-3 bg-[var(--error)]/10 border border-[var(--error)]/20 text-[var(--error-strong)] text-xs rounded-xl font-bold">
                  {submitError}
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Expense Description *
                </label>
                <input
                  type="text"
                  required
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g. July Store Electricity Bill"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Category
                  </label>
                  <select
                    value={category}
                    onChange={(e) => setCategory(e.target.value)}
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  >
                    {categories.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Amount (₹) *
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    required
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    placeholder="0.00"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Payment Mode
                  </label>
                  <select
                    value={paymentMode}
                    onChange={(e) => setPaymentMode(e.target.value as "CASH" | "BANK" | "UPI")}
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  >
                    <option value="CASH">Cash (From Till Float)</option>
                    <option value="UPI">UPI / QR</option>
                    <option value="BANK">Bank Transfer (NEFT/RTGS)</option>
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Bill / Voucher Ref #
                  </label>
                  <input
                    type="text"
                    value={refNum}
                    onChange={(e) => setRefNum(e.target.value)}
                    placeholder="e.g. UTR-8910 or Inv #12"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
              </div>

              <div className="pt-3 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  disabled={isSubmitting}
                  onClick={() => setIsAddOpen(false)}
                  className="px-4 py-2 text-xs text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-5 py-2 text-xs font-semibold text-white bg-[var(--primary)] hover:bg-[var(--primary-hover)] rounded-xl shadow-md flex items-center gap-1.5 disabled:opacity-50"
                >
                  {isSubmitting && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                  <span>Save Expense</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
