import Link from "next/link";
import { ShoppingCart, Package, AlertCircle, TrendingUp, TrendingDown, Receipt } from "lucide-react";
import { AdminShell } from "@/components/admin-shell";
import { EmptyState } from "@/components/empty-state";
import { getDashboardSnapshot, getSession, getSales, resolveActiveShop } from "@/lib/admin-api";
import { formatCurrency } from "@/lib/formatters";

export default async function HomePage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);
  const dashboardSnapshot = activeShop ? await getDashboardSnapshot(activeShop.shop.id) : null;
  const recentSales = activeShop ? await getSales(activeShop.shop.id) : [];

  const totalOutstanding = Number(dashboardSnapshot?.total_outstanding_balance ?? 0);
  // Lifetime, used by the "TOTAL SALES" card lower down where that is what the
  // label promises.
  const grossRevenue = Number(dashboardSnapshot?.gross_revenue ?? 0);
  // Today's, for the hero. These used to be the same value, which meant the
  // first number anyone saw — including in a demo — was the shop's entire
  // trading history labelled as one day.
  const todayRevenue = Number(dashboardSnapshot?.today_gross_revenue ?? 0);
  const todaySalesCount = dashboardSnapshot?.today_sales_count ?? 0;
  const stockValue = Number(dashboardSnapshot?.projected_sell_value ?? 0);

  const currencyCode = activeShop?.shop.currency_code ?? "INR";

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="overview"
      title="Dashboard"
      subtitle="Today's takings, key stats, recent sales, and low stock warnings."
    >
      {!activeShop ? (
        <EmptyState
          title="No shop membership found"
          body="This account is signed in, but there is no active shop membership yet. Please add a shop membership in Business Hub before using the curated workspace."
        />
      ) : (
        <div className="space-y-6">
          {/* Today's takings hero matching HeroMetricCard */}
          <div className="bg-gradient-to-br from-[var(--primary-light)] to-[var(--primary-hover)] text-white rounded-[24px] p-6 sm:p-8 shadow-md animate-fade-in-up">
            <span className="text-[10px] font-extrabold uppercase tracking-[0.12em] text-[var(--info)]">
              Today&apos;s Sales
            </span>
            <h2 className="text-3xl sm:text-4xl font-[900] tracking-tight mt-1">
              {formatCurrency(todayRevenue, currencyCode)}
            </h2>
            <div className="flex items-center gap-3 mt-4 text-xs font-bold text-[var(--info)]">
              <span>{todaySalesCount} sales today</span>
              {totalOutstanding > 0 && (
                <>
                  <span>•</span>
                  <span className="bg-white/15 px-2.5 py-0.5 rounded-full">
                    {formatCurrency(totalOutstanding, currencyCode)} outstanding due
                  </span>
                </>
              )}
            </div>
          </div>

          {/* Key Stats Grid matching _StatCard / Row of metrics */}
          <div className="grid gap-4 grid-cols-2 lg:grid-cols-4">
            {/* Stat: Items */}
            <Link
              href="/inventory"
              className="bg-[var(--surface)] border border-[var(--border-soft)] hover:border-[var(--primary)] hover:shadow-md rounded-[20px] p-5 text-left transition-all group animate-fade-in-up delay-1 hover-lift"
            >
              <div className="w-10 h-10 rounded-xl bg-[var(--primary)]/10 text-[var(--primary-hover)] flex items-center justify-center transition-colors group-hover:bg-[var(--primary)]/20">
                <Package className="w-5 h-5" />
              </div>
              <span className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mt-3.5">
                ITEMS
              </span>
              <h3 className="text-xl font-black text-[var(--text-primary)] mt-1">
                {dashboardSnapshot?.inventory_items_count ?? 0}
              </h3>
              <span className="block text-[11px] font-semibold text-[var(--text-secondary)] mt-0.5">
                {dashboardSnapshot?.active_inventory_items_count ?? 0} live items
              </span>
            </Link>

            {/* Stat: Low Stock */}
            <Link
              href="/inventory"
              className="bg-[var(--surface)] border border-[var(--border-soft)] hover:border-[var(--primary)] hover:shadow-md rounded-[20px] p-5 text-left transition-all group animate-fade-in-up delay-2 hover-lift"
            >
              <div className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors ${
                (dashboardSnapshot?.low_stock_items_count ?? 0) > 0
                  ? "bg-[var(--error)]/10 text-[var(--error-strong)] group-hover:bg-[var(--error)]/15"
                  : "bg-[var(--success)]/10 text-[var(--success-strong)] group-hover:bg-[var(--success)]/15"
              }`}>
                <AlertCircle className="w-5 h-5" />
              </div>
              <span className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mt-3.5">
                LOW STOCK
              </span>
              <h3 className="text-xl font-black text-[var(--text-primary)] mt-1">
                {dashboardSnapshot?.low_stock_items_count ?? 0}
              </h3>
              <span className={`block text-[11px] font-semibold mt-0.5 ${
                (dashboardSnapshot?.low_stock_items_count ?? 0) > 0 ? "text-[var(--error-strong)]" : "text-[var(--success-strong)]"
              }`}>
                {(dashboardSnapshot?.low_stock_items_count ?? 0) > 0 ? "Needs restock" : "All good"}
              </span>
            </Link>

            {/* Stat: Total Sales */}
            <Link
              href="/sales"
              className="bg-[var(--surface)] border border-[var(--border-soft)] hover:border-[var(--primary)] hover:shadow-md rounded-[20px] p-5 text-left transition-all group animate-fade-in-up delay-3 hover-lift"
            >
              <div className="w-10 h-10 rounded-xl bg-violet-50 text-violet-600 flex items-center justify-center transition-colors group-hover:bg-violet-100">
                <TrendingUp className="w-5 h-5" />
              </div>
              <span className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mt-3.5">
                TOTAL SALES
              </span>
              <h3 className="text-xl font-black text-[var(--text-primary)] mt-1">
                {formatCurrency(grossRevenue, currencyCode)}
              </h3>
              <span className="block text-[11px] font-semibold text-[var(--text-secondary)] mt-0.5">
                View detailed history
              </span>
            </Link>

            {/* Stat: Stock Value */}
            <Link
              href="/inventory"
              className="bg-[var(--surface)] border border-[var(--border-soft)] hover:border-[var(--primary)] hover:shadow-md rounded-[20px] p-5 text-left transition-all group animate-fade-in-up delay-4 hover-lift"
            >
              <div className="w-10 h-10 rounded-xl bg-[var(--success)]/10 text-[var(--success-strong)] flex items-center justify-center transition-colors group-hover:bg-[var(--success)]/15">
                <TrendingDown className="w-5 h-5" />
              </div>
              <span className="block text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-tertiary)] mt-3.5">
                STOCK VALUE
              </span>
              <h3 className="text-xl font-black text-[var(--text-primary)] mt-1">
                {formatCurrency(stockValue, currencyCode)}
              </h3>
              <span className="block text-[11px] font-semibold text-[var(--text-secondary)] mt-0.5">
                At selling price
              </span>
            </Link>
          </div>

          {/* Primary Action: Start New Sale */}
          <Link
            href="/pos"
            className="w-full flex items-center justify-center gap-2.5 py-4 px-6 bg-gradient-to-r from-[var(--primary-light)] to-[var(--primary-hover)] hover:from-[var(--primary)] hover:to-[var(--primary-dark)] text-white rounded-[20px] text-sm font-extrabold shadow-md shadow-[var(--primary)]/20 transition-all hover:scale-[1.005] animate-fade-in-up delay-5 hover-lift"
          >
            <ShoppingCart className="w-5 h-5" />
            <span>START NEW SALE</span>
          </Link>

          {/* 2-Column Grid: Recent Sales & Low Stock watch lists */}
          <div className="grid gap-6 lg:grid-cols-[1.2fr_0.8fr]">
            
            {/* Column 1: Recent Sales */}
            <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-[24px] p-5 sm:p-6 shadow-sm animate-fade-in-up delay-6">
              <div className="flex items-center justify-between gap-4 mb-4">
                <h3 className="text-base font-extrabold text-[var(--text-primary)]">
                  Recent sales
                </h3>
                {recentSales.length > 0 && (
                  <Link
                    href="/sales"
                    className="text-xs font-bold text-[var(--primary)] hover:underline animate-fade-in"
                  >
                    View all
                  </Link>
                )}
              </div>

              {recentSales.length === 0 ? (
                <div className="py-12 text-center text-[var(--text-tertiary)] text-xs font-bold border border-dashed border-[var(--border-soft)] rounded-2xl bg-[var(--bg-base)]">
                  No sales yet. Tap Start New Sale to begin.
                </div>
              ) : (
                <div className="space-y-3.5">
                  {recentSales.slice(0, 5).map((sale, index) => (
                    <div
                      key={sale.id}
                      className="flex items-center justify-between p-3.5 bg-[var(--bg-base)] border border-[var(--border-soft)] rounded-2xl hover-lift"
                      style={{ animationDelay: `${240 + index * 40}ms` }}
                    >
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-[var(--primary)]/10 text-[var(--primary-hover)] flex items-center justify-center shrink-0">
                          <Receipt className="w-4 h-4" />
                        </div>
                        <div>
                          <h4 className="text-xs font-extrabold text-[var(--text-primary)]">
                            {sale.customer_name || "Walk-in Guest"}
                          </h4>
                          <span className="block text-[10px] font-bold text-[var(--text-secondary)] mt-0.5">
                            {sale.payment_mode} • {new Date(sale.sale_date).toLocaleDateString()}
                          </span>
                        </div>
                      </div>
                      <div className="text-right">
                        <span className="block text-sm font-black text-[var(--text-primary)]">
                          {formatCurrency(Number(sale.total_amount), currencyCode)}
                        </span>
                        {Number(sale.amount_due) > 0 && (
                          <span className="block text-[10px] font-extrabold text-[var(--warning-strong)] mt-0.5">
                            Due {formatCurrency(Number(sale.amount_due), currencyCode)}
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Column 2: Low Stock */}
            <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-[24px] p-5 sm:p-6 shadow-sm animate-fade-in-up delay-7">
              <div className="flex items-center justify-between gap-4 mb-4">
                <h3 className="text-base font-extrabold text-[var(--text-primary)]">
                  Low stock watch
                </h3>
              </div>

              {!dashboardSnapshot?.low_stock_preview || dashboardSnapshot.low_stock_preview.length === 0 ? (
                <div className="py-12 text-center text-[var(--text-tertiary)] text-xs font-bold border border-dashed border-[var(--border-soft)] rounded-2xl bg-[var(--bg-base)]">
                  No urgent low-stock items.
                </div>
              ) : (
                <div className="space-y-3.5">
                  {dashboardSnapshot.low_stock_preview.slice(0, 5).map((item, index) => (
                    <div
                      key={item.id}
                      className="flex items-center justify-between p-3.5 bg-[var(--bg-base)] border border-[var(--border-soft)] rounded-2xl hover-lift"
                      style={{ animationDelay: `${280 + index * 40}ms` }}
                    >
                      <div>
                        <h4 className="text-xs font-extrabold text-[var(--text-primary)]">
                          {item.item_name}
                        </h4>
                        <span className="block text-[10px] font-bold text-[var(--text-secondary)] mt-0.5">
                          {item.category || "Uncategorized"}
                        </span>
                      </div>
                      <span className="px-2.5 py-1 rounded-full text-[10px] font-extrabold bg-[var(--error)]/10 text-[var(--error-strong)] border border-[var(--error)]/30">
                        {item.stock_on_hand} left
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>

          </div>
        </div>
      )}
    </AdminShell>
  );
}
