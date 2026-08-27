"use client";

import { useT } from "@/lib/i18n";

import React, { useEffect, useMemo, useState } from "react";
import {
  Receipt,
  Search,
  X,
  RotateCcw,
  Lock,
  Undo2,
} from "lucide-react";
import { MixBar } from "@/components/ui/mix-bar";
import type { MixSegment } from "@/components/ui/mix-bar";
import { shopDateKey } from "@/lib/dashboard-metrics";
import { DateRangePicker } from "@/components/ui/date-range-picker";
import { isValidRange, resolveRange } from "@/lib/date-ranges";
import type { DateRange, RangeKey } from "@/lib/date-ranges";
import {
  closeRequestBody,
  discrepancy,
  isMoneyInput,
  moneyValue,
  emptyClose,
  expectedInTill,
  readRegisterPayload,
} from "@/lib/register-close";
import type { RegisterClose } from "@/lib/register-close";
import { formatCurrency, formatDate } from "@/lib/utils";
import { SaleReturnSheet } from "@/components/sale-return-sheet";
import { ThermalReceiptModal } from "@/components/thermal-receipt-modal";
import type { CartItem, SplitPaymentTender } from "@/lib/types";
import { useServerRefresh } from "@/lib/use-server-refresh";
import { useDialog } from "@/components/ui/dialog-provider";

/** The payment slices worth a single click. "All" first, then the tenders in
 *  the order a counter sees them. */
const PAYMENT_CHIPS = [
  { key: "all", label: "All" },
  { key: "cash", label: "Cash" },
  { key: "upi", label: "UPI / QR" },
  { key: "card", label: "Card" },
  { key: "khata", label: "Khata" },
] as const;

/** One word for one thing.
 *
 *  The API's vocabulary and the counter's are not the same. CREDIT is what
 *  the database stores; khata is what the shop says, and what every chip,
 *  badge and total on this screen is labelled. Mapping it once on the way in
 *  keeps the rest of the file speaking a single language.
 */
function normalisePaymentMode(raw: string | undefined): string {
  const mode = (raw || "cash").toLowerCase();
  return mode === "credit" ? "khata" : mode;
}

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
  /** Total refunded per sale id. A return does not alter the sale, so without
   *  this a bill that was fully sent back looks exactly like one that stands. */
  refundedBySale?: Record<string, number>;
  /** The shop's clock, for deciding which day is being closed. */
  timeZone?: string;
  /** The shop a reprint belongs to. It was hardcoded to "Business Hub
   *  Superstore", so every reprinted bill carried a name no shop has. */
  shopName?: string;
  shopGstin?: string;
  shopAddress?: string;
  shopPhone?: string;
  regionCode?: string;
  shopLogo?: string;
  brandColor?: string;
}

/** A sale row as the API returns it. Only the fields this screen reads. */
type ApiSalePayment = { payment_method: string; amount: string };
export type ApiSale = {
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
  // What the server says has been paid and what is still owed. Absent
  // from this type until the sales screen was found reading tenders
  // instead - a field nobody could reach for is a field nobody uses.
  amount_received?: string;
  amount_due?: string;
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

export function toSaleOrder(item: ApiSale): SaleOrder {
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
    // The server calls it CREDIT; a shopkeeper calls it khata, and so does
    // every chip and label on this screen. Translated once, here at the
    // boundary, rather than left to disagree - the Khata filter matched
    // nothing and its count read 0 with credit sales plainly on the list.
    payment_mode: normalisePaymentMode(item.payment_mode),
    payment_breakdown: {
      cash: tenderTotal(payments, "CASH"),
      card: tenderTotal(payments, "CARD"),
      upi: tenderTotal(payments, "UPI"),
      // What is still owed, taken from the sale itself rather than from a
      // CREDIT payment row. There is no such row any more: recording money on
      // khata as a payment is what made the till count it as received, and
      // 670c3e3 stopped writing it - test_no_payment_row_is_stored_for_credit
      // holds it stopped. Reading tenders here meant every credit sale after
      // that fix showed nothing owed on this screen and no khata line on its
      // reprinted receipt, while the ledger, the dashboard and the day book
      // all had it right. amount_due is the server's own arithmetic, so the
      // four tenders now sum to the bill by construction.
      khata_due: parseFloat(item.amount_due || "0"),
    },
    status: item.status || "completed",
    items: (item.items ?? []).map(toReceiptLine),
    items_count: item.item_count || 1,
    created_at: item.occurred_at || new Date().toISOString(),
  } as SaleOrder;
}

