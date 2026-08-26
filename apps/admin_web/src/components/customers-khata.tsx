"use client";

import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  Search,
  Plus,
  Phone,
  Mail,
  ArrowUpRight,
  ArrowDownLeft,
  X,
  Loader2,
  Pencil,
  ChevronDown,
  Receipt,
} from "lucide-react";
import { formatCurrency, formatDate } from "@/lib/utils";
import type { Customer, CustomerSummaryPayload } from "@/lib/types";
import { useT } from "@/lib/i18n";
import { formatQuantity, linesSummary, saleLines } from "@/lib/ledger-items";
import type { LedgerSale } from "@/lib/ledger-items";
import { useServerRefresh } from "@/lib/use-server-refresh";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



interface CustomersKhataProps {
  initialCustomers: Customer[];
  initialSummary: CustomerSummaryPayload;
  shopId: string;
}


/** Pull the timeline rows out of the API payload.
 *
 * Guarded because `setTimeline(payload.entries || [])` is a trap: when the
 * payload is an array, `.entries` is Array.prototype.entries — a truthy
 * FUNCTION — and React runs a function passed to a setter as a state updater,
 * which throws "Cannot convert undefined or null to object".
 */
type TimelineEntry = {
  id: string;
  event_type?: string;
  amount_delta: string;
  running_balance?: string;
  note?: string;
  occurred_at?: string;
  actor_name?: string | null;
  /** The sale this line came from, when the entry recorded one. Null for
   *  opening balances, manual adjustments, and rows written before the
   *  timeline started carrying the sale id. */
  sale?: LedgerSale | null;
};

function readTimelineEntries(payload: unknown): TimelineEntry[] {
  if (Array.isArray(payload)) return payload as TimelineEntry[];
  const entries = (payload as { entries?: unknown })?.entries;
  return Array.isArray(entries) ? (entries as TimelineEntry[]) : [];
}

