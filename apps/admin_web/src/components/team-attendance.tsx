"use client";

import { useT } from "@/lib/i18n";

import React, { useState, useMemo } from "react";
import { StatTile } from "@/components/ui/stat-tile";
import { formatRole } from "@/lib/formatters";
import { summariseWeek, weekStart } from "@/lib/attendance-week";
import { shopDateKey } from "@/lib/dashboard-metrics";
import {
  Plus,
  Shield,
  Calendar,
  LogIn,
  LogOut,
  X,
  Loader2,
} from "lucide-react";
import { formatDate } from "@/lib/utils";
import type { AttendanceSession, AttendanceSummaryPayload, WorkspaceTeamMemberPayload } from "@/lib/types";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



interface TeamAttendanceProps {
  initialTeam: WorkspaceTeamMemberPayload[];
  initialSessions: AttendanceSession[];
  initialSummary: AttendanceSummaryPayload;
  shopId: string;
  /** The shop's IANA timezone, for deciding which week is the current one. */
  timeZone?: string;
}

export function TeamAttendance({
  initialTeam,
  initialSessions,
  initialSummary,
  // The week has to be the shop's week. A UTC clock rolls over five and a
  // half hours early for an Indian shop, which would move Monday.
  timeZone = "Asia/Kolkata",
}: TeamAttendanceProps) {
  const t = useT();
  const [staff, setStaff] = useState<WorkspaceTeamMemberPayload[]>(initialTeam ?? []);
  const [attendance, setAttendance] = useState<AttendanceSession[]>(initialSessions ?? []);
  const [summary, setSummary] = useState<AttendanceSummaryPayload>(initialSummary ?? { total_sessions: 0, present_count: 0, leave_count: 0, active_workers_today: 0 });
  const [activeTab, setActiveTab] = useState<"team" | "attendance">("team");
  const [isLoading, setIsLoading] = useState(false);

  // Invite modal
  const [isInviteOpen, setIsInviteOpen] = useState(false);
  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteName, setInviteName] = useState("");
  const [inviteRole, setInviteRole] = useState<"admin" | "staff" | "viewer">("staff");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState("");

  // Manual Attendance modal
  const [isManualAttendanceOpen, setIsManualAttendanceOpen] = useState(false);
  const [selectedMemberId, setSelectedMemberId] = useState("");
  const [attendanceStatus, setAttendanceStatus] = useState<"present" | "half_day" | "leave" | "absent">("present");
  const [attendanceNote, setAttendanceNote] = useState("");

  // Whoever is actually signed in — not whoever happens to be first in the
  // roster.
  //
  // This was `staff[0]`, so every clock-in and clock-out on this screen was
  // recorded against the first member the API returned, regardless of who
  // pressed the button. For a shop with more than one person that silently
  // corrupts attendance, and therefore payroll, for everybody except that one
  // member — and it looks correct on screen the whole time.
  //
  // The backend has always said which membership is the caller's:
  // is_current_user, set in shops/serializers.py by comparing the actor's
  // user_id. It was simply never read.
  const myMember = useMemo(() => {
    return staff.find((member) => member.is_current_user) ?? null;
  }, [staff]);

  /** Everyone clocked in and not yet clocked out. The one question this
   *  screen exists to answer and never did. */
  /** The current week's timesheet, rolled up from the sessions already
   *  loaded — no extra request, and the same figures wages are paid on. */
  const weekStartKey = useMemo(
    () => weekStart(shopDateKey(new Date(), timeZone)),
    [timeZone],
  );

  const weekRows = useMemo(
    () => summariseWeek(attendance, weekStartKey),
    [attendance, weekStartKey],
  );

  const openShifts = useMemo(
    () => attendance.filter((session) => session.clock_in_at && !session.clock_out_at),
    [attendance],
  );

  const myActiveSession = useMemo(() => {
    if (!myMember) return null;
    return attendance.find((a) => a.membership_id === myMember.id && !a.clock_out_at);
  }, [attendance, myMember]);

  const refreshData = async () => {
    try {
      setIsLoading(true);
      const [resTeam, resSessions, resSummary] = await Promise.all([
        fetch("/api/team").then((r) => r.json()),
        fetch("/api/attendance").then((r) => r.json()),
        fetch("/api/attendance/summary").then((r) => r.json()),
      ]);
      setStaff(resTeam);
      setAttendance(resSessions);
      setSummary(resSummary);
    } catch (err) {
      console.error(err);
    } finally {
      setIsLoading(false);
    }
  };

  const handleInviteStaff = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    setSubmitError("");

    try {
      const res = await fetch("/api/invites", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: inviteEmail,
          role: inviteRole,
          name: inviteName,
        }),
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || "Failed to invite team member");
      }

      setIsInviteOpen(false);
      setInviteEmail("");
      setInviteName("");
      await refreshData();
    } catch (err) {
      setSubmitError(errorMessage(err, "Failed to send invitation."));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleToggleClock = async () => {
    if (!myMember) return;
    setIsSubmitting(true);

    try {
      if (myActiveSession) {
        // Clock Out
        const res = await fetch(`/api/attendance/${myActiveSession.id}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            clock_out_at: new Date().toISOString(),
          }),
        });
        if (!res.ok) throw new Error("Failed to clock out");
      } else {
        // Clock In
        const res = await fetch("/api/attendance", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            membership_id: myMember.id,
            session_date: new Date().toISOString().split("T")[0],
            clock_in_at: new Date().toISOString(),
            status: "present",
          }),
        });
        if (!res.ok) throw new Error("Failed to clock in");
      }
      await refreshData();
    } catch (err) {
      alert(errorMessage(err, "Failed to record attendance shift."));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleManualAttendance = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedMemberId) return;

    setIsSubmitting(true);
    setSubmitError("");

    try {
      const res = await fetch("/api/attendance", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          membership_id: selectedMemberId,
          session_date: new Date().toISOString().split("T")[0],
          clock_in_at: new Date().toISOString(),
          status: attendanceStatus,
          note: attendanceNote,
        }),
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || "Failed to record manual attendance");
      }

      setIsManualAttendanceOpen(false);
      setSelectedMemberId("");
      setAttendanceNote("");
      await refreshData();
    } catch (err) {
      setSubmitError(errorMessage(err, "Failed to save attendance."));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-text-primary tracking-tight">
            Team Members & Staff Attendance
          </h2>
          <p className="text-xs text-[var(--text-tertiary)]">
            Manage store employees, assign POS/admin role permissions, and track shift clock-ins
          </p>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={handleToggleClock}
            // Disabled rather than silently doing nothing when the signed-in
            // user has no membership on this shop (a platform admin looking at
            // someone else's shop, for instance). The handler already returned
            // early in that case, which made the button look live and do
            // nothing at all.
            disabled={isSubmitting || !myMember}
            title={
              myMember
                ? undefined
                : "You are viewing this shop without a staff membership, so there is no shift to clock."
            }
            className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-semibold border transition-all ${
              myActiveSession
                ? "bg-[var(--warning)]/10 border-[var(--warning)]/30 text-[var(--warning)] hover:bg-[var(--warning)]/20"
                : "bg-[var(--success-dark)] hover:bg-[var(--success)] text-white"
            } disabled:opacity-50`}
          >
            {isSubmitting ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : myActiveSession ? (
              <>
                <LogOut className="w-4 h-4 text-[var(--warning)]" />
                <span>Clock Out of Shift</span>
              </>
            ) : (
              <>
                <LogIn className="w-4 h-4" />
                <span>Clock In to Shift</span>
              </>
            )}
          </button>

          <button
            onClick={() => {
              if (staff.length > 0) setSelectedMemberId(staff[0].id);
              setIsManualAttendanceOpen(true);
            }}
            className="flex items-center gap-1.5 px-4 py-2 bg-bg-soft hover:bg-bg-base border border-[var(--border-soft)] text-text-primary text-xs font-semibold rounded-xl"
          >
            <Calendar className="w-4 h-4" />
            <span>Mark Attendance</span>
          </button>

          <button
            onClick={() => setIsInviteOpen(true)}
            className="flex items-center gap-1.5 px-4 py-2 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-semibold rounded-xl"
          >
            <Plus className="w-4 h-4" />
            <span>Invite Team Member</span>
          </button>
        </div>
      </div>

      {/* Four figures about the roster */}
      <div className="grid grid-cols-2 gap-3.5 lg:grid-cols-4">
        <StatTile
          label="Roster"
          value={String(staff.length)}
          note={`${staff.filter((m) => m.status === "active").length} active`}
          className="animate-fade-in-up delay-1"
        />
        <StatTile
          label="On shift now"
          value={String(openShifts.length)}
          note={
            openShifts.length === 0
              ? "Nobody is clocked in"
              : openShifts.map((sh) => sh.member_name).join(", ")
          }
          tone={openShifts.length > 0 ? "good" : "neutral"}
          noteToneOverride="neutral"
          className="animate-fade-in-up delay-2"
        />
        <StatTile
          label="Present today"
          value={String(summary.active_workers_today)}
          note={`of ${staff.length} on the roster`}
          className="animate-fade-in-up delay-3"
        />
        <StatTile
          label="Attendance logs"
          value={String(summary.total_sessions)}
          note="Recorded all time"
          className="animate-fade-in-up delay-4"
        />
      </div>

      {/* Who is actually on the counter. The page has always promised shift
          monitoring; until now it showed a roster and left you to guess. */}
      {openShifts.length > 0 && (
        <div className="rounded-[20px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm animate-fade-in-up delay-3">
          <div className="mb-3 flex items-center gap-2.5">
            <h3 className="text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
              On the counter right now
            </h3>
            <span className="tnum rounded-md bg-[var(--success)]/10 px-1.5 py-0.5 font-mono text-[10px] font-bold text-[var(--success-strong)]">
              {openShifts.length}
            </span>
          </div>

          <ul className="m-0 flex list-none flex-wrap gap-2.5 p-0">
            {openShifts.map((shift) => (
              <li
                key={shift.id}
                className="flex items-center gap-2.5 rounded-[12px] border border-[var(--success)]/40 bg-[var(--success)]/10 px-3 py-2"
              >
                <span className="grid h-7 w-7 flex-none place-items-center rounded-lg bg-[var(--success)] text-[11px] font-extrabold text-white">
                  {(shift.member_name || "?").charAt(0).toUpperCase()}
                </span>
                <span>
                  <span className="block text-[12.5px] font-extrabold text-[var(--success-strong)]">
                    {shift.member_name}
                    {shift.member_role ? ` · ${formatRole(shift.member_role)}` : ""}
                  </span>
                  <span className="mt-0.5 block font-mono text-[10.5px] font-semibold text-[var(--success-strong)] opacity-80">
                    {shift.clock_in_at
                      ? `since ${new Date(shift.clock_in_at).toLocaleTimeString("en-IN", {
                          timeStyle: "short",
                        })}`
                      : "clock-in time not recorded"}
                  </span>
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* The week behind wages. Days present, hours and overtime are what a
          shopkeeper actually pays on; the session log alone does not answer it. */}
      {weekRows.length > 0 && (
        <div className="overflow-hidden rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] shadow-sm animate-fade-in-up delay-4">
          <div className="flex flex-wrap items-center gap-2.5 border-b border-[var(--border-soft)] px-4 py-3">
            <h3 className="text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
              This week
            </h3>
            <span className="rounded-full border border-[var(--border-soft)] bg-[var(--bg-base)] px-2.5 py-1 font-mono text-[11px] font-bold text-[var(--text-secondary)]">
              from {new Date(weekStartKey).toLocaleDateString("en-IN", {
                day: "numeric",
                month: "short",
              })}
            </span>
            <span className="ml-auto font-mono text-[11px] font-medium text-[var(--text-tertiary)]">
              {weekRows.reduce((sum, r) => sum + r.hours, 0).toFixed(1)} hours total
            </span>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left">
              <thead>
                <tr className="border-b border-[var(--border-soft)] bg-[var(--bg-soft)] font-mono text-[9.5px] font-semibold uppercase tracking-[0.13em] text-[var(--text-tertiary)]">
                  <th className="px-4 py-2.5">Member</th>
                  <th className="px-4 py-2.5">Role</th>
                  <th className="px-4 py-2.5 text-right">Days present</th>
                  <th className="px-4 py-2.5 text-right">Hours</th>
                  <th className="px-4 py-2.5 text-right">Overtime</th>
                  <th className="px-4 py-2.5">Now</th>
                </tr>
              </thead>
              <tbody>
                {weekRows.map((row) => (
                  <tr
                    key={row.membershipId}
                    className="border-b border-[var(--border-soft)] transition-colors last:border-b-0 hover:bg-[var(--bg-base)]"
                  >
                    <td className="px-4 py-3 text-[12.5px] font-extrabold text-[var(--text-primary)]">
                      {row.name}
                    </td>
                    <td className="px-4 py-3">
                      <span className="inline-flex rounded-full bg-[var(--primary)]/10 px-2.5 py-1 text-[11px] font-bold text-[var(--primary-hover)]">
                        {formatRole(row.role)}
                      </span>
                    </td>
                    <td className="tnum px-4 py-3 text-right font-mono text-[12.5px] font-semibold">
                      {row.daysPresent}
                    </td>
                    <td className="tnum px-4 py-3 text-right font-mono text-[12.5px] font-bold text-[var(--text-primary)]">
                      {row.hours.toFixed(1)}
                    </td>
                    <td
                      className={`tnum px-4 py-3 text-right font-mono text-[12.5px] font-semibold ${
                        row.overtime > 0
                          ? "text-[var(--warning-strong)]"
                          : "text-[var(--text-tertiary)]"
                      }`}
                    >
                      {row.overtime.toFixed(1)}
                    </td>
                    <td className="px-4 py-3">
                      {row.onShift ? (
                        <span className="inline-flex rounded-full bg-[var(--success)]/10 px-2.5 py-1 text-[11px] font-bold text-[var(--success-strong)]">
                          On shift
                        </span>
                      ) : (
                        <span className="text-[11.5px] font-semibold text-[var(--text-tertiary)]">
                          Clocked out
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Tabs */}
      <div className="flex items-center gap-2 border-b border-[var(--border-soft)]">
        <button
          onClick={() => setActiveTab("team")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors ${
            activeTab === "team"
              ? "border-[var(--primary)] text-text-primary"
              : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
          }`}
        >
          Team Roster ({staff.length})
        </button>
        <button
          onClick={() => setActiveTab("attendance")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors ${
            activeTab === "attendance"
              ? "border-[var(--primary)] text-text-primary"
              : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
          }`}
        >
          Attendance Sessions ({attendance.length})
        </button>
      </div>

      {/* Tab Panels */}
      {activeTab === "team" ? (
        <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl overflow-hidden shadow-xl relative">
          {isLoading && (
            <div className="absolute inset-0 bg-surface/50 backdrop-blur-[1px] flex items-center justify-center z-10">
              <Loader2 className="w-6 h-6 text-primary animate-spin" />
            </div>
          )}
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-bg-soft border-b border-[var(--border-soft)] text-[var(--text-tertiary)] font-semibold uppercase tracking-wider text-[10px]">
                  <th className="py-3 px-4">Member Name</th>
                  <th className="py-3 px-4">{t("webEmail", "Email")}</th>
                  <th className="py-3 px-4">Role</th>
                  <th className="py-3 px-4">Phone</th>
                  <th className="py-3 px-4">Status</th>
                  <th className="py-3 px-4">Joined Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-soft)]">
                {staff.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="py-12 text-center text-xs text-[var(--text-tertiary)]">
                      No staff yet. Invite a cashier and they will appear here with their role and shift history.
                    </td>
                  </tr>
                ) : (
                  staff.map((member) => (
                    <tr key={member.id} className="hover:bg-bg-base transition-colors">
                      <td className="py-3 px-4 font-semibold text-text-primary">
                        {member.member_name || member.member_email || "Unknown User"}
                      </td>
                      <td className="py-3 px-4 text-[var(--text-secondary)] font-mono">
                        {member.member_email}
                      </td>
                      <td className="py-3 px-4">
                        <span className="inline-flex items-center gap-1.5 rounded-full bg-[var(--primary)]/10 px-2.5 py-1 text-[11px] font-bold text-[var(--primary-hover)]">
                          <Shield className="h-3 w-3" />
                          {member.role_label || formatRole(member.role)}
                        </span>
                        {/* What the role actually permits. The server has sent
                            this all along; the cell showed the bare word, which
                            tells whoever is assigning it nothing. */}
                        {member.role_summary && (
                          <span className="mt-1 block text-[11px] font-semibold text-[var(--text-tertiary)]">
                            {member.role_summary}
                          </span>
                        )}
                      </td>
                      <td className="py-3 px-4 font-mono text-[var(--text-tertiary)]">
                        {member.phone || "—"}
                      </td>
                      <td className="py-3 px-4">
                        <span className={`px-2 py-0.5 rounded text-[10px] font-bold uppercase ${
                          member.status === "active"
                            ? "bg-[var(--success)]/10 text-[var(--success)]"
                            : "bg-[var(--warning)]/10 text-[var(--warning)]"
                        }`}>
                          {member.status}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-[var(--text-tertiary)]">
                        {formatDate(member.created_at)}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl overflow-hidden shadow-xl relative">
          {isLoading && (
            <div className="absolute inset-0 bg-surface/50 backdrop-blur-[1px] flex items-center justify-center z-10">
              <Loader2 className="w-6 h-6 text-primary animate-spin" />
            </div>
          )}
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-bg-soft border-b border-[var(--border-soft)] text-[var(--text-tertiary)] font-semibold uppercase tracking-wider text-[10px]">
                  <th className="py-3 px-4">Employee</th>
                  <th className="py-3 px-4">Session Date</th>
                  <th className="py-3 px-4 text-center">Clock In</th>
                  <th className="py-3 px-4 text-center">Clock Out</th>
                  <th className="py-3 px-4 text-center">Hours Worked</th>
                  <th className="py-3 px-4 text-center">Status</th>
                  <th className="py-3 px-4">Supervisor Notes</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-soft)]">
                {attendance.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="py-12 text-center text-xs text-[var(--text-tertiary)]">
                      No attendance session logs found.
                    </td>
                  </tr>
                ) : (
                  attendance.map((record) => (
                    <tr key={record.id} className="hover:bg-bg-base transition-colors">
                      <td className="py-3 px-4 font-semibold text-text-primary">
                        {record.member_name}
                      </td>
                      <td className="py-3 px-4 font-mono text-[var(--text-secondary)]">
                        {formatDate(record.session_date)}
                      </td>
                      <td className="py-3 px-4 text-center font-mono text-[var(--text-secondary)]">
                        {record.clock_in_at ? new Date(record.clock_in_at).toLocaleTimeString("en-IN", { timeStyle: "short" }) : "—"}
                      </td>
                      <td className="py-3 px-4 text-center font-mono text-[var(--text-secondary)]">
                        {record.clock_out_at ? new Date(record.clock_out_at).toLocaleTimeString("en-IN", { timeStyle: "short" }) : "Active Shift"}
                      </td>
                      <td className="py-3 px-4 text-center font-mono font-semibold text-text-primary">
                        {record.total_hours !== undefined ? `${parseFloat(String(record.total_hours)).toFixed(1)} hrs` : "—"}
                      </td>
                      <td className="py-3 px-4 text-center">
                        <span className={`px-2 py-0.5 rounded text-[10px] font-bold uppercase ${
                          record.status === "PRESENT"
                            ? "bg-[var(--success)]/10 text-[var(--success)]"
                            : record.status === "HALF_DAY"
                            ? "bg-[var(--warning)]/10 text-[var(--warning)]"
                            : "bg-[var(--error)]/10 text-[var(--error)]"
                        }`}>
                          {record.status}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-[var(--text-tertiary)] italic">
                        {record.note || "—"}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* MODAL: Invite Staff */}
      {isInviteOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          onClick={() => setIsInviteOpen(false)}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-bg-soft">
              <span className="font-semibold text-sm text-text-primary">Invite Team Member</span>
              <button
                onClick={() => setIsInviteOpen(false)}
                className="p-1 text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleInviteStaff} className="p-6 space-y-4">
              {submitError && (
                <div className="p-3 bg-[var(--error)]/10 border border-[var(--error)]/20 text-[var(--error-strong)] text-xs rounded-xl font-bold">
                  {submitError}
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Full Name *
                </label>
                <input
                  type="text"
                  required
                  value={inviteName}
                  onChange={(e) => setInviteName(e.target.value)}
                  placeholder="e.g. Ramesh Verma"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Email Address *
                </label>
                <input
                  type="email"
                  required
                  value={inviteEmail}
                  onChange={(e) => setInviteEmail(e.target.value)}
                  placeholder="e.g. name@example.com"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  System Role Access
                </label>
                <select
                  value={inviteRole}
                  onChange={(e) => setInviteRole(e.target.value as "admin" | "staff" | "viewer")}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                >
                  <option value="staff">Staff Operator / Cashier</option>
                  <option value="admin">Shop Co-Administrator</option>
                  <option value="viewer">Read-Only Viewer</option>
                </select>
              </div>

              <div className="pt-3 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  disabled={isSubmitting}
                  onClick={() => setIsInviteOpen(false)}
                  className="px-4 py-2 text-xs text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-5 py-2 text-xs font-semibold text-[var(--primary-dark)] bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 rounded-xl shadow-md flex items-center gap-1.5 disabled:opacity-50 border border-[var(--primary)]/25"
                >
                  {isSubmitting && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                  <span>Send Invitation</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* MODAL: Mark Manual Attendance */}
      {isManualAttendanceOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          onClick={() => setIsManualAttendanceOpen(false)}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-bg-soft">
              <span className="font-semibold text-sm text-text-primary">Mark Attendance</span>
              <button
                onClick={() => setIsManualAttendanceOpen(false)}
                className="p-1 text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleManualAttendance} className="p-6 space-y-4">
              {submitError && (
                <div className="p-3 bg-[var(--error)]/10 border border-[var(--error)]/20 text-[var(--error-strong)] text-xs rounded-xl font-bold">
                  {submitError}
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Select Team Member *
                </label>
                <select
                  value={selectedMemberId}
                  onChange={(e) => setSelectedMemberId(e.target.value)}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                >
                  {staff.map((member) => (
                    <option key={member.id} value={member.id}>
                      {member.member_name || member.member_email || "Unknown Member"} ({member.role})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Attendance Status
                </label>
                <select
                  value={attendanceStatus}
                  onChange={(e) => setAttendanceStatus(e.target.value as "present" | "half_day" | "leave" | "absent")}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                >
                  <option value="present">Present (Full Day)</option>
                  <option value="half_day">Half Day Shift</option>
                  <option value="leave">On Approved Leave</option>
                  <option value="absent">Unexcused Absent</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Supervisor Remarks / Note
                </label>
                <input
                  type="text"
                  value={attendanceNote}
                  onChange={(e) => setAttendanceNote(e.target.value)}
                  placeholder="e.g. Late by 15 mins or Sick leave"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>

              <div className="pt-3 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  disabled={isSubmitting}
                  onClick={() => setIsManualAttendanceOpen(false)}
                  className="px-4 py-2 text-xs text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-5 py-2 text-xs font-semibold text-[var(--primary-dark)] bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 rounded-xl shadow-md flex items-center gap-1.5 disabled:opacity-50 border border-[var(--primary)]/25"
                >
                  {isSubmitting && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                  <span>Save Record</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
