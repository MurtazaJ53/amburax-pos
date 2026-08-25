import { SuppliersPurchases } from "@/components/suppliers-purchases";
import { AdminShell } from "@/components/admin-shell";
import { getSession, resolveActiveShop } from "@/lib/admin-api";

export const metadata = {
  title: "Suppliers Directory | Business Hub",
  description: "Manage vendors, purchase orders, payables, and inbound stock",
};

export default async function SuppliersPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="suppliers"
      title="Suppliers"
      subtitle="Who you buy from, what you owe them, and the bills that made it up"
    >
      <SuppliersPurchases initialTab="suppliers" />
    </AdminShell>
  );
}