export function CustomersKhata({ initialCustomers, initialSummary }: CustomersKhataProps) {
  const refreshServerData = useServerRefresh();
  const t = useT();
  const [customers, setCustomers] = useState<Customer[]>(initialCustomers ?? []);
  const [summary, setSummary] = useState<CustomerSummaryPayload>(initialSummary ?? { total_customers: 0, active_credit_customers: 0, total_outstanding_balance: "0.00", total_lifetime_spend: null });
  const [selectedCustomerId, setSelectedCustomerId] = useState<string>(
    (initialCustomers ?? [])[0]?.id || ""
  );
  const [search, setSearch] = useState("");
  const [timeline, setTimeline] = useState<TimelineEntry[]>([]);
  // Which ledger rows have their basket open. Collapsed by default: the
  // timeline is scanned for the balance far more often than it is read
  // line by line.
  const [openBaskets, setOpenBaskets] = useState<Set<string>>(new Set());
  const [isTimelineLoading, setIsTimelineLoading] = useState(false);
  // Read inside the search effect without making it a dependency: the
  // effect needs the selection as it stands when the response lands, and
  // depending on it would refetch the list on every selection change.
  const selectedCustomerIdRef = useRef(selectedCustomerId);
  useEffect(() => {
    selectedCustomerIdRef.current = selectedCustomerId;
  }, [selectedCustomerId]);

  // Modal states
  const [isAddCustomerOpen, setIsAddCustomerOpen] = useState(false);
  const [isTxnModalOpen, setIsTxnModalOpen] = useState(false);
  const [txnType, setTxnType] = useState<"credit" | "debit">("credit");
  const [txnAmount, setTxnAmount] = useState("");
  const [txnDesc, setTxnDesc] = useState("");

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");

  // Add customer form
  const [newName, setNewName] = useState("");
  const [newPhone, setNewPhone] = useState("");
  const [newEmail, setNewEmail] = useState("");
  const [newNotes, setNewNotes] = useState("");
  const [newWorkAddress, setNewWorkAddress] = useState("");
  const [newHomeAddress, setNewHomeAddress] = useState("");
  const [newOpeningBalance, setNewOpeningBalance] = useState("0");

  const selectedCustomer = useMemo(() => {
    return customers.find((c) => c.id === selectedCustomerId) || customers[0] || null;
  }, [customers, selectedCustomerId]);

  // Fetch timeline whenever selected customer changes
  useEffect(() => {
    if (!selectedCustomerId) {
      setTimeline([]);
      return;
    }
    let active = true;
    const fetchTimeline = async () => {
      setIsTimelineLoading(true);
      try {
        const res = await fetch(`/api/customers/${selectedCustomerId}/ledger`);
        if (!res.ok) throw new Error("Failed to load ledger history");
        const data = await res.json();
        if (active) {
          setTimeline(readTimelineEntries(data));
          // Baskets belong to the timeline they were opened on; a fresh
          // timeline starts collapsed.
          setOpenBaskets(new Set());
        }
      } catch (err) {
        console.error(err);
      } finally {
        if (active) setIsTimelineLoading(false);
      }
    };
    fetchTimeline();
    return () => {
      active = false;
    };
  }, [selectedCustomerId]);

  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  const loadMoreCustomers = async () => {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const params = new URLSearchParams({ cursor: nextCursor });
      if (search) params.set("q", search);
      const res = await fetch(`/api/customers?${params.toString()}`);
      if (!res.ok) throw new Error("Could not load more customers.");
      const rows: Customer[] = await res.json();
      // Merged by id: a customer edited in another tab between two pages
      // would otherwise arrive twice.
      setCustomers((previous) => {
        const seen = new Set(previous.map((c) => c.id));
        return [...previous, ...rows.filter((c) => !seen.has(c.id))];
      });
      setNextCursor(res.headers.get("X-Next-Cursor"));
    } catch (err) {
      console.error(err);
    } finally {
      setLoadingMore(false);
    }
  };

  // Debounced search customer list
  useEffect(() => {
    let active = true;
    const fetchFilteredCustomers = async () => {
      try {
        const res = await fetch(`/api/customers?q=${encodeURIComponent(search)}`);
        if (!res.ok) throw new Error("Failed to search customers");
        const data = await res.json();
        if (active) {
          // The list is paged now. On 243 customers the old cap of 200 left
          // 43 of them unreachable from this screen with nothing said, so the
          // cursor is what makes the rest loadable.
          setNextCursor(res.headers.get("X-Next-Cursor"));
          setCustomers(data);
          if (
            data.length > 0 &&
            !data.some((c: Customer) => c.id === selectedCustomerIdRef.current)
          ) {
            setSelectedCustomerId(data[0].id);
          }
        }
      } catch (err) {
        console.error(err);
      }
    };
    const debounce = setTimeout(fetchFilteredCustomers, 300);
    return () => {
      active = false;
      clearTimeout(debounce);
    };
  }, [search]);

  /** The customer being corrected, or null when adding a new one. The same
   *  form serves both: the fields are identical, and a separate edit dialog
   *  would only be a second place for them to drift apart. */
  const [editingCustomer, setEditingCustomer] = useState<Customer | null>(null);

  const openEditCustomer = (customer: Customer) => {
    setEditingCustomer(customer);
    setNewName(customer.name ?? "");
    setNewPhone(customer.phone === "-" ? "" : (customer.phone ?? ""));
    setNewEmail(customer.email ?? "");
    setNewNotes(customer.notes ?? "");
    setNewWorkAddress(customer.work_address ?? "");
    setNewHomeAddress(customer.home_address ?? "");
    setSubmitError("");
    setIsAddCustomerOpen(true);
  };

  const handleSaveEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingCustomer) return;
    setIsSubmitting(true);
    setSubmitError("");
    try {
      const res = await fetch(`/api/customers/${editingCustomer.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: newName,
          phone: newPhone || "-",
          email: newEmail || "",
          notes: newNotes || "",
          work_address: newWorkAddress || "",
          home_address: newHomeAddress || "",
        }),
      });
      if (!res.ok) {
        throw new Error((await res.text()) || "Could not save those changes.");
      }
      const updated = (await res.json()) as Customer;
      setCustomers((previous) => previous.map((c) => (c.id === updated.id ? updated : c)));
      setIsAddCustomerOpen(false);
      setEditingCustomer(null);
      refreshServerData();
    } catch (err) {
      setSubmitError(errorMessage(err, "Could not save those changes."));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleAddCustomer = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    setSubmitError("");

    const payload = {
      name: newName,
      phone: newPhone || "-",
      email: newEmail || undefined,
      notes: newNotes || "",
      work_address: newWorkAddress || "",
      home_address: newHomeAddress || "",
      opening_balance: parseFloat(newOpeningBalance) || 0,
    };

    try {
      const res = await fetch("/api/customers", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || "Failed to create customer.");
      }

      const newCust = await res.json() as Customer;
      
      // Close modal and reset fields
      setIsAddCustomerOpen(false); setEditingCustomer(null);
      setNewName("");
      setNewPhone("");
      setNewEmail("");
      setNewNotes("");
      setNewOpeningBalance("0");

      // Refresh customers list and summary
      const updatedList = await fetch("/api/customers").then((r) => r.json());
      const updatedSummary = await fetch("/api/customers/summary").then((r) => r.json());
      
      setCustomers(updatedList);
      setSummary(updatedSummary);
      refreshServerData();
      setSelectedCustomerId(newCust.id);
    } catch (err) {
      setSubmitError(errorMessage(err, "An error occurred while creating customer."));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRecordKhataTxn = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedCustomer) return;

    setIsSubmitting(true);
    setSubmitError("");

    const amt = parseFloat(txnAmount) || 0;
    const isCredit = txnType === "credit"; // repayment reduces outstanding balance (negative delta)
    const amountDelta = isCredit ? -amt : amt;

    const payload = {
      event_type: isCredit ? "payment" : "adjustment",
      amount_delta: amountDelta,
      total_spent_delta: 0,
      note: txnDesc || (isCredit ? "Repayment received" : "Manual debit adjustment"),
      occurred_at: new Date().toISOString(),
    };

    try {
      const res = await fetch(`/api/customers/${selectedCustomer.id}/ledger`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || "Failed to save ledger transaction.");
      }

      // Close modal and reset fields
      setIsTxnModalOpen(false);
      setTxnAmount("");
      setTxnDesc("");

      // Refresh list, summary, and current customer timeline
      const [updatedList, updatedSummary, updatedTimeline] = await Promise.all([
        fetch("/api/customers").then((r) => r.json()),
        fetch("/api/customers/summary").then((r) => r.json()),
        fetch(`/api/customers/${selectedCustomer.id}/ledger`).then((r) => r.json()),
      ]);

      setCustomers(updatedList);
      setSummary(updatedSummary);
      setTimeline(readTimelineEntries(updatedTimeline));
      // A khata entry changes what the shop is owed, which is a figure the
      // page header renders from the server.
      refreshServerData();
    } catch (err) {
      setSubmitError(errorMessage(err, "An error occurred while saving ledger entry."));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4">
      {/* One row: figures left, action right. Three tall cards plus a title
          line cost a third of the screen on a page whose job is showing
          customers. */}
      <div className="flex items-center gap-4 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm animate-fade-in-up">
        <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
          {[
            {
              label: "customers",
              value: String(summary.total_customers),
              detail: "on the books",
              tone: "text-[var(--text-primary)]",
            },
            {
              label: "on khata",
              value: String(summary.active_credit_customers),
              detail: `of ${summary.total_customers}`,
              tone:
                summary.active_credit_customers > 0
                  ? "text-[var(--warning-strong)]"
                  : "text-[var(--text-primary)]",
            },
            {
              label: "owed to you",
              value: formatCurrency(parseFloat(summary.total_outstanding_balance || "0")),
              detail:
                parseFloat(summary.total_outstanding_balance || "0") > 0
                  ? "across open accounts"
                  : "everyone has settled",
              tone:
                parseFloat(summary.total_outstanding_balance || "0") > 0
                  ? "text-[var(--warning-strong)]"
                  : "text-[var(--success-strong)]",
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
                <span className={`tnum font-mono text-[17px] font-bold leading-tight ${stat.tone}`}>
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
          onClick={() => setIsAddCustomerOpen(true)}
          className="focus-ring inline-flex shrink-0 cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3.5 py-2 text-[12px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20"
        >
          <Plus className="h-4 w-4" />
          Add customer
        </button>
      </div>

      <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 lg:grid-cols-[300px_minmax(0,1fr)]">
        
        {/* Left Side: Customer List */}
        <div className="flex min-h-0 flex-col gap-3 overflow-hidden rounded-[18px] border border-[var(--border-soft)] bg-[var(--surface)] p-3">
          <div className="relative">
            <Search className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search by name or phone..."
              className="w-full pl-9 pr-3 py-2 bg-bg-soft border border-[var(--border-soft)] focus:border-[var(--primary)] rounded-xl text-xs text-text-primary placeholder-[var(--text-tertiary)] outline-none"
            />
          </div>

          {/* The list scrolls itself, so the search box above it stays put and
              the page behind it never moves. */}
          <div className="no-scrollbar min-h-0 flex-1 space-y-1 overflow-y-auto pr-1">
            {customers.length === 0 ? (
              <div className="text-center text-xs text-[var(--text-tertiary)] py-8">
                {t("webNoCustomersFound")}
              </div>
            ) : (
              customers.map((cust) => {
                const isSelected = cust.id === selectedCustomerId;
                const outstanding = parseFloat(cust.balance || "0");
                return (
                  <button
                    key={cust.id}
                    onClick={() => setSelectedCustomerId(cust.id)}
                    className={`w-full text-left p-3 rounded-xl transition-all border flex items-center justify-between ${
                      isSelected
                        ? "bg-primary/10 border-primary/20"
                        : "bg-transparent border-transparent hover:bg-bg-soft"
                    }`}
                  >
                    <div className="min-w-0">
                      <div className="font-semibold text-xs text-text-primary truncate">{cust.name}</div>
                      <div className="text-[10px] text-[var(--text-tertiary)] mt-0.5">{cust.phone}</div>
                    </div>

                    {outstanding > 0 && (
                      <span className="text-[10px] font-bold text-[var(--error-strong)] font-mono whitespace-nowrap bg-[var(--error)]/5 px-2 py-0.5 rounded-full border border-[var(--error)]/10">
                        ₹{outstanding.toLocaleString("en-IN")}
                      </span>
                    )}
                  </button>
                );
              })
            )}

            {/* 243 customers against a 200-row cap meant 43 of them could not
                be reached from this screen, and nothing said so. */}
            {nextCursor && (
              <button
                type="button"
                onClick={() => void loadMoreCustomers()}
                disabled={loadingMore}
                className="focus-ring mt-2 w-full cursor-pointer rounded-xl border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3 py-2 text-[11.5px] font-extrabold text-[var(--primary-dark)] transition-colors duration-200 hover:bg-[var(--primary)]/20 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {loadingMore ? "Loading…" : "Load more customers"}
              </button>
            )}
          </div>
        </div>

        {/* Right Side: Customer Ledger Timeline */}
        {/* A fixed 600px meant this pane was short on a big screen and cut off
            on a small one. It now takes whatever height is left and scrolls
            its own ledger. */}
        <div className="no-scrollbar flex min-h-0 flex-col gap-5 overflow-y-auto rounded-[18px] border border-[var(--border-soft)] bg-[var(--surface)] p-5">
          {selectedCustomer ? (
            <>
              {/* Header profile details */}
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-[var(--border-soft)] pb-4">
                <div>
                  <h3 className="text-base font-bold text-text-primary">{selectedCustomer.name}</h3>
                  <div className="flex flex-wrap gap-x-4 gap-y-1.5 mt-1.5 text-xs text-[var(--text-secondary)]">
                    <span className="flex items-center gap-1">
                      <Phone className="w-3.5 h-3.5 text-[var(--text-tertiary)]" />
                      {selectedCustomer.phone}
                    </span>
                    {selectedCustomer.email && (
                      <span className="flex items-center gap-1">
                        <Mail className="w-3.5 h-3.5 text-[var(--text-tertiary)]" />
                        {selectedCustomer.email}
                      </span>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={() => {
                      setTxnType("debit");
                      setIsTxnModalOpen(true);
                    }}
                    className="flex items-center gap-1 px-3 py-1.5 bg-[var(--error)]/10 hover:bg-[var(--error)]/20 text-[var(--error-strong)] rounded-xl text-xs font-semibold transition-all"
                  >
                    <ArrowUpRight className="w-3.5 h-3.5" />
                    <span>Give Credit (Udhaar)</span>
                  </button>

                  {/* A misspelled name or a wrong number was permanent until
                      now: the server has always allowed the edit, but nothing
                      in the web app could reach it. */}
                  <button
                    type="button"
                    onClick={() => selectedCustomer && openEditCustomer(selectedCustomer)}
                    className="focus-ring flex cursor-pointer items-center gap-1 rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-1.5 text-xs font-semibold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
                  >
                    <Pencil className="h-3.5 w-3.5" />
                    <span>Edit</span>
                  </button>
                  
                  <button
                    onClick={() => {
                      setTxnType("credit");
                      setIsTxnModalOpen(true);
                    }}
                    className="flex items-center gap-1.5 px-3 py-2 bg-[var(--success-dark)] hover:bg-[var(--success)] text-white rounded-xl text-xs font-semibold transition-all shadow-md"
                  >
                    <ArrowDownLeft className="w-3.5 h-3.5" />
                    <span>Record Repayment</span>
                  </button>
                </div>
              </div>

              {/* Outstanding metrics box */}
              <div className="grid grid-cols-2 gap-4 bg-bg-soft border border-[var(--border-soft)] rounded-2xl p-4">
                <div>
                  <div className="text-[10px] font-bold text-[var(--text-tertiary)] uppercase tracking-wider">
                    Total Outstanding Due
                  </div>
                  <div className="text-base font-black font-mono text-[var(--error-strong)] mt-0.5">
                    {formatCurrency(parseFloat(selectedCustomer.balance || "0"))}
                  </div>
                </div>
                <div>
                  <div className="text-[10px] font-bold text-[var(--text-tertiary)] uppercase tracking-wider">
                    {t("webLifetimeSpend")}
                  </div>
                  <div className="text-base font-black font-mono text-text-primary mt-0.5">
                    {formatCurrency(parseFloat(selectedCustomer.total_spent || "0"))}
                  </div>
                </div>
              </div>

              {/* Timeline feed */}
              <div className="flex-1 overflow-y-auto space-y-4 pr-1 relative">
                {isTimelineLoading && (
                  <div className="absolute inset-0 bg-surface/50 backdrop-blur-[1px] flex items-center justify-center z-10">
                    <Loader2 className="w-6 h-6 text-primary animate-spin" />
                  </div>
                )}
                
                <div className="text-xs font-bold text-text-primary">Ledger History Timeline</div>
                {timeline.length === 0 ? (
                  <div className="text-center text-xs text-[var(--text-tertiary)] py-12">
                    {t("webNoLedgerYet")}
                  </div>
                ) : (
                  <div className="relative pl-4 border-l border-[var(--border-soft)] ml-2 space-y-4 pt-1">
                    {timeline.map((entry) => {
                      const isCredit = parseFloat(entry.amount_delta) < 0;
                      const amtAbs = Math.abs(parseFloat(entry.amount_delta));
                      const lines = saleLines(entry.sale);
                      const isOpen = openBaskets.has(entry.id);
                      return (
                        <div key={entry.id} className="relative group">
                          {/* Dot indicator */}
                          <span
                            className={`absolute -left-[21px] top-1 w-2.5 h-2.5 rounded-full border-2 border-[var(--surface)] ${
                              isCredit ? "bg-[var(--success)]" : "bg-[var(--error)]"
                            }`}
                          />
                          <div className="flex items-start justify-between gap-4">
                            <div>
                              <p className="text-xs font-bold text-text-primary">
                                {entry.note}
                              </p>
                              <span className="text-[10px] text-[var(--text-tertiary)] block mt-0.5">
                                {formatDate(entry.occurred_at)}
                              </span>
                              {entry.actor_name && (
                                <span className="text-[9px] text-[var(--text-tertiary)] italic block mt-0.5">
                                  Logged by: {entry.actor_name}
                                </span>
                              )}
                            </div>
                            
                            <div className="text-right">
                              <span
                                className={`font-mono font-bold text-xs ${
                                  isCredit ? "text-[var(--success-strong)]" : "text-[var(--error-strong)]"
                                }`}
                              >
                                {isCredit ? "-" : "+"} ₹{amtAbs.toLocaleString("en-IN")}
                              </span>
                              <span className="block text-[9px] text-[var(--text-tertiary)] font-mono mt-0.5">
                                Bal: ₹{parseFloat(entry.running_balance || "0").toLocaleString("en-IN")}
                              </span>
                            </div>
                          </div>

                          {/* What the money was for. A khata figure the owner
                              cannot break down is a figure the customer argues
                              with at the counter. */}
                          {lines.length > 0 && (
                            <div className="mt-1.5">
                              <button
                                type="button"
                                onClick={() =>
                                  setOpenBaskets((previous) => {
                                    const next = new Set(previous);
                                    if (next.has(entry.id)) next.delete(entry.id);
                                    else next.add(entry.id);
                                    return next;
                                  })
                                }
                                aria-expanded={isOpen}
                                className="focus-ring inline-flex cursor-pointer items-center gap-1 rounded-[7px] border border-[var(--border-soft)] bg-[var(--bg-app)] px-2 py-1 text-[10px] font-bold text-[var(--text-secondary)] transition-colors hover:bg-[var(--primary)]/10 hover:text-[var(--primary-dark)]"
                              >
                                <Receipt className="h-3 w-3" />
                                {linesSummary(lines)}
                                <ChevronDown
                                  className={`h-3 w-3 transition-transform duration-200 ${
                                    isOpen ? "rotate-180" : ""
                                  }`}
                                />
                              </button>

                              {isOpen && (
                                <ul className="animate-fade-in-up mt-1.5 space-y-1 rounded-[9px] border border-[var(--border-soft)] bg-[var(--bg-app)] p-2">
                                  {lines.map((sold, index) => (
                                    <li
                                      key={`${entry.id}-${index}`}
                                      className="flex items-baseline justify-between gap-3 text-[10px]"
                                    >
                                      <span className="min-w-0 truncate font-semibold text-text-primary">
                                        {sold.name}
                                        {sold.size ? (
                                          <span className="text-[var(--text-tertiary)]"> · {sold.size}</span>
                                        ) : null}
                                        {sold.is_return ? (
                                          <span className="ml-1 rounded-[4px] bg-[var(--error)]/15 px-1 py-px text-[8px] font-bold uppercase tracking-wide text-[var(--error-strong)]">
                                            returned
                                          </span>
                                        ) : null}
                                      </span>
                                      <span className="tnum shrink-0 font-mono text-[var(--text-tertiary)]">
                                        {formatQuantity(sold.quantity)} ×{" "}
                                        {formatCurrency(parseFloat(sold.unit_price || "0"))}
                                      </span>
                                      <span className="tnum shrink-0 font-mono font-bold text-text-primary">
                                        {formatCurrency(parseFloat(sold.line_total || "0"))}
                                      </span>
                                    </li>
                                  ))}
                                  {entry.sale?.receipt_number ? (
                                    <li className="border-t border-[var(--border-soft)] pt-1 text-[9px] font-mono text-[var(--text-tertiary)]">
                                      Bill {entry.sale.receipt_number}
                                      {entry.sale.status === "void" ? " · voided" : ""}
                                    </li>
                                  ) : null}
                                </ul>
                              )}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="flex-1 flex items-center justify-center text-xs text-[var(--text-tertiary)]">
              {customers.length === 0
                ? "No customers yet. Add one, and every sale on credit and every repayment will build their ledger here."
                : "Pick a customer on the left to open their ledger."}
            </div>
          )}
        </div>
      </div>

      {/* MODAL: Record Transaction */}
      {isTxnModalOpen && selectedCustomer && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          onClick={() => setIsTxnModalOpen(false)}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-bg-soft">
              <span className="font-semibold text-sm text-text-primary">
                {txnType === "credit" ? "Record Customer Payment" : "Issue Store Credit (Udhaar)"}
              </span>
              <button
                onClick={() => setIsTxnModalOpen(false)}
                className="p-1 text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleRecordKhataTxn} className="p-6 space-y-4">
              {submitError && (
                <div className="p-3 bg-[var(--error)]/10 border border-[var(--error)]/20 text-[var(--error-strong)] text-xs rounded-xl font-bold">
                  {submitError}
                </div>
              )}

              <p className="text-xs text-[var(--text-secondary)]">
                Record ledger entry for <strong className="text-text-primary">{selectedCustomer.name}</strong>.
              </p>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Amount (₹) *
                </label>
                <input
                  type="number"
                  step="0.01"
                  required
                  value={txnAmount}
                  onChange={(e) => setTxnAmount(e.target.value)}
                  placeholder="0.00"
                  className="w-full px-4 py-2.5 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-base font-mono font-bold text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Description / Reference Note *
                </label>
                <input
                  type="text"
                  required
                  value={txnDesc}
                  onChange={(e) => setTxnDesc(e.target.value)}
                  placeholder={txnType === "credit" ? "e.g. Received via GPay" : "e.g. Credit sale of groceries"}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div className="pt-3 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  disabled={isSubmitting}
                  onClick={() => setIsTxnModalOpen(false)}
                  className="px-4 py-2 text-xs text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className={`px-5 py-2 text-xs font-semibold text-white rounded-xl shadow-md flex items-center gap-1.5 disabled:opacity-50 ${
                    txnType === "credit"
                      ? "bg-[var(--success-dark)] hover:bg-[var(--success)]"
                      : "bg-[var(--error-dark)] hover:bg-[var(--error)]"
                  }`}
                >
                  {isSubmitting && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                  <span>{txnType === "credit" ? "Record Repayment" : "Confirm Udhaar"}</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* MODAL: Add Customer */}
      {isAddCustomerOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          onClick={() => { setIsAddCustomerOpen(false); setEditingCustomer(null); }}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-bg-soft">
              <span className="font-semibold text-sm text-text-primary">{editingCustomer ? "Edit customer" : "Add new customer"}</span>
              <button
                onClick={() => { setIsAddCustomerOpen(false); setEditingCustomer(null); }}
                className="p-1 text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form
              onSubmit={editingCustomer ? handleSaveEdit : handleAddCustomer}
              className="p-6 space-y-4"
            >
              {submitError && (
                <div className="p-3 bg-[var(--error)]/10 border border-[var(--error)]/20 text-[var(--error-strong)] text-xs rounded-xl font-bold">
                  {submitError}
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Customer Full Name *
                </label>
                <input
                  type="text"
                  required
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder="e.g. Ramesh Verma"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Phone Number
                  </label>
                  <input
                    type="text"
                    value={newPhone}
                    onChange={(e) => setNewPhone(e.target.value)}
                    placeholder="e.g. +91 98765 43210"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Email Address
                  </label>
                  <input
                    type="email"
                    value={newEmail}
                    onChange={(e) => setNewEmail(e.target.value)}
                    placeholder="e.g. name@example.com"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
              </div>

              {/* Opening balance seeds the ledger at creation and is never
                  read again — the server only looks at it in create(). Showing
                  it while editing displayed a meaningless 0 next to a real
                  balance of thousands, and editing it would have done nothing.
                  While editing, the live balance is shown instead, read-only:
                  it is the sum of the ledger, and the way to change it is to
                  record a repayment or a credit, not to type over it. */}
              {editingCustomer ? (
                <div className="rounded-xl border border-[var(--border-soft)] bg-[var(--bg-soft)] px-3 py-2.5">
                  <span className="block text-xs font-semibold text-[var(--text-secondary)]">
                    Outstanding balance
                  </span>
                  <span className="tnum mt-0.5 block font-mono text-sm font-bold text-[var(--warning-strong)]">
                    {formatCurrency(parseFloat(editingCustomer.balance || "0"))}
                  </span>
                  <span className="mt-1 block text-[11px] font-medium text-[var(--text-tertiary)]">
                    Built from the ledger. Use Give Credit or Record Repayment to
                    change it.
                  </span>
                </div>
              ) : (
                <div>
                  <label className="mb-1 block text-xs font-semibold text-[var(--text-secondary)]">
                    Opening Udhaar Balance (₹)
                  </label>
                  <input
                    type="number"
                    value={newOpeningBalance}
                    onChange={(e) => setNewOpeningBalance(e.target.value)}
                    placeholder="0.00"
                    className="w-full rounded-xl border border-[var(--border-soft)] bg-bg-soft px-3 py-2 text-xs text-text-primary focus:outline-none"
                  />
                  <p className="mt-1 text-[11px] font-medium text-[var(--text-tertiary)]">
                    What they already owed before this book started. Recorded as
                    the first ledger entry.
                  </p>
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Work address
                </label>
                <input
                  type="text"
                  value={newWorkAddress}
                  onChange={(e) => setNewWorkAddress(e.target.value)}
                  placeholder="Shop or office — where they are during the day"
                  className="w-full rounded-xl border border-[var(--border-soft)] bg-[var(--bg-soft)] px-3 py-2 text-xs text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div>
                <label className="mb-1 block text-xs font-semibold text-[var(--text-secondary)]">
                  Home address
                </label>
                <input
                  type="text"
                  value={newHomeAddress}
                  onChange={(e) => setNewHomeAddress(e.target.value)}
                  placeholder="Optional. Stored encrypted, like the phone number."
                  className="w-full rounded-xl border border-[var(--border-soft)] bg-[var(--bg-soft)] px-3 py-2 text-xs text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div>
                <label className="mb-1 block text-xs font-semibold text-[var(--text-secondary)]">
                  Customer Notes
                </label>
                <textarea
                  value={newNotes}
                  onChange={(e) => setNewNotes(e.target.value)}
                  placeholder="Loyalty details, special terms, credit policies..."
                  rows={3}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>

              <div className="pt-3 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  disabled={isSubmitting}
                  onClick={() => { setIsAddCustomerOpen(false); setEditingCustomer(null); }}
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
                  <span>{editingCustomer ? "Save changes" : "Add customer"}</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
