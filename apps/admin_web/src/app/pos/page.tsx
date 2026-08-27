import { PosTerminal } from "@/components/pos-terminal";
import { AdminShell } from "@/components/admin-shell";
import { getSession, resolveActiveShop, getInventory, getCustomers } from "@/lib/admin-api";
import type { InventoryItem, Customer } from "@/lib/types";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



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
  let errorMsg = "";

  if (shopId) {
    try {
      const [resInventory, resCustomers] = await Promise.all([
        getInventory(shopId),
        getCustomers(shopId),
      ]);
      inventory = resInventory;
      customers = resCustomers;
    } catch (err) {
      errorMsg = errorMessage(err, "Failed to load POS data from backend");
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
      ) : errorMsg ? (
        <div className="panel p-8 border-[var(--error)]/20 bg-[var(--error)]/5 rounded-xl">
          <p className="text-[var(--error)] font-semibold text-lg mb-2">Backend Connection Error</p>
          <p className="text-sm text-[var(--text-secondary)] mb-4">
            Next.js Server Component failed to fetch catalog data from the Django backend.
          </p>
          <pre className="text-xs text-[var(--error)] font-mono bg-black/40 p-4 rounded overflow-x-auto max-w-full text-left whitespace-pre-wrap">
            {errorMsg}
          </pre>
        </div>
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
