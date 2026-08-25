import { AdminShell } from "@/components/admin-shell";
import { InsightsTabs } from "@/components/insights-tabs";
import { getSession, resolveActiveShop } from "@/lib/admin-api";

export const metadata = {
  title: "Report | Business Hub",
  description: "Cash kept, dead stock, the buying list, and how the team is selling",
};

export default async function InsightsPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="insights"
      title="Report"
      subtitle="Whether the shop kept money, what it is stuck with, and what to buy next"
    >
      <InsightsTabs
        shopName={activeShop?.shop.name ?? ""}
        timeZone={activeShop?.shop.timezone ?? "Asia/Kolkata"}
      />
    </AdminShell>
  );
}
