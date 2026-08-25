import { SalesManager } from "@/components/sales-manager";
import { AdminShell } from "@/components/admin-shell";
import { refundsBySale } from "@/lib/sale-returns";
import {
  getSaleReturns,
  getSales,
  getSalesSummary,
  getSession,
  resolveActiveShop,
} from "@/lib/admin-api";

export const metadata = {
  title: "Sales History & Orders | Business Hub",
  description: "View sales ledger, invoices, payment breakdown, and refund receipts",
};

export default async function SalesPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);
  const shopId = activeShop?.shop.id || "";

  const [sales, summary, returns] = await Promise.all([
    getSales(shopId),
    getSalesSummary(shopId),
    // A bill that was sent back looks identical to one that was not, because
    // the return is a separate document. Reading them here is what lets the
    // table say so.
    getSaleReturns(shopId).catch(() => []),
  ]);

  const refundedBySale = refundsBySale(returns);

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="sales"
      fitViewport
      title="Sales History & Invoices"
      subtitle="Complete transaction logs, customer invoices, payment breakdowns, and returns"
    >
      <SalesManager
        initialSales={sales}
        initialSummary={summary}
        shopId={shopId}
        refundedBySale={refundedBySale}
        timeZone={activeShop?.shop.timezone || "Asia/Kolkata"}
        shopName={activeShop?.shop.name || ""}
        shopGstin={activeShop?.shop.gstin || ""}
        regionCode={activeShop?.shop.region_code || "IN"}
        shopLogo={activeShop?.shop.logo_data || ""}
        brandColor={activeShop?.shop.brand_color || ""}
      />
    </AdminShell>
  );
}
