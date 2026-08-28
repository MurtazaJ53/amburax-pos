import { PageLoadError } from "@/components/ui/page-load-error";
import { PosTerminal } from "@/components/pos-terminal";
import { AdminShell } from "@/components/admin-shell";
import { getSession, resolveActiveShop, getInventory, getCustomers } from "@/lib/admin-api";
import type { InventoryItem, Customer } from "@/lib/types";




export const metadata = {
  title: "POS Terminal | Business Hub",
  description: "High-speed retail point of sale and billing terminal",
};

export default async function PosPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);
  const shopId = activeShop?.shop.id || "";

  let inventory: InventoryItem[] = [];
  let customers: Customer[] = [];
  let loadError: unknown = null;

  if (shopId) {
    try {
      const [resInventory, resCustomers] = await Promise.all([
        getInventory(shopId),
        getCustomers(shopId),
      ]);
      inventory = resInventory;
      customers = resCustomers;
    } catch (err) {
      loadError = err;
      console.error("PosPage fetch error:", err);
    }
  }

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="pos"
      fitViewport
      title="Retail POS Terminal"
      subtitle="Fast barcode scanning, dynamic GST calculation, split tender & instant thermal printing"
    >
      {!shopId ? (
        <div className="panel p-8 text-center text-[var(--text-secondary)]">
          <p className="font-semibold text-lg text-text-primary mb-2">No Active Shop</p>
          <p className="text-sm">Please select or create a shop first to load the POS billing terminal.</p>
        </div>
      ) : loadError ? (
        <PageLoadError error={loadError} subject="the till" />
      ) : (
        <PosTerminal
          shopName={activeShop?.shop.name || ""}
          shopGstin={activeShop?.shop.gstin || ""}
          // Wired through, not left to a default. These were simply omitted,
          // so every shop's receipt printed the placeholder address and phone
          // baked into the component.
          shopAddress={activeShop?.shop.address || ""}
          shopPhone={activeShop?.shop.business_phone || ""}
          regionCode={activeShop?.shop.region_code || "IN"}
          shopLogo={activeShop?.shop.logo_data || ""}
          brandColor={activeShop?.shop.brand_color || ""}
          cashierName={session.user.full_name || ""}
          initialInventory={inventory}
          initialCustomers={customers}
          shopId={shopId}
        />
      )}
    </AdminShell>
  );
}
