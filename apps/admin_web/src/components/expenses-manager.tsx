"use client";

import { useT } from "@/lib/i18n";

import React, { useState, useEffect } from "react";
import {
  Wallet,
  Plus,
  Search,
  X,
  Loader2,
} from "lucide-react";
import { StatTile } from "@/components/ui/stat-tile";
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
    const sum = (rows: Expense[]) =>
      rows.reduce((s, e) => s + (parseFloat(e.amount || "0") || 0), 0);
    const cashOutflow = sum(expenses.filter((e) => e.payment_method === "CASH"));
    // Everything that did not come out of the drawer. Grouping UPI, bank and
    // card together is the distinction that matters here: till cash has to be
    // counted against the drawer at close, the rest does not.
    const digitalOutflow = sum(expenses.filter((e) => e.payment_method !== "CASH"));
    return { total, cashOutflow, digitalOutflow };
  }, [expenses, summary]);

  /** Spend per category, biggest first. The summary endpoint reports only the
   *  biggest one, which cannot answer "where is the money actually going". */
  const byCategory = React.useMemo(() => {
    const totals = new Map<string, number>();
    for (const e of expenses) {
      const key = (e.category || "Uncategorised").trim() || "Uncategorised";
      totals.set(key, (totals.get(key) ?? 0) + (parseFloat(e.amount || "0") || 0));
    }
    return [...totals.entries()]
      .map(([name, value]) => ({ name, value }))
      .sort((a, b) => b.value - a.value);
  }, [expenses]);

  const categoryPeak = byCategory[0]?.value ?? 0;

  /** The four almost every Indian shop pays. Tapping one opens the form with
   *  the category already chosen — the category field is free text, so these
   *  are a shortcut rather than a restriction. */
  const QUICK_CATEGORIES = ["Rent", "Electricity", "Staff wages", "Transport"];

  const openWithCategory = (preset: string) => {
    setCategory(preset);
    setTitle("");
    setAmount("");
    setRefNum("");
    setSubmitError("");
    setIsAddOpen(true);
  };

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
            className="flex items-center gap-1.5 px-4 py-2 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-semibold rounded-xl shadow-md shadow-blue-500/20"
          >
            <Plus className="w-4 h-4" />
            <span>Record Expense</span>
          </button>
        </div>
      </div>

      {/* Three figures: what went out, and out of which pocket */}
      <div className="grid gap-3.5 sm:grid-cols-3">
        <StatTile
          label="Total recorded"
          value={formatCurrency(metrics.total)}
          note={`${expenses.length} ${expenses.length === 1 ? "entry" : "entries"}${
            byCategory.length > 0 ? ` across ${byCategory.length} categories` : ""
          }`}
          className="animate-fade-in-up delay-1"
        />
        <StatTile
          label="Paid from till"
          value={formatCurrency(metrics.cashOutflow)}
          note="Comes straight off cash in hand"
          tone={metrics.cashOutflow > 0 ? "warning" : "neutral"}
          noteToneOverride="neutral"
          className="animate-fade-in-up delay-2"
        />
        <StatTile
          label="Paid by bank or UPI"
          value={formatCurrency(metrics.digitalOutflow)}
          note="NEFT, RTGS, UPI or card"
          className="animate-fade-in-up delay-3"
        />
      </div>

      {/* Where the money actually goes, and one tap to add more of it */}
      <div className="rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm animate-fade-in-up delay-2">
        <h3 className="text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
          {byCategory.length > 0 ? "Where it went" : "The four every shop pays"}
        </h3>
        <p className="mt-0.5 text-[12px] font-medium text-[var(--text-secondary)]">
          {byCategory.length > 0
            ? "Biggest first. Categories are what keep the profit figure honest."
            : "Tap one to record it — you can still type any category you like."}
        </p>

        {byCategory.length > 0 && (
          <ul className="m-0 mt-3.5 flex list-none flex-col gap-2 p-0">
            {byCategory.slice(0, 5).map((row) => (
              <li key={row.name} className="flex items-center gap-3">
                <span className="w-28 flex-none truncate text-[12.5px] font-bold text-[var(--text-primary)]">
                  {row.name}
                </span>
                <span className="h-2 flex-1 overflow-hidden rounded-full bg-[var(--bg-soft)]">
                  <span
                    className="block h-full rounded-full bg-[var(--primary-bright)]"
                    style={{
                      width: `${categoryPeak > 0 ? (row.value / categoryPeak) * 100 : 0}%`,
                    }}
                  />
                </span>
                <span className="tnum w-24 flex-none text-right font-mono text-[12.5px] font-bold text-[var(--text-primary)]">
                  {formatCurrency(row.value)}
                </span>
              </li>
            ))}
          </ul>
        )}

        <div className="mt-3.5 flex flex-wrap gap-2">
          {QUICK_CATEGORIES.map((preset) => (
            <button
              key={preset}
              type="button"
              onClick={() => openWithCategory(preset)}
              className="focus-ring cursor-pointer rounded-[10px] border border-transparent bg-[var(--primary)]/10 px-3.5 py-2 text-[12.5px] font-bold text-[var(--primary-hover)] transition-colors hover:border-[var(--primary)]"
            >
              {preset}
            </button>
          ))}
          <button
            type="button"
            onClick={() => setIsAddOpen(true)}
            className="focus-ring cursor-pointer rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2 text-[12.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
          >
            Something else
          </button>
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
                    {search.trim() || categoryFilter !== "all"
                      ? "No expenses match this search."
                      : "Nothing recorded yet. Every rupee logged here is one the profit figure stops overstating."}
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
                            ? "bg-[var(--warning)]/10 text-[var(--warning-strong)]"
                            : "bg-[var(--primary)]/10 text-[var(--primary-hover)]"
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
                  className="px-5 py-2 text-xs font-semibold text-[var(--primary-dark)] bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 rounded-xl shadow-md flex items-center gap-1.5 disabled:opacity-50 border border-[var(--primary)]/25"
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
