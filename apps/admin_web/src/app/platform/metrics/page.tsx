import type { Metadata } from "next";
import { getPlatformMetrics, getSession } from "@/lib/admin-api";
import { PlatformShell } from "@/components/platform-shell";

export const metadata: Metadata = {
  title: "Global Metrics | Platform Cockpit",
};

export default async function PlatformMetricsPage() {
  const [session, metrics] = await Promise.all([
    getSession(),
    getPlatformMetrics(),
  ]);

  const totalPlanShops = metrics.starter_shops + metrics.growth_shops + metrics.pro_shops;
  const getPercent = (count: number) => totalPlanShops > 0 ? Math.round((count / totalPlanShops) * 100) : 0;

  return (
    <PlatformShell
      session={session}
      activeRoute="metrics"
      title="Global Metrics"
      subtitle="Overview of platform health and usage."
    >
      <div className="space-y-8">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="panel-soft rounded-[24px] p-6 border-t-4 border-t-[#47b0ff]">
            <p className="eyebrow">Total Shops</p>
            <p className="mt-2 text-4xl font-bold text-[#47b0ff]">{metrics.total_shops}</p>
          </div>
          <div className="panel-soft rounded-[24px] p-6 border-t-4 border-t-[var(--success)]">
            <p className="eyebrow">Active</p>
            <p className="mt-2 text-4xl font-bold text-[var(--success)]">{metrics.active_shops}</p>
          </div>
          <div className="panel-soft rounded-[24px] p-6 border-t-4 border-t-[var(--warning)]">
            <p className="eyebrow">Pending</p>
            <p className="mt-2 text-4xl font-bold text-[var(--warning)]">{metrics.pending_shops}</p>
          </div>
          <div className="panel-soft rounded-[24px] p-6 border-t-4 border-t-[var(--error)]">
            <p className="eyebrow">Suspended</p>
            <p className="mt-2 text-4xl font-bold text-[var(--error)]">{metrics.suspended_shops}</p>
          </div>
        </div>

        <div className="panel-soft rounded-[24px] p-6">
          <h2 className="eyebrow mb-6">Plan Distribution</h2>
          <div className="space-y-6">
            <PlanBar label="Starter" count={metrics.starter_shops} percent={getPercent(metrics.starter_shops)} color="#47b0ff" />
            <PlanBar label="Growth" count={metrics.growth_shops} percent={getPercent(metrics.growth_shops)} color="var(--success)" />
            <PlanBar label="Pro" count={metrics.pro_shops} percent={getPercent(metrics.pro_shops)} color="#a855f7" />
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="panel-soft rounded-[24px] p-6">
            <p className="eyebrow">Total Users</p>
            <p className="mt-2 text-3xl font-bold text-[var(--text-primary)]">{metrics.total_users}</p>
          </div>
          <div className="panel-soft rounded-[24px] p-6">
            <p className="eyebrow">New Shops (30d)</p>
            <p className="mt-2 text-3xl font-bold text-[var(--text-primary)]">{metrics.shops_created_last_30d}</p>
          </div>
          <div className={`panel-soft rounded-[24px] p-6 border-t-4 ${metrics.open_plan_requests > 0 ? "border-t-[var(--warning)]" : "border-t-transparent"}`}>
            <p className="eyebrow">Open Plan Requests</p>
            <p className={`mt-2 text-3xl font-bold ${metrics.open_plan_requests > 0 ? "text-[var(--warning)]" : "text-[var(--text-primary)]"}`}>
              {metrics.open_plan_requests}
            </p>
          </div>
        </div>
      </div>
    </PlatformShell>
  );
}

function PlanBar({ label, count, percent, color }: { label: string; count: number; percent: number; color: string }) {
  return (
    <div>
      <div className="flex justify-between text-sm mb-2">
        <span className="font-semibold text-[var(--text-primary)]">{label}</span>
        <span className="text-[var(--text-secondary)]">{count} ({percent}%)</span>
      </div>
      <div className="h-4 w-full bg-[rgba(255,255,255,0.05)] rounded-full overflow-hidden">
        <div 
          className="h-full rounded-full transition-all duration-500 ease-out" 
          style={{ width: `${percent}%`, backgroundColor: color }}
        />
      </div>
    </div>
  );
}
