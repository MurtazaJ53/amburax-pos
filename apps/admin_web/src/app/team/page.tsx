import { TeamAttendance } from "@/components/team-attendance";
import { AdminShell } from "@/components/admin-shell";
import { getSession, resolveActiveShop, getWorkspaceTeamMembers, getAttendanceSessions, getAttendanceSummary } from "@/lib/admin-api";
import type { WorkspaceTeamMemberPayload, AttendanceSession, AttendanceSummaryPayload } from "@/lib/types";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



export const metadata = {
  title: "Team & Staff Management | Business Hub",
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
  let errorMsg = "";

  if (shopId) {
    try {
      const [resTeam, resSessions, resSummary] = await Promise.all([
        getWorkspaceTeamMembers(shopId),
        getAttendanceSessions(shopId),
        getAttendanceSummary(shopId),
      ]);
      team = resTeam;
      sessions = resSessions;
      summary = resSummary;
    } catch (err) {
      errorMsg = errorMessage(err, "Failed to load team data from backend");
      console.error("TeamPage fetch error:", err);
    }
  }

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="team"
      title="Team Roster & Staff Permissions"
      subtitle="Role-based access control, cashier invites, salary tracking, and active shift monitoring"
    >
      {!shopId ? (
        <div className="panel p-8 text-center text-[var(--text-secondary)]">
          <p className="font-semibold text-lg text-text-primary mb-2">No Active Shop</p>
          <p className="text-sm">Please select or create a shop first to view and manage team members.</p>
        </div>
      ) : errorMsg ? (
        <div className="panel p-8 border-[var(--error)]/20 bg-[var(--error)]/5 rounded-xl">
          <p className="text-[var(--error)] font-semibold text-lg mb-2">Backend Connection Error</p>
          <p className="text-sm text-[var(--text-secondary)] mb-4">
            Next.js Server Component failed to fetch team data from the Django backend.
          </p>
          <pre className="text-xs text-[var(--error)] font-mono bg-black/40 p-4 rounded overflow-x-auto max-w-full text-left whitespace-pre-wrap">
            {errorMsg}
          </pre>
        </div>
      ) : (
        <TeamAttendance
          timeZone={activeShop?.shop.timezone || "Asia/Kolkata"} initialTeam={team} initialSessions={sessions} initialSummary={summary} shopId={shopId} />
      )}
    </AdminShell>
  );
}
