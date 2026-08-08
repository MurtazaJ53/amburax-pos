import { getServerT } from "@/lib/i18n/server";
import { formatCurrency } from "@/lib/formatters";
import type { Expense } from "@/lib/types";

type ExpenseTableProps = {
  expenses: Expense[];
  currencyCode?: string;
};

export async function ExpenseTable({ expenses, currencyCode = "INR" }: ExpenseTableProps) {
  const t = await getServerT();
  return (
    <div className="panel-soft overflow-hidden rounded-[28px]">
      <div className="overflow-x-auto">
        <table className="min-w-full border-collapse">
          <thead>
            <tr className="border-b border-[var(--border-soft)] text-left text-xs uppercase tracking-[0.24em] text-[var(--text-muted)]">
              <th className="px-5 py-4 font-medium">{t("webCategory", "Category")}</th>
              <th className="px-5 py-4 font-medium">Description</th>
              <th className="px-5 py-4 font-medium">Method</th>
              <th className="px-5 py-4 font-medium">Date</th>
              <th className="px-5 py-4 font-medium">Amount</th>
              <th className="px-5 py-4 font-medium">Actor</th>
            </tr>
          </thead>
          <tbody>
            {expenses.length ? (
              expenses.map((expense) => (
                <tr key={expense.id} className="border-b border-[rgba(152,164,189,0.08)] align-top">
                  <td className="px-5 py-4">
                    <p className="text-base font-semibold">{expense.category}</p>
                    {expense.payment_reference ? (
                      <p className="mt-1 text-xs text-[var(--text-muted)]">
                        {expense.payment_reference}
                      </p>
                    ) : null}
                  </td>
                  <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                    <div className="max-w-[22rem] line-clamp-2">
                      {expense.description || "No extra note has been added."}
                    </div>
                  </td>
                  <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                    {expense.payment_method}
                  </td>
                  <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                    {expense.expense_date}
                  </td>
                  <td className="px-5 py-4 text-sm font-semibold text-[var(--warning)]">
                    {formatCurrency(Number(expense.amount || 0), currencyCode)}
                  </td>
                  <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                    {expense.actor_name || "System"}
                  </td>
                </tr>
              ))
            ) : (
              <tr>
                <td
                  colSpan={6}
                  className="px-5 py-10 text-center text-sm text-[var(--text-secondary)]"
                >
                  No expenses are available for this store yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
