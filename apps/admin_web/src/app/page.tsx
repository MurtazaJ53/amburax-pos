import Link from "next/link";
import {
  AlertCircle,
  ArrowUpRight,
  Banknote,
  MessageSquare,
  Package,
  Plus,
  Receipt,
  ShoppingCart,
  TrendingDown,
  TrendingUp,
} from "lucide-react";

import { AdminShell } from "@/components/admin-shell";
import { EmptyState } from "@/components/empty-state";
import { AttentionList } from "@/components/ui/attention-list";
import type { AttentionItem, AttentionSeverity } from "@/components/ui/attention-list";
import { Panel, PanelEmpty } from "@/components/ui/panel";
import { LowStockWatch } from "@/components/low-stock-watch";
import { TakingsPanel } from "@/components/takings-panel";
import { StatTile } from "@/components/ui/stat-tile";
import {
  getDashboardSnapshot,
  getSales,
  getSession,
  getWorkspacePulse,
  resolveActiveShop,
} from "@/lib/admin-api";
import { shopDateKey, summariseToday } from "@/lib/dashboard-metrics";
import { formatCurrency } from "@/lib/formatters";
import type { WorkspacePulseSnapshot } from "@/lib/types";

/** Segment colours for the payment mix, keyed by mode. */

function greetingFor(hour: number): string {
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good evening";
}

/** A workspace-pulse task, restated as a row in the attention queue. */
function toAttentionItem(
  task: WorkspacePulseSnapshot["tasks"][number],
  index: number,
): AttentionItem {
  const severity: AttentionSeverity =
    task.tone === "danger" || task.priority === "critical"
      ? "critical"
      : task.tone === "warning" || task.priority === "high"
        ? "warning"
        : "info";

  return {
    id: `${task.code}-${index}`,
    severity,
    title: task.title,
    body: task.body,
    cta: task.cta_label || "Open",
    href: task.route || "/",
  };
}

