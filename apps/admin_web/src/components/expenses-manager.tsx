"use client";

import {
  ALL_EXPENSE_CATEGORIES,
  EXPENSE_CATEGORIES,
  QUICK_EXPENSE_CATEGORIES,
} from "@/lib/expense-categories";

import { useT } from "@/lib/i18n";

import React, { useState, useEffect } from "react";
import {
  Wallet,
  Plus,
  Search,
  X,
  Loader2,
  Pencil,
  CalendarDays,
} from "lucide-react";
import { formatCurrency, formatDate } from "@/lib/utils";
import type { Expense, ExpenseSummaryPayload } from "@/lib/types";
import { todayKey } from "@/lib/local-date";

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
  const [paymentMode, setPaymentMode] = useState<string>("CASH");
  const [refNum, setRefNum] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  /** The expense being corrected, or null when recording a new one. The same
   *  form does both: a correction asks exactly the same questions. */
  const [editing, setEditing] = useState<Expense | null>(null);
  const [expenseDate, setExpenseDate] = useState<string>("");
  const [submitError, setSubmitError] = useState("");


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


  /** The four almost every Indian shop pays. Tapping one opens the form with
   *  the category already chosen — the category field is free text, so these
   *  are a shortcut rather than a restriction. */
  const QUICK_CATEGORIES: readonly string[] = QUICK_EXPENSE_CATEGORIES;

  // Local, not UTC. toISOString() renders UTC, so an expense entered after
  // midnight IST was filed against yesterday while the sales beside it were
  // filed against today - and the day book then showed nothing paid out.
  const today = () => todayKey();

  /** Everything selectable in the filter: the standard list plus whatever
   *  this shop has actually recorded, so a category typed by hand can still
   *  be filtered on rather than disappearing from the control. */
  const filterCategories = React.useMemo(() => {
    const seen = new Set<string>(ALL_EXPENSE_CATEGORIES);
    for (const expense of expenses) {
      if (expense.category?.trim()) seen.add(expense.category.trim());
    }
    return [...seen].sort((a, b) => a.localeCompare(b));
  }, [expenses]);

  const openWithCategory = (preset: string) => {
    setEditing(null);
    setCategory(preset);
    setTitle("");
    setAmount("");
    setRefNum("");
    setExpenseDate(today());
    setSubmitError("");
    setIsAddOpen(true);
  };

  /** Load an existing row back into the form so it can be corrected.
   *
   *  Correcting beats deleting and retyping: a delete loses who recorded it
   *  and when, which is the trail the register exists to keep. */
  const openForEdit = (expense: Expense) => {
    setEditing(expense);
    setCategory(expense.category ?? "");
    setTitle(expense.description ?? "");
    setAmount(String(expense.amount ?? ""));
    setPaymentMode(expense.payment_method ?? "CASH");
    setRefNum(expense.payment_reference ?? "");
    setExpenseDate(expense.expense_date ?? today());
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
      expense_date: expenseDate || today(),
    };

    try {
      const res = await fetch(
        editing ? `/api/expenses/${editing.id}` : "/api/expenses",
        {
        method: editing ? "PATCH" : "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      },
      );

      if (!res.ok) {
        const text = await res.text();
        throw new Error(
          text || (editing ? "Could not save the correction." : "Failed to save expense record."),
        );
      }

      // Close modal and reset fields
      setIsAddOpen(false);
      setEditing(null);
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
    <div className="flex min-h-0 flex-1 flex-col gap-4">
      {/* One row: the figures on the left, the action on the right. A title
          card repeating the navbar, three tall tiles and a category panel
          pushed the actual expenses to the bottom of the screen - which is
          where you were finding them. */}
      <div className="flex items-center gap-4 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm animate-fade-in-up">
        <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
          {[
            {
              label: "spent",
              value: formatCurrency(metrics.total),
              detail: `${expenses.length} ${expenses.length === 1 ? "entry" : "entries"}`,
              tone: "text-[var(--error-strong)]",
            },
            {
              label: "from the till",
              value: formatCurrency(metrics.cashOutflow),
              detail: "off cash in hand",
              tone:
                metrics.cashOutflow > 0
                  ? "text-[var(--warning-strong)]"
                  : "text-[var(--text-primary)]",
            },
            {
              label: "bank / upi / card",
              value: formatCurrency(metrics.digitalOutflow),
              detail: "not from the drawer",
              tone: "text-[var(--text-primary)]",
            },
            {
              label: "biggest",
              value: byCategory.length > 0 ? byCategory[0].name : "--",
              detail:
                byCategory.length > 0
                  ? formatCurrency(byCategory[0].value)
                  : "nothing recorded yet",
              tone: "text-[var(--text-primary)]",
            },
          ].map((stat, index) => (
            <div
              key={stat.label}
              className={`flex shrink-0 flex-col justify-center ${
                index > 0 ? "border-l border-[var(--border-soft)] pl-4" : ""
              }`}
            >
              <dt className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                {stat.label}
              </dt>
              <dd className="m-0 flex items-baseline gap-1.5">
                <span
                  className={`tnum max-w-[180px] truncate font-mono text-[17px] font-bold leading-tight ${stat.tone}`}
                >
                  {stat.value}
                </span>
                <span className="whitespace-nowrap text-[11px] font-semibold text-[var(--text-tertiary)]">
                  {stat.detail}
                </span>
              </dd>
            </div>
          ))}
        </dl>

        <button
          onClick={() => openWithCategory("")}
          className="focus-ring inline-flex shrink-0 cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3.5 py-2 text-[12px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20"
        >
          <Plus className="h-4 w-4" />
          Record expense
        </button>
      </div>

      {/* Quick picks stay - one tap to the commonest few - but as a strip
          rather than a panel of their own. */}
      <div className="no-scrollbar flex items-center gap-2 overflow-x-auto">
        <span className="shrink-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
          Quick add
        </span>
        {QUICK_CATEGORIES.map((preset: string) => (
          <button
            key={preset}
            type="button"
            onClick={() => openWithCategory(preset)}
            className="focus-ring shrink-0 cursor-pointer whitespace-nowrap rounded-full border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-1.5 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)]"
          >
            {preset}
          </button>
        ))}
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
          <option value="all">All categories</option>
          {filterCategories.map((c: string) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </div>

      {/* Expenses Table */}
      {/* The figures, the quick picks and the filters hold still; only the
          entries scroll. Reaching the bottom of a long month used to take the
          totals and the search box off the top with it. */}
      <div className="relative flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] shadow-sm">
        {isLoading && (
          <div className="absolute inset-0 bg-surface/50 backdrop-blur-[1px] flex items-center justify-center z-10">
            <Loader2 className="w-6 h-6 text-primary animate-spin" />
          </div>
        )}
        <div className="min-h-0 flex-1 overflow-auto">
          <table className="w-full border-collapse text-left text-xs">
            {/* Pinned, so you still know which column is Amount a hundred
                rows down. */}
            <thead className="sticky top-0 z-10">
              <tr className="bg-bg-soft border-b border-[var(--border-soft)] text-[var(--text-tertiary)] font-semibold uppercase tracking-wider text-[10px]">
                <th className="py-3 px-4">Expense Title</th>
                <th className="py-3 px-4">{t("webCategory", "Category")}</th>
                <th className="py-3 px-4">Date</th>
                <th className="py-3 px-4 text-center">Payment Mode</th>
                <th className="py-3 px-4">Reference / Voucher</th>
                <th className="py-3 px-4 text-right">Amount</th>
                <th className="py-3 px-4 text-right">Actions</th>
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
                    <td className="tnum py-3 px-4 text-right font-mono font-bold text-[var(--error-strong)]">
                      {formatCurrency(parseFloat(exp.amount || "0"))}
                    </td>
                    <td className="py-3 px-4 text-right">
                      {/* Correcting beats deleting and retyping: a delete
                          loses who recorded it and when, which is the trail
                          this register exists to keep. */}
                      <button
                        type="button"
                        onClick={() => openForEdit(exp)}
                        aria-label={`Edit ${exp.description || exp.category}`}
                        className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-[var(--border-soft)] bg-[var(--surface)] px-2.5 py-1.5 text-[11px] font-bold text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)]"
                      >
                        <Pencil className="h-3 w-3" />
                        Edit
                      </button>
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
          onClick={() => {
            setIsAddOpen(false);
            setEditing(null);
          }}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-bg-soft">
              <div className="flex items-center gap-2">
                <Wallet className="w-5 h-5 text-primary" />
                <span className="font-semibold text-sm text-text-primary">
                  {editing ? "Correct this expense" : "Record an expense"}
                </span>
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
                    {/* Grouped: a flat list of thirty is not read, it is
                        scrolled past. A category the shop typed itself is
                        kept at the top so an edit does not silently move it. */}
                    {category && !ALL_EXPENSE_CATEGORIES.includes(category) && (
                      <option value={category}>{category}</option>
                    )}
                    {EXPENSE_CATEGORIES.map((group) => (
                      <optgroup key={group.group} label={group.group}>
                        {group.items.map((c) => (
                          <option key={c} value={c}>
                            {c}
                          </option>
                        ))}
                      </optgroup>
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

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Date of expense
                </label>
                <div className="relative">
                  <CalendarDays className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-[var(--text-tertiary)]" />
                  <input
                    type="date"
                    value={expenseDate}
                    max={today()}
                    onChange={(e) => setExpenseDate(e.target.value)}
                    className="tnum w-full rounded-xl border border-[var(--border-soft)] bg-bg-soft py-2 pl-9 pr-3 font-mono text-xs font-bold text-text-primary focus:outline-none"
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
                    onChange={(e) => setPaymentMode(e.target.value)}
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  >
                    <option value="CASH">Cash (From Till Float)</option>
                    <option value="UPI">UPI / QR</option>
                    <option value="BANK">Bank transfer (NEFT / RTGS)</option>
                    {/* The API has always accepted these two; the form simply
                        never offered them, so a card payment had to be filed
                        as something it was not. */}
                    <option value="CARD">Card</option>
                    <option value="OTHER">Other</option>
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
