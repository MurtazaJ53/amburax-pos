import { PageLoadError } from "@/components/ui/page-load-error";
import { InventoryManager } from "@/components/inventory-manager";
import { AdminShell } from "@/components/admin-shell";
import { getSession, resolveActiveShop, getInventory, getInventorySummary } from "@/lib/admin-api";
import { canViewCosts } from "@/lib/roles";
import type { InventoryItem, InventorySummaryPayload } from "@/lib/types";




export const metadata = {
  title: "Inventory Management | Business Hub",
  description: "Manage products, barcodes, stock levels, variants, and low-stock alerts",
};

export default async function InventoryPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);
  const shopId = activeShop?.shop.id || "";

  let inventory: InventoryItem[] = [];
  let summary: InventorySummaryPayload = {
    total_items: 0,
    available_items: 0,
    low_stock_items: 0,
    out_of_stock_items: 0,
    categories: 0,
    projected_sell_value: null,
  };
  let loadError: unknown = null;

  if (shopId) {
    try {
      const [resInventory, resSummary] = await Promise.all([
        getInventory(shopId),
        getInventorySummary(shopId),
      ]);
      inventory = resInventory;
      summary = resSummary;
    } catch (err) {
      loadError = err;
      console.error("InventoryPage fetch error:", err);
    }
  }

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="inventory"
      fitViewport
      title="Inventory & Catalog"
      subtitle="Real-time stock valuation, barcode registry, low-stock threshold triggers & batch adjustments"
    >
      {!shopId ? (
        <div className="panel p-8 text-center text-[var(--text-secondary)]">
          <p className="font-semibold text-lg text-text-primary mb-2">No Active Shop</p>
          <p className="text-sm">Please select or create a shop first to view and manage inventory.</p>
        </div>
      ) : loadError ? (
        <PageLoadError error={loadError} subject="your products" />
      ) : (
        <InventoryManager
          initialInventory={inventory}
          initialSummary={summary}
          shopId={shopId}
          // The server already hides costs from anyone below admin by sending
          // null. Telling the screen the same rule lets it distinguish "no
          // cost recorded" from "not yours to see", instead of asking a
          // cashier to fill in a field they cannot read.
          canViewCosts={canViewCosts(activeShop?.role ?? null)}
        />
      )}
    </AdminShell>
  );
}
