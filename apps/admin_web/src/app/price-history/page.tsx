import { AdminShell } from "@/components/admin-shell";
import { EmptyState } from "@/components/empty-state";
import { PriceHistoryScreen } from "@/components/price-history";
import { getSession, resolveActiveShop } from "@/lib/admin-api";

export const metadata = {
  title: "Supplier prices | Business Hub",
  description: "What you pay each supplier, and who has been putting prices up",
};

export default async function PriceHistoryPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="price-history"
      title="Supplier prices"
      subtitle="Built from purchase invoices you have already entered. Each supplier is compared only against its own earlier price."
    >
      {!activeShop ? (
        <EmptyState
          title="No shop membership found"
          body="This account is signed in, but there is no active shop membership yet."
        />
      ) : (
        <PriceHistoryScreen currencyCode={activeShop.shop.currency_code} />
      )}
    </AdminShell>
  );
}
