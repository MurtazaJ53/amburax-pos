import { AdminShell } from "@/components/admin-shell";
import { EmptyState } from "@/components/empty-state";
import { StocktakeScreen } from "@/components/stocktake";
import { getSession, resolveActiveShop } from "@/lib/admin-api";
import { canManageWorkspace } from "@/lib/roles";

export const metadata = {
  title: "Stocktake | Business Hub",
  description: "Count the shelves and reconcile against the books",
};

export default async function StocktakePage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="stocktake"
      title="Stocktake"
      subtitle="Count what is on the shelf. Applying posts the difference, so anything sold while you count is not undone."
    >
      {!activeShop ? (
        <EmptyState
          title="No shop membership found"
          body="This account is signed in, but there is no active shop membership yet."
        />
      ) : (
        <StocktakeScreen
          // Staff may count; applying rewrites stock shop-wide and reveals
          // shrinkage, so the backend requires manager level. Reflected here so
          // staff are not shown a button that can only fail.
          canApply={canManageWorkspace(activeShop.role)}
          currencyCode={activeShop.shop.currency_code}
        />
      )}
    </AdminShell>
  );
}
