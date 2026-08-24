import type { Metadata } from "next";
import Link from "next/link";
import { getPlatformAuditEvents, getSession } from "@/lib/admin-api";
import { PlatformShell } from "@/components/platform-shell";

export const metadata: Metadata = {
  title: "Audit Log | Platform Cockpit",
};

export default async function PlatformAuditPage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | undefined }>;
}) {
  const params = await searchParams;
  const q = params.q || "";
  const actionParam = params.action || "";
  const actorEmail = params.actor_email || "";
  const pageStr = params.page || "1";
  const currentPage = parseInt(pageStr, 10);

  const [session, auditPayload] = await Promise.all([
    getSession(),
    getPlatformAuditEvents({ q, action: actionParam, actor_email: actorEmail, page: pageStr }),
  ]);

  function buildSearchUrl(updates: Record<string, string | null>) {
    const urlParams = new URLSearchParams();
    if (q) urlParams.set("q", q);
    if (actionParam) urlParams.set("action", actionParam);
    if (actorEmail) urlParams.set("actor_email", actorEmail);
    if (currentPage > 1) urlParams.set("page", currentPage.toString());

    for (const [key, value] of Object.entries(updates)) {
      if (value === null || value === "") {
        urlParams.delete(key);
      } else {
        urlParams.set(key, value);
      }
    }
    
    if (("q" in updates || "action" in updates || "actor_email" in updates) && !("page" in updates)) {
      urlParams.delete("page");
    }

    const query = urlParams.toString();
    return query ? `/platform/audit?${query}` : "/platform/audit";
  }

  return (
    <PlatformShell
      session={session}
      activeRoute="audit"
      title="Global Audit Log"
      subtitle="Immutable record of operator actions across all tenants."
    >
      <div className="space-y-6">
        <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <form action="/platform/audit" method="GET" className="flex items-center gap-3">
            <input type="hidden" name="action" value={actionParam} />
            <input type="hidden" name="actor_email" value={actorEmail} />
            <input
              name="q"
              defaultValue={q}
              placeholder="Search reasons or metadata..."
              className="panel-soft w-80 rounded-xl border border-[var(--border-soft)] px-4 py-2 text-sm text-[var(--text-primary)] outline-none placeholder:text-[var(--text-muted)] focus:border-[var(--warning)]"
            />
            <button type="submit" className="rounded-xl bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 px-4 py-2 text-sm font-semibold text-[var(--primary-dark)] border border-[var(--primary)]/25">
              Search
            </button>
          </form>
          
          {(q || actionParam || actorEmail) && (
            <Link href="/platform/audit" className="text-sm text-[var(--warning)] hover:underline">
              Clear filters
            </Link>
          )}
        </div>

        <p className="eyebrow">Showing {auditPayload.count} {auditPayload.count === 1 ? "event" : "events"}</p>

        {auditPayload.results.length === 0 ? (
          <div className="panel-soft rounded-[24px] px-6 py-12 text-center text-[var(--text-secondary)]">
            <p>No audit events found.</p>
          </div>
        ) : (
          <div className="panel-soft overflow-hidden rounded-[24px]">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-[var(--border-soft)] text-[var(--text-secondary)]">
                <tr>
                  <th className="px-6 py-4 font-medium">Action</th>
                  <th className="px-6 py-4 font-medium">Shop</th>
                  <th className="px-6 py-4 font-medium">Actor</th>
                  <th className="px-6 py-4 font-medium">Reason</th>
                  <th className="px-6 py-4 font-medium text-right">Time</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-soft)]">
                {auditPayload.results.map((event) => (
                  <tr key={event.id} className="transition-colors hover:bg-[rgba(255,255,255,0.02)]">
                    <td className="px-6 py-4">
                      <ActionBadge action={event.action} />
                    </td>
                    <td className="px-6 py-4">
                      {event.shop ? (
                        <Link href={`/platform/shops/${event.shop}`} className="text-[var(--warning)] hover:underline font-medium">
                          {event.shop_name || event.shop_slug || event.shop}
                        </Link>
                      ) : (
                        <span className="text-[var(--text-secondary)]">-</span>
                      )}
                    </td>
                    <td className="px-6 py-4">
                      <div className="text-[var(--text-primary)]">{event.actor_name || "System"}</div>
                      {event.actor_email && <div className="text-[var(--text-secondary)] text-xs">{event.actor_email}</div>}
                    </td>
                    <td className="px-6 py-4 text-[var(--text-secondary)] max-w-xs truncate" title={event.reason}>
                      {event.reason || "-"}
                    </td>
                    <td className="px-6 py-4 text-right text-[var(--text-secondary)] whitespace-nowrap">
                      {new Date(event.created_at).toLocaleString()}
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
            href={auditPayload.results.length === 10 ? buildSearchUrl({ page: (currentPage + 1).toString() }) : "#"}
            className={`px-4 py-2 text-sm font-semibold rounded-xl ${auditPayload.results.length === 10 ? "bg-[rgba(255,255,255,0.1)] hover:bg-[rgba(255,255,255,0.15)] text-[var(--text-primary)]" : "text-[var(--text-muted)] pointer-events-none"}`}
          >
            Next
          </Link>
        </div>
      </div>
    </PlatformShell>
  );
}

function ActionBadge({ action }: { action: string }) {
  let colors = "text-[var(--text-secondary)] border-[rgba(152,164,189,0.18)] bg-[rgba(152,164,189,0.08)]";
  
  if (action === "shop.suspended") {
    colors = "text-[var(--error)] border-[rgba(244,63,94,0.18)] bg-[rgba(244,63,94,0.08)]";
  } else if (action === "shop.approved" || action === "shop.activated" || action === "shop.plan_changed") {
    colors = "text-[var(--warning)] border-[rgba(245,158,11,0.18)] bg-[rgba(245,158,11,0.08)]";
  }

  return (
    <span className={`inline-block rounded-md border px-2 py-1 text-xs font-mono uppercase tracking-tight ${colors}`}>
      {action}
    </span>
  );
}
