import { getServerT } from "@/lib/i18n/server";
import { formatCurrency } from "@/lib/formatters";
import type { Customer } from "@/lib/types";

type CustomerTableProps = {
  customers: Customer[];
  currencyCode?: string;
};

export async function CustomerTable({ customers, currencyCode = "INR" }: CustomerTableProps) {
  const t = await getServerT();
  return (
    <div className="panel-soft overflow-hidden rounded-[28px]">
      <div className="overflow-x-auto">
        <table className="min-w-full border-collapse">
          <thead>
            <tr className="border-b border-[var(--border-soft)] text-left text-xs uppercase tracking-[0.24em] text-[var(--text-muted)]">
              <th className="px-5 py-4 font-medium">Customer</th>
              <th className="px-5 py-4 font-medium">Phone</th>
              <th className="px-5 py-4 font-medium">{t("webEmail", "Email")}</th>
              <th className="px-5 py-4 font-medium">Outstanding</th>
              <th className="px-5 py-4 font-medium">Lifetime spend</th>
              <th className="px-5 py-4 font-medium">Status</th>
            </tr>
          </thead>
          <tbody>
            {customers.length ? (
              customers.map((customer) => {
                const balance = Number(customer.balance || 0);
                const tone =
                  balance > 0
                    ? "text-[var(--warning)]"
                    : balance < 0
                      ? "text-[var(--success)]"
                      : "text-[var(--text-primary)]";

                return (
                  <tr key={customer.id} className="border-b border-[rgba(152,164,189,0.08)] align-top">
                    <td className="px-5 py-4">
                      <div className="max-w-[18rem]">
                        <p className="text-base font-semibold">{customer.name}</p>
                        <p className="mt-1 text-sm text-[var(--text-secondary)] line-clamp-2">
                          {customer.notes || "No note has been added for this customer yet."}
                        </p>
                      </div>
                    </td>
                    <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                      {customer.phone || "No phone"}
                    </td>
                    <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                      {customer.email || "No email"}
                    </td>
                    <td className={`px-5 py-4 text-sm font-semibold ${tone}`}>
                      {formatCurrency(balance, currencyCode)}
                    </td>
                    <td className="px-5 py-4 text-sm text-[var(--text-primary)]">
                      {formatCurrency(Number(customer.total_spent || 0), currencyCode)}
                    </td>
                    <td className="px-5 py-4">
                      <span className="rounded-full border border-[rgba(152,164,189,0.12)] bg-[rgba(13,18,28,0.8)] px-3 py-1 text-xs font-medium text-[var(--text-secondary)]">
                        {customer.status}
                      </span>
                    </td>
                  </tr>
                );
              })
            ) : (
              <tr>
                <td
                  colSpan={6}
                  className="px-5 py-10 text-center text-sm text-[var(--text-secondary)]"
                >
                  No customers are available for this store yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
