import Link from "next/link";
import type { PlatformShopPayload } from "@/lib/types";

type Props = {
  shops: PlatformShopPayload[];
  count: number;
  currentPage: number;
  currentStatus: string;
  currentQ: string;
  currentPlan: string;
};

export function PlatformShopTable({ shops, count, currentPage, currentStatus, currentQ, currentPlan }: Props) {
  function buildSearchUrl(updates: Record<string, string | null>) {
    const params = new URLSearchParams();
    if (currentStatus) params.set("status", currentStatus);
    if (currentQ) params.set("q", currentQ);
    if (currentPlan) params.set("plan", currentPlan);
    if (currentPage > 1) params.set("page", currentPage.toString());

    for (const [key, value] of Object.entries(updates)) {
      if (value === null || value === "") {
        params.delete(key);
      } else {
        params.set(key, value);
      }
    }
    
    // reset page if search criteria changes
    if (("q" in updates || "status" in updates || "plan" in updates) && !("page" in updates)) {
      params.delete("page");
    }

    const query = params.toString();
    return query ? `/platform/shops?${query}` : "/platform/shops";
  }

  const statuses = [
    { value: "", label: "All" },
    { value: "pending", label: "Pending" },
    { value: "active", label: "Active" },
    { value: "suspended", label: "Suspended" },
  ];

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <form action="/platform/shops" method="GET" className="flex items-center gap-3">
          <input type="hidden" name="status" value={currentStatus} />
          <input type="hidden" name="plan" value={currentPlan} />
          <input
            name="q"
            defaultValue={currentQ}
            placeholder="Search shops..."
            className="panel-soft w-64 rounded-xl border border-[var(--border-soft)] px-4 py-2 text-sm text-[var(--text-primary)] outline-none placeholder:text-[var(--text-muted)] focus:border-[var(--warning)]"
          />
          <button type="submit" className="rounded-xl bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 px-4 py-2 text-sm font-semibold text-[var(--primary-dark)] border border-[var(--primary)]/25">
            Search
          </button>
        </form>

        <div className="flex gap-2">
          {statuses.map(s => (
            <Link
              key={s.value}
              href={buildSearchUrl({ status: s.value })}
              className={`rounded-full px-4 py-1.5 text-sm font-medium transition-colors ${
                currentStatus === s.value
                  ? "bg-[rgba(245,158,11,0.12)] text-[var(--warning)] border border-[rgba(245,158,11,0.18)]"
                  : "bg-transparent text-[var(--text-secondary)] hover:bg-[rgba(255,255,255,0.05)] border border-transparent"
              }`}
            >
              {s.label}
            </Link>
          ))}
        </div>
        
        <form action="/platform/shops" method="GET" className="flex items-center gap-2">
          <input type="hidden" name="status" value={currentStatus} />
          <input type="hidden" name="q" value={currentQ} />
          <select 
            name="plan"
            defaultValue={currentPlan}
            className="panel-soft rounded-xl border border-[var(--border-soft)] px-4 py-2 text-sm text-[var(--text-primary)] outline-none focus:border-[var(--warning)]"
            onChange={(e) => { e.target.form?.submit() }}
          >
            <option value="">All Plans</option>
            <option value="starter">Starter</option>
            <option value="growth">Growth</option>
            <option value="pro">Pro</option>
          </select>
          <noscript>
            <button type="submit" className="rounded-xl bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 px-4 py-2 text-sm font-semibold text-[var(--primary-dark)] border border-[var(--primary)]/25">
              Filter
            </button>
          </noscript>
        </form>
      </div>

      <p className="eyebrow">Showing {count} {count === 1 ? "shop" : "shops"}</p>

      {shops.length === 0 ? (
        <div className="panel-soft rounded-[24px] px-6 py-12 text-center text-[var(--text-secondary)]">
          <p>No shops found matching your criteria.</p>
          <Link href="/platform/shops" className="mt-4 inline-block text-[var(--warning)] hover:underline">
            Clear all filters
          </Link>
        </div>
      ) : (
        <div className="panel-soft overflow-hidden rounded-[24px]">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-[var(--border-soft)] text-[var(--text-secondary)]">
              <tr>
                <th className="px-6 py-4 font-medium">Shop</th>
                <th className="px-6 py-4 font-medium">Status</th>
                <th className="px-6 py-4 font-medium">Plan</th>
                <th className="px-6 py-4 font-medium">Owner</th>
                <th className="px-6 py-4 font-medium text-right">Members</th>
                <th className="px-6 py-4 font-medium">Created</th>
                <th className="px-6 py-4 font-medium text-right">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-soft)]">
              {shops.map((shop) => (
                <tr key={shop.id} className="group transition-colors hover:bg-[rgba(255,255,255,0.02)]">
                  <td className="px-6 py-4">
                    <div className="font-semibold text-[var(--text-primary)]">{shop.name}</div>
                    <div className="text-[var(--text-secondary)]">{shop.slug}</div>
                  </td>
                  <td className="px-6 py-4">
                    <StatusChip status={shop.status} display={shop.status_display} />
                  </td>
                  <td className="px-6 py-4">
                    <PlanChip plan={shop.plan_tier} />
                  </td>
                  <td className="px-6 py-4">
                    <div className="text-[var(--text-primary)]">{shop.owner_name || "-"}</div>
                    <div className="text-[var(--text-secondary)]">{shop.owner_email || "-"}</div>
                  </td>
                  <td className="px-6 py-4 text-right text-[var(--text-secondary)]">
                    {shop.member_count}
                  </td>
                  <td className="px-6 py-4 text-[var(--text-secondary)]">
                    {new Date(shop.created_at).toLocaleDateString()}
                  </td>
                  <td className="px-6 py-4 text-right">
                    <Link 
                      href={`/platform/shops/${shop.id}`}
                      className="font-medium text-[var(--warning)] opacity-0 group-hover:opacity-100 transition-opacity hover:underline"
                    >
                      Open
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="flex justify-between items-center">
        <Link 
          href={currentPage > 1 ? buildSearchUrl({ page: (currentPage - 1).toString() }) : "#"}
          className={`px-4 py-2 text-sm font-semibold rounded-xl ${currentPage > 1 ? "bg-[rgba(255,255,255,0.1)] hover:bg-[rgba(255,255,255,0.15)] text-[var(--text-primary)]" : "text-[var(--text-muted)] pointer-events-none"}`}
        >
          Previous
        </Link>
        <span className="text-sm text-[var(--text-secondary)]">Page {currentPage}</span>
        <Link 
          href={shops.length === 10 ? buildSearchUrl({ page: (currentPage + 1).toString() }) : "#"}
          className={`px-4 py-2 text-sm font-semibold rounded-xl ${shops.length === 10 ? "bg-[rgba(255,255,255,0.1)] hover:bg-[rgba(255,255,255,0.15)] text-[var(--text-primary)]" : "text-[var(--text-muted)] pointer-events-none"}`}
        >
          Next
        </Link>
      </div>
    </div>
  );
}

function StatusChip({ status, display }: { status: string; display: string }) {
  let colors = "";
  switch (status) {
    case "active":
      colors = "text-[var(--success)] border-[rgba(58,215,162,0.18)] bg-[rgba(58,215,162,0.08)]";
      break;
    case "pending":
      colors = "text-[var(--warning)] border-[rgba(245,158,11,0.18)] bg-[rgba(245,158,11,0.08)]";
      break;
    case "suspended":
      colors = "text-[var(--error)] border-[rgba(244,63,94,0.18)] bg-[rgba(244,63,94,0.08)]";
      break;
    default:
      colors = "text-[var(--text-secondary)] border-[rgba(152,164,189,0.18)] bg-[rgba(152,164,189,0.08)]";
  }
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium ${colors}`}>
      <span className="h-1.5 w-1.5 rounded-full bg-current" />
      {display}
    </span>
  );
}

function PlanChip({ plan }: { plan: string }) {
  let colors = "";
  switch (plan) {
    case "starter":
      colors = "text-[#47b0ff] border-[rgba(71,176,255,0.18)] bg-[rgba(71,176,255,0.08)]";
      break;
    case "growth":
      colors = "text-[var(--success)] border-[rgba(58,215,162,0.18)] bg-[rgba(58,215,162,0.08)]";
      break;
    case "pro":
      colors = "text-[#a855f7] border-[rgba(168,85,247,0.18)] bg-[rgba(168,85,247,0.08)]";
      break;
    default:
      colors = "text-[var(--text-secondary)] border-[rgba(152,164,189,0.18)] bg-[rgba(152,164,189,0.08)]";
  }
  return (
    <span className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-medium uppercase ${colors}`}>
      {plan}
    </span>
  );
}