export default async function HomePage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);

  if (!activeShop) {
    return (
      <AdminShell
        session={session}
        activeShop={null}
        activeRoute="overview"
        title="Home"
        subtitle="Today's takings, key stats, recent sales, and low stock warnings."
      >
        <EmptyState
          title="No shop membership found"
          body="This account is signed in, but there is no active shop membership yet. Please add a shop membership in Business Hub before using the curated workspace."
        />
      </AdminShell>
    );
  }

  const shopId = activeShop.shop.id;
  const currencyCode = activeShop.shop.currency_code ?? "INR";
  const timeZone = activeShop.shop.timezone || "Asia/Kolkata";

  const dashboardSnapshot = await getDashboardSnapshot(shopId);

  // The shop's own calendar date, not the server's. A Kolkata shop billing at
  // 1 AM is still on yesterday's sheet for a UTC server.
  const todayKey = dashboardSnapshot.today_date ?? shopDateKey(new Date(), timeZone);

  const [recentSales, todaySales, pulse] = await Promise.all([
    getSales(shopId),
    getSales(shopId, { dateFrom: todayKey, dateTo: todayKey }),
    // The pulse feed drives the attention queue. If it is unavailable the
    // rest of the screen must still render, so we fall back to figures the
    // dashboard projection already gave us and say so in the panel.
    getWorkspacePulse(shopId).catch(() => null),
  ]);

  const today = summariseToday(todaySales, timeZone);

  const todaySalesCount = dashboardSnapshot.today_sales_count ?? 0;
  const grossRevenue = Number(dashboardSnapshot.gross_revenue ?? 0);
  const stockValue = Number(dashboardSnapshot.projected_sell_value ?? 0);
  const totalOutstanding = Number(dashboardSnapshot.total_outstanding_balance ?? 0);
  const lowStockCount = dashboardSnapshot.low_stock_items_count ?? 0;
  const outOfStockCount = dashboardSnapshot.out_of_stock_items_count ?? 0;
  const creditCustomers = dashboardSnapshot.active_credit_customers_count ?? 0;

  const localHour = Number(
    new Intl.DateTimeFormat("en-GB", { hour: "2-digit", hour12: false, timeZone }).format(
      new Date(),
    ),
  );


  // Prefer the real pulse feed. Where it is empty or unreachable, derive the
  // same kind of rows from the dashboard projection rather than showing a
  // blank panel.
  const pulseItems = (pulse?.tasks ?? []).map(toAttentionItem);
  const derivedItems: AttentionItem[] = [];

  if (pulseItems.length === 0) {
    if (outOfStockCount > 0) {
      derivedItems.push({
        id: "out-of-stock",
        severity: "critical",
        title: `${outOfStockCount} ${outOfStockCount === 1 ? "item is" : "items are"} out of stock`,
        body: "Nothing left on the shelf to sell.",
        cta: "Reorder",
        href: "/inventory",
      });
    }
    if (lowStockCount > outOfStockCount) {
      derivedItems.push({
        id: "low-stock",
        severity: "warning",
        title: `${lowStockCount - outOfStockCount} items below reorder level`,
        body: "Running low, but still sellable today.",
        cta: "Review",
        href: "/inventory",
      });
    }
    if (totalOutstanding > 0) {
      derivedItems.push({
        id: "khata",
        severity: "warning",
        title: `${formatCurrency(totalOutstanding, currencyCode)} owed on khata`,
        body: `${creditCustomers} ${creditCustomers === 1 ? "account" : "accounts"} carrying a balance.`,
        cta: "Collect",
        href: "/customers",
      });
    }
  }

  const attentionItems = pulseItems.length > 0 ? pulseItems : derivedItems;
  const criticalCount = attentionItems.filter((item) => item.severity === "critical").length;

  const needsSetup =
    (dashboardSnapshot.inventory_items_count ?? 0) === 0 ||
    (dashboardSnapshot.sales_count ?? 0) === 0;

  const setupSteps = [
    {
      done: true,
      label: "Shop details saved",
      body: `Trading as ${activeShop.shop.name} in ${currencyCode}.`,
      href: "/settings",
      cta: "Review details",
    },
    {
      done: (dashboardSnapshot.inventory_items_count ?? 0) > 0,
      label: "Add your items",
      body: "Import a spreadsheet, or add the first few by hand.",
      href: "/import",
      cta: "Import items",
    },
    {
      done: (dashboardSnapshot.sales_count ?? 0) > 0,
      label: "Ring up your first sale",
      body: "Takings, stock and khata figures fill in from here.",
      href: "/pos",
      cta: "Open POS",
    },
  ];
  const stepsDone = setupSteps.filter((step) => step.done).length;

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="overview"
      title="Home"
      subtitle="Today's takings, key stats, recent sales, and low stock warnings."
      headerVariant="bar"
      fitViewport
    >
      {/* min-h-0 all the way down, or the flex children below refuse to
          shrink and the page grows a scrollbar anyway. */}
      <div className="flex min-h-0 flex-1 flex-col gap-3.5">
        {/* Greeting, and the actions a counter reaches for */}
        <div className="flex flex-wrap items-end gap-3 animate-fade-in-up">
          <div>
            <h1 className="text-xl sm:text-2xl font-[900] tracking-tight text-[var(--text-primary)]">
              {greetingFor(localHour)}
              {session?.user?.full_name ? `, ${session.user.full_name.split(" ")[0]}` : ""}
            </h1>
            <p className="mt-0.5 text-[12.5px] font-medium text-[var(--text-secondary)]">
              {todaySalesCount > 0
                ? `${todaySalesCount} ${todaySalesCount === 1 ? "bill" : "bills"} today${
                    today.bestHour ? ` · busiest ${today.bestHour.label}` : ""
                  }`
                : "No bills yet today. Takings, key stats, recent sales and low stock warnings all appear here."}
            </p>
          </div>

          <div className="ml-auto flex flex-wrap gap-2">
            <Link
              href="/inventory"
              className="hover-lift focus-ring inline-flex items-center gap-1.5 rounded-[11px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2.5 text-[12.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
            >
              <Plus className="h-3.5 w-3.5" />
              Add item
            </Link>
            <Link
              href="/expenses"
              className="hover-lift focus-ring inline-flex items-center gap-1.5 rounded-[11px] border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2.5 text-[12.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
            >
              <TrendingDown className="h-3.5 w-3.5" />
              Record expense
            </Link>
            <Link
              href="/pos"
              className="hover-lift focus-ring inline-flex items-center gap-1.5 whitespace-nowrap rounded-[11px] border border-[var(--primary)]/30 bg-[var(--primary)]/14 px-4 py-2.5 text-[12.5px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/22"
            >
              <ShoppingCart className="h-4 w-4" />
              New sale
            </Link>
          </div>
        </div>

        {/* First run: what to do before any of the figures mean anything */}
        {needsSetup && (
          <section className="rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm animate-fade-in-up delay-1">
            <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
              Get {activeShop.shop.name} selling
            </span>
            <h2 className="mt-2 text-lg font-extrabold tracking-tight text-[var(--text-primary)]">
              {stepsDone} of {setupSteps.length} steps done
            </h2>

            <div className="mt-3.5 grid gap-3 sm:grid-cols-3">
              {setupSteps.map((step, index) => (
                <Link
                  key={step.label}
                  href={step.href}
                  className={`hover-lift focus-ring flex flex-col gap-1 rounded-[14px] border p-3.5 ${
                    step.done
                      ? "border-[var(--success)]/40 bg-[var(--success)]/10"
                      : "border-[var(--border-soft)] bg-[var(--bg-base)]"
                  }`}
                >
                  <span
                    className={`grid h-6 w-6 place-items-center rounded-lg font-mono text-[11px] font-bold ${
                      step.done
                        ? "bg-[var(--success)] text-white"
                        : "border border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)]"
                    }`}
                    aria-hidden="true"
                  >
                    {step.done ? "✓" : index + 1}
                  </span>
                  <span className="mt-1 text-[13px] font-extrabold text-[var(--text-primary)]">
                    {step.label}
                  </span>
                  <span className="text-[11.5px] font-medium text-[var(--text-secondary)]">
                    {step.body}
                  </span>
                  <span className="mt-1 inline-flex items-center gap-1 text-[11.5px] font-bold text-[var(--primary-hover)]">
                    {step.done ? "Review" : step.cta}
                    <ArrowUpRight className="h-3 w-3" />
                  </span>
                </Link>
              ))}
            </div>

            <div className="mt-3.5 flex items-center gap-3">
              <div className="h-1.5 flex-1 overflow-hidden rounded-full border border-[var(--border-soft)] bg-[var(--bg-base)]">
                <span
                  className="block h-full rounded-full bg-gradient-to-r from-[var(--primary-light)] to-[var(--primary-hover)]"
                  style={{ width: `${(stepsDone / setupSteps.length) * 100}%` }}
                />
              </div>
              <span className="tnum font-mono text-[11px] font-medium text-[var(--text-tertiary)]">
                {stepsDone}/{setupSteps.length}
              </span>
            </div>
          </section>
        )}

        {/* Takings for whichever period is asked for. The panel is a client
            component: the period is a question the shopkeeper changes, not a
            fact of the page, so it must not cost a full server render. */}
        <section className="grid gap-3.5 lg:grid-cols-[1.55fr_1fr]">
          <TakingsPanel currencyCode={currencyCode} timeZone={timeZone} />
          <div className="flex flex-col gap-3.5">
            <div className="flex flex-1 flex-col rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-4 shadow-sm animate-fade-in-up delay-2">
              <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
                Cash taken today
              </span>
              <p className="tnum mt-2 font-mono text-[23px] font-bold tracking-tight text-[var(--text-primary)]">
                {formatCurrency(today.cashTaken, currencyCode)}
              </p>
              <p className="mt-0.5 text-[11.5px] font-medium text-[var(--text-tertiary)]">
                {today.cashTaken > 0
                  ? "Notes and coins only — this is what the drawer should hold."
                  : "No cash bills yet today."}
              </p>
              <Link
                href="/day-book"
                className="focus-ring mt-auto pt-3 text-[11.5px] font-bold text-[var(--primary-hover)] hover:underline"
              >
                Open day book
              </Link>
            </div>

            <div className="flex flex-1 flex-col rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-4 shadow-sm animate-fade-in-up delay-3">
              <span className="font-mono text-[10px] font-bold uppercase tracking-[0.15em] text-[var(--text-tertiary)]">
                Owed to you (Khata)
              </span>
              <p
                className={`tnum mt-2 font-mono text-[23px] font-bold tracking-tight ${
                  totalOutstanding > 0
                    ? "text-[var(--warning-strong)]"
                    : "text-[var(--text-primary)]"
                }`}
              >
                {formatCurrency(totalOutstanding, currencyCode)}
              </p>
              <p className="mt-0.5 text-[11.5px] font-medium text-[var(--text-tertiary)]">
                {totalOutstanding > 0
                  ? `${creditCustomers} ${
                      creditCustomers === 1 ? "account" : "accounts"
                    } carrying a balance`
                  : "Everyone has settled up."}
              </p>
              {totalOutstanding > 0 && (
                <Link
                  href="/customers"
                  className="hover-lift focus-ring mt-auto inline-flex w-fit items-center gap-1.5 rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-base)] px-3 py-1.5 text-[11.5px] font-bold text-[var(--text-secondary)]"
                >
                  <MessageSquare className="h-3 w-3" />
                  Send reminders
                </Link>
              )}
            </div>
          </div>
        </section>

        {/* The four headline counts, each with something to judge it against */}
        <section className="grid grid-cols-2 gap-3.5 lg:grid-cols-4">
          <StatTile
            label="Items"
            value={String(dashboardSnapshot.inventory_items_count ?? 0)}
            note={`${dashboardSnapshot.active_inventory_items_count ?? 0} live · ${
              dashboardSnapshot.category_count ?? 0
            } categories`}
            href="/inventory"
            trailing={
              <span className="grid h-8 w-8 place-items-center rounded-[10px] bg-[var(--primary)]/10 text-[var(--primary-hover)]">
                <Package className="h-4 w-4" />
              </span>
            }
            className="animate-fade-in-up delay-2"
          />
          <StatTile
            label="Low stock"
            value={String(lowStockCount)}
            note={
              lowStockCount > 0
                ? `${outOfStockCount} out of stock · ${Math.max(
                    lowStockCount - outOfStockCount,
                    0,
                  )} below reorder`
                : "Every item is above its reorder level"
            }
            tone={lowStockCount > 0 ? "alert" : "neutral"}
            noteToneOverride={lowStockCount > 0 ? "alert" : "good"}
            href="/inventory"
            trailing={
              <span
                className={`grid h-8 w-8 place-items-center rounded-[10px] ${
                  lowStockCount > 0
                    ? "bg-[var(--error)]/10 text-[var(--error-strong)]"
                    : "bg-[var(--success)]/10 text-[var(--success-strong)]"
                }`}
              >
                <AlertCircle className="h-4 w-4" />
              </span>
            }
            className="animate-fade-in-up delay-3"
          />
          <StatTile
            label="Total sales"
            value={formatCurrency(grossRevenue, currencyCode)}
            note={`${dashboardSnapshot.sales_count ?? 0} bills all time`}
            href="/sales"
            trailing={
              <span className="grid h-8 w-8 place-items-center rounded-[10px] bg-[var(--info)]/10 text-[var(--info-strong)]">
                <TrendingUp className="h-4 w-4" />
              </span>
            }
            className="animate-fade-in-up delay-4"
          />
          <StatTile
            label="Stock value"
            value={formatCurrency(stockValue, currencyCode)}
            note="At selling price"
            href="/inventory"
            trailing={
              <span className="grid h-8 w-8 place-items-center rounded-[10px] bg-[var(--success)]/10 text-[var(--success-strong)]">
                <Banknote className="h-4 w-4" />
              </span>
            }
            className="animate-fade-in-up delay-5"
          />
        </section>

        {/* What just happened on the left, what is running out on the right,
            and what to act on underneath both.

            The page itself does not scroll: a shopkeeper checking one figure
            should not lose the takings off the top of the screen to reach an
            alert below it. Each list scrolls inside its own panel instead. */}
        <section className="grid min-h-0 flex-1 gap-3.5 lg:grid-cols-[1.1fr_1fr]">
          <Panel
            title="Recent sales"
            action={recentSales.length > 0 ? { label: "View all", href: "/sales" } : undefined}
            scrollBody
            className="min-h-0 animate-fade-in-up delay-5"
          >
            {recentSales.length === 0 ? (
              <PanelEmpty>No sales yet. Tap New sale to begin.</PanelEmpty>
            ) : (
              <ul className="m-0 flex list-none flex-col p-0">
                {recentSales.map((sale, index) => (
                  <li
                    key={sale.id}
                    className="animate-fade-in-up border-b border-[var(--border-soft)] last:border-b-0"
                    style={{ animationDelay: `${240 + index * 40}ms` }}
                  >
                    <Link
                      href="/sales"
                      className="focus-ring flex items-center gap-3 rounded-xl px-1 py-2.5 transition-colors hover:bg-[var(--bg-base)]"
                    >
                      <span className="grid h-8 w-8 flex-none place-items-center rounded-[9px] bg-[var(--primary)]/10 text-[var(--primary-hover)]">
                        <Receipt className="h-3.5 w-3.5" />
                      </span>
                      <span className="min-w-0">
                        <span className="block text-[12.5px] font-extrabold text-[var(--text-primary)]">
                          {sale.customer_name || "Walk-in guest"}
                        </span>
                        <span className="mt-0.5 block font-mono text-[10.5px] font-semibold text-[var(--text-tertiary)]">
                          {sale.payment_mode} &middot; {sale.item_count}{" "}
                          {sale.item_count === 1 ? "item" : "items"} &middot;{" "}
                          {new Date(sale.sale_date).toLocaleDateString("en-IN", {
                            day: "numeric",
                            month: "short",
                          })}
                        </span>
                      </span>
                      <span className="ml-auto flex-none text-right">
                        <b className="tnum block font-mono text-[13.5px] font-bold tracking-tight text-[var(--text-primary)]">
                          {formatCurrency(Number(sale.total_amount), currencyCode)}
                        </b>
                        {Number(sale.amount_due) > 0 ? (
                          <span className="mt-0.5 block text-[10px] font-bold text-[var(--warning-strong)]">
                            Due {formatCurrency(Number(sale.amount_due), currencyCode)}
                          </span>
                        ) : (
                          <span className="mt-0.5 block text-[10px] font-bold text-[var(--text-tertiary)]">
                            Paid
                          </span>
                        )}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </Panel>

          <LowStockWatch
            rows={dashboardSnapshot.low_stock_preview ?? []}
            totalCount={lowStockCount}
            className="min-h-0 animate-fade-in-up delay-6"
          />
        </section>

        <section className="flex min-h-0 flex-[0.8] flex-col">
          <Panel
            title="Needs attention"
            count={attentionItems.length}
            countTone={criticalCount > 0 ? "alert" : "warning"}
            scrollBody
            className="min-h-0 animate-fade-in-up delay-4"
          >
            {attentionItems.length === 0 ? (
              <PanelEmpty>
                {pulse === null
                  ? "Alerts are unavailable right now. Stock and khata figures above are still live."
                  : "Nothing needs you right now."}
              </PanelEmpty>
            ) : (
              <AttentionList items={attentionItems} />
            )}
          </Panel>
        </section>
      </div>
    </AdminShell>
  );
}
