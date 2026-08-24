import { CustomersTabs } from "@/components/customers-tabs";
import { AdminShell } from "@/components/admin-shell";
import { getSession, resolveActiveShop, getCustomers, getCustomerSummary } from "@/lib/admin-api";
import type { Customer, CustomerSummaryPayload } from "@/lib/types";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



export const metadata = {
  title: "Customers & Khata Ledger | Business Hub",
  description: "Manage customer profiles, store credit, receivables, and payment reminders",
};

export default async function CustomersPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);
  const shopId = activeShop?.shop.id || "";

  let customers: Customer[] = [];
  let summary: CustomerSummaryPayload = {
    total_customers: 0,
    active_credit_customers: 0,
    total_outstanding_balance: "0.00",
    total_lifetime_spend: null,
  };
  let errorMsg = "";

  if (shopId) {
    try {
      const [resCustomers, resSummary] = await Promise.all([
        getCustomers(shopId),
        getCustomerSummary(shopId),
      ]);
      customers = resCustomers;
      summary = resSummary;
    } catch (err) {
      errorMsg = errorMessage(err, "Failed to load customers data from backend");
      console.error("CustomersPage fetch error:", err);
    }
  }

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="customers"
      fitViewport
      title="Customer CRM & Udhaar Khata"
      subtitle="Store credit ledger, balance reminders, customer loyalty, and repayment logging"
    >
      {!shopId ? (
        <div className="panel p-8 text-center text-[var(--text-secondary)]">
          <p className="font-semibold text-lg text-text-primary mb-2">No Active Shop</p>
          <p className="text-sm">Please select or create a shop first to view and manage customers.</p>
        </div>
      ) : errorMsg ? (
        <div className="panel p-8 border-[var(--error)]/20 bg-[var(--error)]/5 rounded-xl">
          <p className="text-[var(--error)] font-semibold text-lg mb-2">Backend Connection Error</p>
          <p className="text-sm text-[var(--text-secondary)] mb-4">
            Next.js Server Component failed to fetch data from the Django backend.
          </p>
          <pre className="text-xs text-[var(--error)] font-mono bg-black/40 p-4 rounded overflow-x-auto max-w-full text-left whitespace-pre-wrap">
            {errorMsg}
          </pre>
        </div>
      ) : (
        <CustomersTabs
          initialCustomers={customers}
          initialSummary={summary}
          shopId={shopId}
          shopName={activeShop?.shop.name ?? ""}
          upiVpa={activeShop?.shop.upi_vpa ?? ""}
        />
      )}
    </AdminShell>
  );
}