const SALES_PAGE_SIZE = 100;

export function SalesManager({
  initialSales,
  initialSummary: _initialSummary,
  shopId,
  refundedBySale = {},
  timeZone = "Asia/Kolkata",
  shopName = "",
  shopGstin = "",
  shopAddress = "",
  shopPhone = "",
  regionCode = "IN",
  shopLogo = "",
  brandColor = "",
}: SalesManagerProps) {
  const { say, ask } = useDialog();
  const refreshServerData = useServerRefresh();
  const t = useT();
  const mappedInitial = React.useMemo(() => {
    return (initialSales ?? []).map(toSaleOrder);
  }, [initialSales]);

  const [sales, setSales] = useState<SaleOrder[]>(mappedInitial);
  const [isLoading, setIsLoading] = useState(false);
  const [_error, setError] = useState<string | null>(null);
  
  const [search, setSearch] = useState("");
  const [paymentFilter, setPaymentFilter] = useState("all");
  // The period is asked of the SERVER. Filtering whatever page of sales the
  // browser happened to hold meant a bill from last year was unreachable no
  // matter what was typed.
  const [rangeKey, setRangeKey] = useState<RangeKey>("last30");
  const [customRange, setCustomRange] = useState<DateRange>({ from: "", to: "" });

  const shopToday = useMemo(() => shopDateKey(new Date(), timeZone), [timeZone]);
  const range = useMemo(
    () => resolveRange(rangeKey, shopToday, customRange),
    [rangeKey, shopToday, customRange],
  );
  // A custom range is only asked for once both ends are set; a half-typed
  // date would otherwise narrow the list to nothing mid-keystroke.
  const rangeIsBounded =
    !range.unbounded && (rangeKey !== "custom" || isValidRange(customRange));
  const [activeView, setActiveView] = useState<"history" | "dayclose">("history");

  // Receipt Modal state
  const [viewingReceipt, setViewingReceipt] = useState<SaleOrder | null>(null);
  const [returningSaleId, setReturningSaleId] = useState<string | null>(null);

  // Day Close Form state
  /** The close for the current shop-day. Both figures start empty: the float
   *  used to be hardcoded to 5,000 and the counted cash pre-filled with
   *  6,450, so the over/short reading was produced from two numbers nobody
   *  had entered. */
  const [registerClose, setRegisterClose] = useState<RegisterClose>(() =>
    emptyClose(shopDateKey(new Date(), timeZone)),
  );
  /** Cash the API summed from the tender rows for this business day. The
   *  browser's own sales list is filtered and paged, so it is the wrong thing
   *  to reconcile a drawer against. */
  const [registerCash, setRegisterCash] = useState<number | null>(null);
  const [closeError, setCloseError] = useState("");
  // What is literally in the two money fields. Kept apart from the numbers
  // because "10." is a valid thing to be part-way through typing and is not a
  // number yet; round-tripping through one would eat the dot.
  const [floatText, setFloatText] = useState("");
  const [countedText, setCountedText] = useState("");
  const [isSavingClose, setIsSavingClose] = useState(false);
  const floatEntered = registerClose.floatEntered;

  useEffect(() => {
    let active = true;
    const date = shopDateKey(new Date(), timeZone);
    const load = async () => {
      try {
        const res = await fetch(`/api/sales/register?date=${date}`);
        if (!res.ok) throw new Error("Could not load the day close.");
        const read = readRegisterPayload(await res.json(), date);
        if (!active) return;
        setRegisterClose(read.close);
        setRegisterCash(read.cashSales);
        setFloatText(read.close.floatEntered ? String(read.close.openingFloat) : "");
        setCountedText(read.close.countedCash ? String(read.close.countedCash) : "");
      } catch (err) {
        // Leaving the day unanswered is the honest failure here. Falling back
        // to zeros would render a confident "Balanced" against figures that
        // were never loaded.
        if (active) setCloseError(errorMessage(err, "Could not load the day close."));
      }
    };
    void load();
    return () => {
      active = false;
    };
  }, [shopId, timeZone]);

  /** Send the count to the server. `lock` signs the day off.
   *
   *  Called when a field is left, not on every keystroke: a drawer count is
   *  typed digit by digit, and a request per digit would put a dozen writes
   *  behind one figure. A rejected write is surfaced rather than swallowed —
   *  a close the cashier believes was saved and was not is the worst outcome
   *  this screen has.
   */
  const persistClose = async (next: RegisterClose, lock = false) => {
    setRegisterClose(next);
    setCloseError("");
    setIsSavingClose(true);
    try {
      const res = await fetch("/api/sales/register", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(closeRequestBody(next, lock)),
      });
      const body = await res.json().catch(() => null);
      if (!res.ok) {
        throw new Error(
          (body as { detail?: string })?.detail || "Could not save the day close.",
        );
      }
      const read = readRegisterPayload(body, next.date);
      setRegisterClose(read.close);
      setRegisterCash(read.cashSales);
      refreshServerData();
    } catch (err) {
      setCloseError(errorMessage(err, "Could not save the day close."));
    } finally {
      setIsSavingClose(false);
    }
  };

  /** One page of bills. `cursor` null means start again from the newest.
   *
   *  The history used to stop at five hundred rows with nothing to say about
   *  it - on nineteen thousand sales, that is the last fortnight and no way
   *  to reach the rest. It is keyset-paged now. */
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  async function fetchPage(cursor: string | null) {
    const query = new URLSearchParams({ limit: String(SALES_PAGE_SIZE) });
    // All time sends no window at all.
    if (rangeIsBounded) {
      query.set("date_from", range.from);
      query.set("date_to", range.to);
    }
    if (cursor) query.set("cursor", cursor);
    const res = await fetch(`/api/sales?${query.toString()}`);
    if (!res.ok) throw new Error("Failed to load sales history");
    const rows = await res.json();
    return {
      sales: (rows as ApiSale[]).map(toSaleOrder),
      cursor: res.headers.get("X-Next-Cursor"),
    };
  }

  async function fetchSales() {
    try {
      setIsLoading(true);
      const page = await fetchPage(null);
      setSales(page.sales);
      setNextCursor(page.cursor);
    } catch (err) {
      setError(errorMessage(err, "Failed to load sales"));
    } finally {
      setIsLoading(false);
    }
  }

  async function loadMoreSales() {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await fetchPage(nextCursor);
      // Merged by id: a bill voided in another tab between two pages would
      // otherwise arrive twice.
      setSales((previous) => {
        const seen = new Set(previous.map((sale) => sale.id));
        return [...previous, ...page.sales.filter((sale) => !seen.has(sale.id))];
      });
      setNextCursor(page.cursor);
    } catch (err) {
      setError(errorMessage(err, "Could not load more bills."));
    } finally {
      setLoadingMore(false);
    }
  }

  // Reload whenever the period changes. The server-rendered list that
  // arrives as a prop covers no particular window, so the first run also
  // makes the rows match the label above them.
  useEffect(() => {
    void fetchSales();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [range.from, range.to, range.unbounded, rangeIsBounded]);

  const handleVoidSale = async (saleId: string) => {
    const agreed = await ask(
      "Void this sale?",
      "The bill comes out of the day's takings and its stock goes back on the shelf. This cannot be undone.",
      { confirmLabel: "Void the sale", tone: "danger" },
    );
    if (!agreed) return;
    try {
      const res = await fetch(`/api/sales/${saleId}/void`, { method: "POST" });
      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || "Failed to void transaction");
      }
      await fetchSales();
      // Voiding takes the bill out of the day's takings and puts its stock
      // back, neither of which this list shows.
      refreshServerData();
    } catch (err) {
      say("Could not void this sale", errorMessage(err, "Something went wrong."), "danger");
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
    // Sum the tenders, not the mode. A split bill has payment_mode "split",
    // so matching on the mode dropped it from every bucket: its money showed
    // in gross sales and nowhere in the breakdown, and its cash never reached
    // the drawer figure the register is counted against at close.
    // payment_breakdown is already derived from the sale's payment rows.
    const cashTotal = sales.reduce((sum, s) => sum + (s.payment_breakdown?.cash ?? 0), 0);
    const upiTotal = sales.reduce((sum, s) => sum + (s.payment_breakdown?.upi ?? 0), 0);
    const cardTotal = sales.reduce((sum, s) => sum + (s.payment_breakdown?.card ?? 0), 0);
    const khataTotal = sales.reduce(
      (sum, s) => sum + (s.payment_breakdown?.khata_due ?? 0),
      0,
    );

    // What is still owed on these bills: money counted in gross sales that
    // has not arrived. It is the khata bucket by definition, so it is named
    // rather than summed a second way that could disagree with it.
    const dueTotal = khataTotal;

    return {
      totalRev,
      count,
      aov,
      cashTotal,
      upiTotal,
      cardTotal,
      khataTotal,
      dueTotal,
    };
  }, [sales]);

  /** The mix, as coloured segments. Built from the tender buckets so a split
   *  bill contributes to each method it actually used. */
  const mixSegments: MixSegment[] = useMemo(
    () =>
      [
        { key: "CASH", label: "Cash", amount: metrics.cashTotal, color: "var(--success)" },
        { key: "UPI", label: "UPI", amount: metrics.upiTotal, color: "var(--primary-bright)" },
        { key: "CARD", label: "Card", amount: metrics.cardTotal, color: "var(--primary)" },
        { key: "KHATA", label: "Khata", amount: metrics.khataTotal, color: "var(--warning)" },
      ].filter((segment) => segment.amount > 0),
    [metrics],
  );

  /** How many bills each payment slice would return. A chip that says
   *  "Cash 12" answers the question as well as filtering by it. */
  const paymentCounts = useMemo(() => {
    const tally: Record<string, number> = { all: sales.length };
    for (const chip of PAYMENT_CHIPS) {
      if (chip.key === "all") continue;
      tally[chip.key] = sales.filter((sale) => sale.payment_mode === chip.key).length;
    }
    return tally;
  }, [sales]);

  // Day close calculations
  // The drawer is reconciled against the server's tender total. `metrics` is
  // computed from the sales list on screen, which is filtered and paged, so it
  // would quietly under-count the day.
  const drawerCash = registerCash ?? 0;
  const expectedCashInDrawer = expectedInTill(registerClose.openingFloat, drawerCash);
  const isDayClosed = registerClose.closedAt !== null;
  const cashDifference =
    registerCash === null ? null : discrepancy(registerClose, drawerCash, floatEntered);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-5">
      {/* One control row: which view on the left, how to narrow it on the
          right. The switch used to hold a row of its own doing nothing but
          taking height, and the search sat on a third row below that - three
          bands of chrome before the first bill.

          It renders in both views on purpose. Folding it into the History
          block would take the switch away the moment you used it. */}
      {/* relative z-20 is load-bearing. animate-fade-in-up animates a
          transform, which makes this card a stacking context - so the date
          menu inside it cannot paint above the figures and the table that
          follow it in the DOM, and was being drawn underneath them. */}
      <div className="relative z-20 rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] p-3 shadow-sm animate-fade-in-up">
        <div className="flex flex-wrap items-center gap-2.5">
          <div className="flex shrink-0 items-center gap-1 rounded-xl border border-[var(--border-soft)] bg-[var(--bg-base)] p-1">
            {[
              { key: "history" as const, label: "Sales History" },
              { key: "dayclose" as const, label: "Day Close" },
            ].map((tab) => (
              <button
                key={tab.key}
                type="button"
                onClick={() => setActiveView(tab.key)}
                aria-pressed={activeView === tab.key}
                className={`focus-ring cursor-pointer whitespace-nowrap rounded-lg px-3.5 py-1.5 text-xs font-bold transition-colors ${
                  activeView === tab.key
                    ? "border border-[var(--primary)]/25 bg-[var(--primary)]/12 text-[var(--primary-dark)] shadow-sm"
                    : "border border-transparent text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {activeView === "history" && (
            <>
              <div className="relative min-w-[200px] flex-1 sm:max-w-[300px]">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--text-tertiary)]" />
                <input
                  type="text"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Invoice # or customer"
                  aria-label="Search sales"
                  className="w-full rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface-muted)] py-2 pl-9 pr-8 text-[12.5px] font-medium text-[var(--text-primary)] outline-none transition-colors placeholder:text-[var(--text-tertiary)] focus:border-[var(--primary)]"
                />
                {search && (
                  <button
                    type="button"
                    onClick={() => setSearch("")}
                    aria-label="Clear search"
                    className="focus-ring absolute right-2 top-1/2 grid h-6 w-6 -translate-y-1/2 cursor-pointer place-items-center rounded-full text-[var(--text-tertiary)] transition-colors hover:bg-[var(--bg-base)] hover:text-[var(--text-primary)]"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                )}
              </div>

              <DateRangePicker
                value={rangeKey}
                custom={customRange}
                today={shopToday}
                onChange={(key, next) => {
                  setRangeKey(key);
                  setCustomRange(next);
                }}
                className="w-[180px] shrink-0"
              />

              <span className="ml-auto shrink-0 text-[11.5px] font-semibold text-[var(--text-tertiary)]">
                {isLoading
                  ? "Loading..."
                  : `${filteredSales.length} of ${sales.length}${
                      // Said out loud: the filters above only search what has
                      // been loaded, so a plain count would read as the whole
                      // period and a search for an older bill look empty.
                      nextCursor ? " loaded" : ""
                    } in ${range.label.toLowerCase()}`}
              </span>

              {nextCursor && !isLoading && (
                <button
                  type="button"
                  onClick={() => void loadMoreSales()}
                  disabled={loadingMore}
                  className="focus-ring shrink-0 cursor-pointer rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3 py-1.5 text-[11.5px] font-extrabold text-[var(--primary-dark)] transition-colors duration-200 hover:bg-[var(--primary)]/20 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {loadingMore ? "Loading…" : "Load older bills"}
                </button>
              )}
            </>
          )}
        </div>

        {/* Kept on a line of its own, below a rule. Slices are scanned as a
            set - reading across five counts to compare them is the whole
            point - and mixed in beside a search box they stop reading as one. */}
        {activeView === "history" && (
          <div className="no-scrollbar mt-2.5 flex items-center gap-2 overflow-x-auto border-t border-[var(--border-soft)] pt-2.5">
            {PAYMENT_CHIPS.map((chip) => {
              const active = paymentFilter === chip.key;
              const empty = chip.key !== "all" && (paymentCounts[chip.key] ?? 0) === 0;
              return (
                <button
                  key={chip.key}
                  type="button"
                  onClick={() => setPaymentFilter(chip.key)}
                  aria-pressed={active}
                  disabled={empty && !active}
                  className={`focus-ring shrink-0 whitespace-nowrap rounded-full border px-3.5 py-2 text-[11.5px] font-bold transition-colors ${
                    empty && !active
                      ? "cursor-not-allowed border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-tertiary)] opacity-60"
                      : active
                        ? "cursor-pointer border-[var(--primary)] bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                        : "cursor-pointer border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] hover:border-[var(--border)] hover:text-[var(--text-primary)]"
                  }`}
                >
                  {chip.label} <span className="tnum font-mono">{paymentCounts[chip.key] ?? 0}</span>
                </button>
              );
            })}

            {(search.trim() !== "" || paymentFilter !== "all") && (
              <button
                type="button"
                onClick={() => {
                  setSearch("");
                  setPaymentFilter("all");
                }}
                className="focus-ring ml-auto shrink-0 cursor-pointer whitespace-nowrap rounded-full border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)]"
              >
                Clear filters
              </button>
            )}
          </div>
        )}
      </div>

      {activeView === "history" ? (
        <div className="flex min-h-0 flex-1 flex-col gap-5">
          {/* One row: the figures on the left, the mix on the right. Three
              tall cards cost a third of the screen on a page whose job is
              showing bills. Each figure is a labelled unit with a rule
              between, so four numbers read as four things. */}
          <div className="flex items-center gap-4 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm animate-fade-in-up">
            <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
              {[
                {
                  label: "bills",
                  value: String(metrics.count),
                  detail: range.label.toLowerCase(),
                  tone: "text-[var(--text-primary)]",
                },
                {
                  label: "gross sales",
                  value: formatCurrency(metrics.totalRev),
                  detail: "before returns",
                  tone: "text-[var(--text-primary)]",
                },
                {
                  label: "average bill",
                  value: formatCurrency(metrics.aov),
                  detail: "per checkout",
                  tone: "text-[var(--text-primary)]",
                },
                {
                  label: "still owed",
                  value: formatCurrency(metrics.dueTotal),
                  detail: metrics.dueTotal > 0 ? "on khata" : "everyone settled",
                  tone:
                    metrics.dueTotal > 0
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
                    <span
                      className={`tnum font-mono text-[17px] font-bold leading-tight ${stat.tone}`}
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

            {mixSegments.length > 0 && (
              <div className="hidden min-w-[220px] max-w-[380px] shrink-0 lg:block">
                <MixBar
                  segments={mixSegments}
                  format={(amount) => formatCurrency(amount)}
                  ariaLabel={`How the money arrived: ${mixSegments
                    .map((segment) => `${segment.label} ${formatCurrency(segment.amount)}`)
                    .join(", ")}.`}
                />
              </div>
            )}
          </div>

          {/* Only the rows move. The figures above and the column headings
              stay put, so you never lose track of which column you are
              reading halfway down a long day. */}
          <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] shadow-sm">
            <div className="min-h-0 flex-1 overflow-auto">
              <table className="w-full text-left border-collapse text-xs">
                <thead className="sticky top-0 z-10">
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
                        {sales.length === 0
                          ? "No sales yet. Every bill rung up at the counter lands here."
                          : "No sales match this search."}
                      </td>
                    </tr>
                  ) : (
                    filteredSales.map((sale) => (
                      <tr key={sale.id} className="hover:bg-bg-base transition-colors">
                        <td className="py-3 px-4 font-mono font-semibold text-[var(--text-primary)]">
                          {sale.receipt_number}
                          {/* The return is its own document and leaves the sale
                              untouched, so without this a fully returned bill
                              reads exactly like one that still stands. */}
                          {(refundedBySale[sale.id] ?? 0) > 0 && (
                            <span
                              className={`mt-1 block w-fit rounded-full px-2 py-0.5 font-sans text-[10px] font-bold ${
                                (refundedBySale[sale.id] ?? 0) >= sale.total_amount
                                  ? "bg-[var(--error)]/10 text-[var(--error-strong)]"
                                  : "bg-[var(--warning)]/10 text-[var(--warning-strong)]"
                              }`}
                            >
                              {(refundedBySale[sale.id] ?? 0) >= sale.total_amount
                                ? "Fully returned"
                                : `Returned ${formatCurrency(refundedBySale[sale.id] ?? 0)}`}
                            </span>
                          )}
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

                            {(() => {
                              const refunded = refundedBySale[sale.id] ?? 0;
                              const fullyReturned = refunded >= sale.total_amount;

                              if (sale.status === "voided") {
                                return (
                                  <span className="rounded bg-[var(--error)]/15 px-2 py-0.5 text-[10px] font-bold uppercase text-[var(--error-strong)]">
                                    Voided
                                  </span>
                                );
                              }

                              return (
                                <>
                                  {/* Return takes back individual lines and leaves
                                      the bill intact; Void cancels the whole sale.
                                      Neither is offered once the bill has already
                                      been sent back — see below. */}
                                  {!fullyReturned && (
                                    <button
                                      onClick={() => setReturningSaleId(sale.id)}
                                      className="inline-flex items-center gap-1 rounded-lg border border-[var(--warning)]/20 bg-[var(--warning)]/10 px-2 py-1 text-[11px] text-[var(--warning-strong)] transition-colors hover:bg-[var(--warning)]/20"
                                    >
                                      <Undo2 className="h-3 w-3" />
                                      <span>{refunded > 0 ? "Return more" : "Return"}</span>
                                    </button>
                                  )}

                                  {/* Void restocks every line of the sale and
                                      reverses the money, and the server does not
                                      check whether a return already did some of
                                      that. Offering it after a return invites
                                      double-restocking the same goods. */}
                                  {refunded > 0 ? (
                                    <span
                                      className="rounded bg-[var(--bg-soft)] px-2 py-0.5 text-[10px] font-bold uppercase text-[var(--text-tertiary)]"
                                      title="This bill has already been returned. Voiding it as well would put the same stock back twice."
                                    >
                                      {fullyReturned ? "Returned" : "Part returned"}
                                    </span>
                                  ) : (
                                    <button
                                      onClick={() => handleVoidSale(sale.id)}
                                      className="inline-flex items-center gap-1 rounded-lg border border-[var(--error)]/20 bg-[var(--error)]/10 px-2 py-1 text-[11px] text-[var(--error-strong)] transition-colors hover:bg-[var(--error)]/20"
                                    >
                                      <RotateCcw className="h-3 w-3" />
                                      <span>Void</span>
                                    </button>
                                  )}
                                </>
                              );
                            })()}
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      ) : (
        /* ========================================================= */
        /* DAY CLOSE REGISTER AUDIT                                  */
        /* ========================================================= */
        <div className="mx-auto w-full max-w-2xl space-y-6 overflow-y-auto rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] p-6 shadow-sm">
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

          {/* What the drawer should hold. The float is asked for rather than
              assumed: it used to be hardcoded at 5,000, which made every
              over/short reading a comparison against money nobody counted. */}
          <div className="rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface-muted)] p-4">
            <label className="block">
              <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
                Opening cash float
              </span>
              <span className="mt-1 block text-[11px] font-medium text-[var(--text-tertiary)]">
                What was in the drawer before trading started.
              </span>
              <input
                type="text"
                inputMode="decimal"
                autoComplete="off"
                disabled={isDayClosed}
                value={floatText}
                placeholder="0.00"
                onChange={(e) => {
                  const text = e.target.value;
                  // Anything that is not money is ignored outright. Accepting
                  // it would coerce a typo to zero and quietly invent a float.
                  if (!isMoneyInput(text)) return;
                  setFloatText(text);
                  setRegisterClose({
                    ...registerClose,
                    openingFloat: moneyValue(text),
                    floatEntered: text !== "",
                  });
                }}
                onBlur={() => void persistClose(registerClose)}
                className="tnum mt-2 w-full rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2.5 font-mono text-sm font-bold text-[var(--text-primary)] outline-none focus:border-[var(--primary)] disabled:opacity-60"
              />
            </label>

            <dl className="mt-3.5 space-y-1.5 border-t border-[var(--border-soft)] pt-3.5">
              <div className="flex justify-between text-xs">
                <dt className="text-[var(--text-secondary)]">Cash sales taken</dt>
                <dd className="tnum font-mono font-bold text-[var(--success-strong)]">
                  +{formatCurrency(drawerCash)}
                </dd>
              </div>
              <div className="flex justify-between text-xs">
                <dt className="text-[var(--text-tertiary)]">UPI / QR (not in the drawer)</dt>
                <dd className="tnum font-mono font-semibold text-[var(--text-tertiary)]">
                  {formatCurrency(metrics.upiTotal)}
                </dd>
              </div>
              <div className="flex justify-between text-xs">
                <dt className="text-[var(--text-tertiary)]">Card (not in the drawer)</dt>
                <dd className="tnum font-mono font-semibold text-[var(--text-tertiary)]">
                  {formatCurrency(metrics.cardTotal)}
                </dd>
              </div>
              <div className="flex justify-between border-t border-[var(--border-soft)] pt-2.5 text-sm font-extrabold text-[var(--text-primary)]">
                <dt>Cash expected in till</dt>
                <dd className="tnum font-mono">{formatCurrency(expectedCashInDrawer)}</dd>
              </div>
            </dl>
          </div>

          <div className="mt-4 space-y-4">
            <label className="block">
              <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
                Cash counted in the drawer
              </span>
              <input
                type="text"
                inputMode="decimal"
                autoComplete="off"
                disabled={isDayClosed}
                value={countedText}
                placeholder="0.00"
                onChange={(e) => {
                  const text = e.target.value;
                  if (!isMoneyInput(text)) return;
                  setCountedText(text);
                  setRegisterClose({ ...registerClose, countedCash: moneyValue(text) });
                }}
                onBlur={() => void persistClose(registerClose)}
                className="tnum mt-2 w-full rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2.5 font-mono text-sm font-bold text-[var(--text-primary)] outline-none focus:border-[var(--primary)] disabled:opacity-60"
              />
            </label>

            {/* This figure can get a cashier accused of a shortfall, so it is
                withheld until both halves of it were actually entered. */}
            {cashDifference === null ? (
              <p className="rounded-[12px] border border-dashed border-[var(--border)] bg-[var(--bg-base)] px-4 py-3 text-[12px] font-semibold text-[var(--text-tertiary)]">
                Enter the opening float to see whether the till is over or short.
              </p>
            ) : (
              <div
                className={`flex items-center justify-between rounded-[12px] border px-4 py-3 ${
                  cashDifference === 0
                    ? "border-[var(--success)]/40 bg-[var(--success)]/10"
                    : cashDifference > 0
                      ? "border-[var(--warning)]/40 bg-[var(--warning)]/10"
                      : "border-[var(--error)]/40 bg-[var(--error)]/10"
                }`}
              >
                <span
                  className={`text-xs font-bold ${
                    cashDifference === 0
                      ? "text-[var(--success-strong)]"
                      : cashDifference > 0
                        ? "text-[var(--warning-strong)]"
                        : "text-[var(--error-strong)]"
                  }`}
                >
                  {cashDifference === 0
                    ? "Balanced"
                    : cashDifference > 0
                      ? "Cash over"
                      : "Cash short"}
                </span>
                <span
                  className={`tnum font-mono text-lg font-bold ${
                    cashDifference === 0
                      ? "text-[var(--success-strong)]"
                      : cashDifference > 0
                        ? "text-[var(--warning-strong)]"
                        : "text-[var(--error-strong)]"
                  }`}
                >
                  {cashDifference > 0 ? "+" : ""}
                  {formatCurrency(cashDifference)}
                </span>
              </div>
            )}

            <label className="block">
              <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
                Notes
              </span>
              <textarea
                rows={3}
                disabled={isDayClosed}
                value={registerClose.notes}
                onChange={(e) =>
                  setRegisterClose({ ...registerClose, notes: e.target.value })
                }
                onBlur={() => void persistClose(registerClose)}
                placeholder="Anything worth explaining about the count, a handover, or a refund."
                className="mt-2 w-full rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2.5 text-xs text-[var(--text-primary)] outline-none placeholder:text-[var(--text-tertiary)] focus:border-[var(--primary)] disabled:opacity-60"
              />
            </label>

            {isDayClosed ? (
              <div className="rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] px-4 py-3">
                <p className="m-0 text-[12px] font-bold text-[var(--text-primary)]">
                  Day closed at{" "}
                  {new Date(registerClose.closedAt as string).toLocaleTimeString("en-IN", {
                    timeStyle: "short",
                  })}
                </p>
                {registerClose.closedByName && (
                  <p className="m-0 mt-0.5 text-[11px] font-medium text-[var(--text-tertiary)]">
                    Counted by {registerClose.closedByName}
                  </p>
                )}
              </div>
            ) : (
              <button
                type="button"
                disabled={!floatEntered || isSavingClose}
                onClick={() => void persistClose(registerClose, true)}
                className="focus-ring w-full cursor-pointer rounded-[12px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 py-3 text-xs font-bold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20 disabled:cursor-not-allowed disabled:opacity-50"
              >
                {floatEntered ? "Lock the day close" : "Enter the opening float first"}
              </button>
            )}

            {closeError && (
              <p
                role="alert"
                className="m-0 rounded-[10px] border border-[var(--error)]/40 bg-[var(--error)]/10 px-3 py-2 text-[11.5px] font-semibold text-[var(--error-strong)]"
              >
                {closeError}
              </p>
            )}

            <p className="m-0 text-[11px] font-medium text-[var(--text-tertiary)]">
              {isSavingClose
                ? "Saving..."
                : "Saved to your shop's records, and visible on every device."}
            </p>
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
          shopName={shopName}
          shopGstin={shopGstin}
          // Passed here too. Reprinting a bill from history used the receipt
          // component's own placeholder address, phone and GSTIN, so the same
          // fake details reached paper by a second route.
          shopAddress={shopAddress}
          shopPhone={shopPhone}
          regionCode={regionCode}
          shopLogo={shopLogo}
          brandColor={brandColor}
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
