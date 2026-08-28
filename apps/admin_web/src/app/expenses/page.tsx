import { PageLoadError } from "@/components/ui/page-load-error";
import { ExpensesManager } from "@/components/expenses-manager";
import { AdminShell } from "@/components/admin-shell";
import { getSession, resolveActiveShop, getExpenses, getExpenseSummary } from "@/lib/admin-api";
import type { Expense, ExpenseSummaryPayload } from "@/lib/types";




export const metadata = {
  title: "Shop Expenses Manager | Business Hub",
  description: "Track store expenses, utility bills, inventory costs, and miscellaneous cash outflows",
};

export default async function ExpensesPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);
  const shopId = activeShop?.shop.id || "";

  let expenses: Expense[] = [];
  let summary: ExpenseSummaryPayload = {
    total_entries: 0,
    total_amount: "0.00",
    unique_categories: 0,
    biggest_category: null,
  };
  let loadError: unknown = null;

  if (shopId) {
    try {
      const [resExpenses, resSummary] = await Promise.all([
        getExpenses(shopId),
        getExpenseSummary(shopId),
      ]);
      expenses = resExpenses;
      summary = resSummary;
    } catch (err) {
      loadError = err;
      console.error("ExpensesPage fetch error:", err);
    }
  }

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="expenses"
      title="Shop Expenses Manager"
      fitViewport
      subtitle="Track store expenses, utility bills, inventory costs, and miscellaneous cash outflows"
    >
      {!shopId ? (
        <div className="panel p-8 text-center text-[var(--text-secondary)]">
          <p className="font-semibold text-lg text-text-primary mb-2">No Active Shop</p>
          <p className="text-sm">Please select or create a shop first to view and manage expenses.</p>
        </div>
      ) : loadError ? (
        <PageLoadError error={loadError} subject="your expenses" />
      ) : (
        <ExpensesManager initialExpenses={expenses} initialSummary={summary} shopId={shopId} />
      )}
    </AdminShell>
  );
}
