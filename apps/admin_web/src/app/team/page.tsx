import { PageLoadError } from "@/components/ui/page-load-error";
import { TeamAttendance } from "@/components/team-attendance";
import { AdminShell } from "@/components/admin-shell";
import { getSession, resolveActiveShop, getWorkspaceTeamMembers, getAttendanceSessions, getAttendanceSummary, getWorkspaceAccessSessions } from "@/lib/admin-api";
import type { WorkspaceTeamMemberPayload, AttendanceSession, AttendanceSummaryPayload, WorkspaceAccessSessionPayload } from "@/lib/types";




export const metadata = {
  title: "Staff | Business Hub",
  description: "Manage staff roles, cashier permissions, shift rosters, and attendance",
};

export default async function TeamPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);
  const shopId = activeShop?.shop.id || "";

  let team: WorkspaceTeamMemberPayload[] = [];
  let sessions: AttendanceSession[] = [];
  let summary: AttendanceSummaryPayload = {
    total_sessions: 0,
    present_count: 0,
    leave_count: 0,
    active_workers_today: 0,
  };
  let devices: WorkspaceAccessSessionPayload[] = [];
  let loadError: unknown = null;

  if (shopId) {
    try {
      const [resTeam, resSessions, resSummary, resDevices] = await Promise.all([
        getWorkspaceTeamMembers(shopId),
        getAttendanceSessions(shopId),
        getAttendanceSummary(shopId),
        // Read-only here. Revoking is MFA-gated and stays on /sessions;
        // seeing which device belongs to which person belongs beside the
        // person.
        getWorkspaceAccessSessions(shopId).catch(() => []),
      ]);
      team = resTeam;
      sessions = resSessions;
      summary = resSummary;
      devices = resDevices;
    } catch (err) {
      loadError = err;
      console.error("TeamPage fetch error:", err);
    }
  }

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="team"
      title="Staff"
      fitViewport
      subtitle="Who may open the shop, what they may do, and who worked which shift"
    >
      {!shopId ? (
        <div className="panel p-8 text-center text-[var(--text-secondary)]">
          <p className="font-semibold text-lg text-text-primary mb-2">No Active Shop</p>
          <p className="text-sm">Please select or create a shop first to view and manage team members.</p>
        </div>
      ) : loadError ? (
        <PageLoadError error={loadError} subject="your team" />
      ) : (
        <TeamAttendance
          timeZone={activeShop?.shop.timezone || "Asia/Kolkata"}
          initialTeam={team}
          initialSessions={sessions}
          initialSummary={summary}
          initialDevices={devices}
          defaultTab="team"
          shopId={shopId}
        />
      )}
    </AdminShell>
  );
}
