"use client";

import { useT } from "@/lib/i18n";

import React, { useState, useMemo, useEffect } from "react";
import { formatCurrency, formatRole } from "@/lib/formatters";
import { summariseWeek, weekStart } from "@/lib/attendance-week";
import { monthLabel, monthsIn, paySheet, payTotals } from "@/lib/pay-sheet";
import { EMPTY_HISTORY, discountRate, readMemberHistory } from "@/lib/member-history";
import type { MemberHistory } from "@/lib/member-history";
import { shopDateKey } from "@/lib/dashboard-metrics";
import {
  Plus,
  Shield,
  LogIn,
  LogOut,
  X,
  Loader2,
} from "lucide-react";
import { formatDate } from "@/lib/utils";
import type {
  AttendanceSession,
  AttendanceSummaryPayload,
  WorkspaceAccessSessionPayload,
  WorkspaceTeamMemberPayload,
} from "@/lib/types";
import { useServerRefresh } from "@/lib/use-server-refresh";
import { useDialog } from "@/components/ui/dialog-provider";

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
  /** Which half this route is. /staff and /attendance rendered the same
   *  component with identical props and always opened on the roster, so a
   *  link called Attendance landed you a click away from attendance. */
  defaultTab?: TabKey;
  /** Signed-in devices, fetched by the page. Read-only here - revoking sits
   *  behind the MFA gate on /sessions and must stay there. */
  initialDevices?: WorkspaceAccessSessionPayload[];
}

export type TabKey = "team" | "attendance" | "pay" | "devices";

export function TeamAttendance({
  initialTeam,
  initialSessions,
  initialSummary,
  // The week has to be the shop's week. A UTC clock rolls over five and a
  // half hours early for an Indian shop, which would move Monday.
  timeZone = "Asia/Kolkata",
  defaultTab = "team",
  initialDevices = [],
}: TeamAttendanceProps) {
  const { say } = useDialog();
  const refreshServerData = useServerRefresh();
  const devices = initialDevices;
  /** The month the pay sheet is showing. Defaults to the most recent month
   *  that has any records, not to today - a shop opening the sheet on the 1st
   *  wants last month, which is the one they are paying for. */
  const [payMonth, setPayMonth] = useState<string>("");

  /** The person whose history is open, or null. */
  const [openMember, setOpenMember] = useState<WorkspaceTeamMemberPayload | null>(null);
  const [history, setHistory] = useState<MemberHistory>(EMPTY_HISTORY);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState("");

  const t = useT();
  const [staff, setStaff] = useState<WorkspaceTeamMemberPayload[]>(initialTeam ?? []);
  const [attendance, setAttendance] = useState<AttendanceSession[]>(initialSessions ?? []);
  const [summary, setSummary] = useState<AttendanceSummaryPayload>(initialSummary ?? { total_sessions: 0, present_count: 0, leave_count: 0, active_workers_today: 0 });
  const [activeTab, setActiveTab] = useState<TabKey>(defaultTab);
  const [isLoading, setIsLoading] = useState(false);

  const availableMonths = useMemo(() => monthsIn(attendance), [attendance]);
  /** A month is only chosen once: whatever the picker holds, or the newest
   *  month that has records. Defaulting to today would show an empty sheet on
   *  the 1st, which is exactly when the pay is being worked out. */
  const activeMonth = payMonth || availableMonths[0] || "";
  const payRows = useMemo(
    () => paySheet(attendance, activeMonth),
    [attendance, activeMonth],
  );
  const payTotalsRow = useMemo(() => payTotals(payRows), [payRows]);

  /** Hours and day counts read as figures, not as float noise: 7.5 stays 7.5
   *  and 8 does not become 8.00. */
  const formatHours = (value: number): string =>
    Number.isInteger(value) ? String(value) : value.toFixed(1);

  const rate = discountRate(history);

  useEffect(() => {
    if (!openMember) return;
    let active = true;
    const load = async () => {
      setHistoryLoading(true);
      setHistoryError("");
      try {
        const res = await fetch(`/api/team/${openMember.id}/history`);
        const body = await res.json().catch(() => null);
        if (!res.ok) {
          throw new Error(
            (body as { detail?: string })?.detail || "Could not read their history.",
          );
        }
        if (active) setHistory(readMemberHistory(body));
      } catch (err) {
        // Empty figures, not stale ones. Somebody else's month under this
        // person's name is the worst outcome here.
        if (active) {
          setHistory(EMPTY_HISTORY);
          setHistoryError(
            err instanceof Error ? err.message : "Could not read their history.",
          );
        }
      } finally {
        if (active) setHistoryLoading(false);
      }
    };
    void load();
    return () => {
      active = false;
    };
  }, [openMember]);

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
      refreshServerData();
      await refreshData();
      refreshServerData();
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
      refreshServerData();
    } catch (err) {
      say("Could not record that shift", errorMessage(err, "Something went wrong."), "danger");
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
      refreshServerData();
    } catch (err) {
      setSubmitError(errorMessage(err, "Failed to save attendance."));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4">
      {/* One row: the figures, then the two things you actually do here. A
          title card repeating the navbar and four tall tiles pushed the
          people themselves below the fold. */}
      <div className="flex flex-wrap items-center gap-4 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm animate-fade-in-up">
        <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
          {[
            {
              label: "on the team",
              value: String(staff.length),
              detail: `${staff.filter((m) => m.status === "active").length} active`,
              tone: "text-[var(--text-primary)]",
            },
            {
              label: "on shift now",
              value: String(openShifts.length),
              detail:
                openShifts.length === 0
                  ? "nobody clocked in"
                  : openShifts.map((sh) => sh.member_name).join(", "),
              tone:
                openShifts.length > 0
                  ? "text-[var(--success-strong)]"
                  : "text-[var(--text-primary)]",
            },
            {
              label: "present today",
              value: String(summary.active_workers_today),
              detail: `of ${staff.length}`,
              tone: "text-[var(--text-primary)]",
            },
            {
              label: "counter pins",
              value: String(staff.filter((m) => m.has_pos_pin).length),
              detail: "set for a shift change",
              tone: "text-[var(--text-primary)]",
            },
          ].map((stat, index) => (
            <div
              key={stat.label}
              className={`flex shrink-0 flex-col justify-center ${
                index > 0 ? "border-l border-[var(--border-soft)] pl-4" : ""
              }`}
            >
              <dt className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                {stat.label}
              </dt>
              <dd className="m-0 flex items-baseline gap-1.5">
                <span
                  className={`tnum max-w-[200px] truncate font-mono text-[17px] font-bold leading-tight ${stat.tone}`}
                >
                  {stat.value}
                </span>
                <span className="max-w-[190px] truncate whitespace-nowrap text-[11px] font-semibold text-[var(--text-tertiary)]">
                  {stat.detail}
                </span>
              </dd>
            </div>
          ))}
        </dl>

        <div className="flex shrink-0 items-center gap-2">
          <button
            onClick={handleToggleClock}
            disabled={isSubmitting || !myMember}
            title={
              myMember
                ? undefined
                : "You are viewing this shop without a staff membership, so there is no shift to clock."
            }
            className={`focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border px-3.5 py-2 text-[12px] font-bold transition-colors disabled:cursor-not-allowed disabled:opacity-50 ${
              myActiveSession
                ? "border-[var(--error)]/30 bg-[var(--error)]/10 text-[var(--error-strong)] hover:bg-[var(--error)]/16"
                : "border-[var(--success)]/30 bg-[var(--success)]/10 text-[var(--success-dark)] hover:bg-[var(--success)]/16"
            }`}
          >
            {myActiveSession ? <LogOut className="h-4 w-4" /> : <LogIn className="h-4 w-4" />}
            {myActiveSession ? "Clock out" : "Clock in"}
          </button>

          <button
            onClick={() => setIsInviteOpen(true)}
            className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3.5 py-2 text-[12px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20"
          >
            <Plus className="h-4 w-4" />
            Invite
          </button>
        </div>
      </div>

      {/* Who is actually on the counter. The page has always promised shift
          monitoring; until now it showed a roster and left you to guess. */}
      {openShifts.length > 0 && (activeTab === "team" || activeTab === "attendance") && (
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
      {weekRows.length > 0 && activeTab === "attendance" && (
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

      {/* Three questions, kept apart: who may open the shop, who actually
          worked, and which devices are still signed in. They share a table
          but answer opposite things - a PIN is access, attendance is pay. */}
      <div className="flex items-center gap-2 border-b border-[var(--border-soft)]">
        {[
          { key: "team" as TabKey, label: "Staff", count: staff.length },
          { key: "attendance" as TabKey, label: "Attendance", count: attendance.length },
          { key: "pay" as TabKey, label: "Pay sheet", count: null },
          { key: "devices" as TabKey, label: "Devices", count: null },
        ].map((tab) => (
          <button
            key={tab.key}
            type="button"
            onClick={() => setActiveTab(tab.key)}
            aria-pressed={activeTab === tab.key}
            className={`focus-ring cursor-pointer border-b-2 px-3 pb-3 text-xs font-bold transition-colors ${
              activeTab === tab.key
                ? "border-[var(--primary)] text-text-primary"
                : "border-transparent text-[var(--text-tertiary)] hover:text-text-primary"
            }`}
          >
            {tab.label}
            {tab.count !== null && (
              <span className="tnum ml-1.5 font-mono text-[11px] text-[var(--text-tertiary)]">
                {tab.count}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Tab Panels */}
      {activeTab === "team" && (
        <div className="relative flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] shadow-sm">
          {isLoading && (
            <div className="absolute inset-0 bg-surface/50 backdrop-blur-[1px] flex items-center justify-center z-10">
              <Loader2 className="w-6 h-6 text-primary animate-spin" />
            </div>
          )}
          <div className="min-h-0 flex-1 overflow-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-bg-soft border-b border-[var(--border-soft)] text-[var(--text-tertiary)] font-semibold uppercase tracking-wider text-[10px]">
                  <th className="py-3 px-4">Member Name</th>
                  <th className="py-3 px-4">{t("webEmail", "Email")}</th>
                  <th className="py-3 px-4">Role</th>
                  <th className="py-3 px-4">Phone</th>
                  <th className="py-3 px-4">Counter PIN</th>
                  <th className="py-3 px-4">Status</th>
                  <th className="py-3 px-4">Joined</th>
                  <th className="py-3 px-4 text-right">History</th>
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
                        {member.has_pos_pin ? (
                          <span
                            className="rounded-full bg-[var(--success)]/10 px-2 py-0.5 text-[10px] font-bold uppercase text-[var(--success-strong)]"
                            title="A four-digit PIN unlocks the till at a shift change. It is hashed, and it cannot sign anyone in on its own."
                          >
                            Set
                          </span>
                        ) : (
                          <span className="text-[11px] font-semibold text-[var(--text-tertiary)]">
                            Not set
                          </span>
                        )}
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
                      <td className="py-3 px-4 text-right">
                        {/* The question is always about somebody you are
                            already looking at, so it opens from the row. */}
                        <button
                          type="button"
                          onClick={() => setOpenMember(member)}
                          aria-label={`See how ${member.member_name} is doing`}
                          className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-lg border border-[var(--border-soft)] bg-[var(--surface)] px-2.5 py-1.5 text-[11px] font-bold text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)]"
                        >
                          How they are doing
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === "attendance" && (
        <div className="relative flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] shadow-sm">
          {isLoading && (
            <div className="absolute inset-0 bg-surface/50 backdrop-blur-[1px] flex items-center justify-center z-10">
              <Loader2 className="w-6 h-6 text-primary animate-spin" />
            </div>
          )}
          <div className="min-h-0 flex-1 overflow-auto">
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


      {activeTab === "devices" && (
        <div className="overflow-hidden rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] shadow-sm">
          <div className="flex flex-wrap items-center gap-3 border-b border-[var(--border-soft)] px-4 py-3">
            <h3 className="text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
              Devices signed in
            </h3>
            {/* Revoking is a security action and lives behind the MFA gate on
                its own screen. Seeing WHICH devices belong to which person
                belongs here, next to the person. */}
            <a
              href="/sessions"
              className="focus-ring ml-auto text-[11.5px] font-bold text-[var(--primary-hover)] hover:underline"
            >
              Revoke or wipe a device
            </a>
          </div>

          {devices.length === 0 ? (
            <p className="px-4 py-10 text-center text-xs font-bold text-[var(--text-tertiary)]">
              No devices are signed in to this shop.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-left text-xs">
                <thead className="sticky top-0 z-10">
                  <tr className="border-b border-[var(--border-soft)] bg-bg-soft text-[10px] font-semibold uppercase tracking-wider text-[var(--text-tertiary)]">
                    <th className="px-4 py-3">Person</th>
                    <th className="px-4 py-3">Device</th>
                    <th className="px-4 py-3">Last seen</th>
                    <th className="px-4 py-3">Trust</th>
                    <th className="px-4 py-3 text-right">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border-soft)]">
                  {devices.map((device) => (
                    <tr key={device.id} className="hover:bg-[var(--bg-base)]">
                      <td className="px-4 py-3">
                        <span className="block font-bold text-[var(--text-primary)]">
                          {device.member_name || "Unknown"}
                        </span>
                        <span className="block text-[10.5px] text-[var(--text-tertiary)]">
                          {device.role_label}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <span className="block font-semibold text-[var(--text-primary)]">
                          {device.device_label || "Unnamed device"}
                        </span>
                        <span className="block font-mono text-[10.5px] text-[var(--text-tertiary)]">
                          {device.platform_name || "unknown"}
                          {device.app_version ? ` · v${device.app_version}` : ""}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-[var(--text-tertiary)]">
                        {device.last_seen_at ? formatDate(device.last_seen_at) : "never"}
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase ${
                            device.trust_level === "trusted"
                              ? "bg-[var(--success)]/10 text-[var(--success-strong)]"
                              : device.trust_level === "review"
                                ? "bg-[var(--warning)]/10 text-[var(--warning-strong)]"
                                : "bg-[var(--error)]/10 text-[var(--error-strong)]"
                          }`}
                        >
                          {device.trust_level}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-right">
                        <span
                          className={`text-[11px] font-bold ${
                            device.status === "active"
                              ? "text-[var(--success-strong)]"
                              : "text-[var(--text-tertiary)]"
                          }`}
                        >
                          {device.status === "active" ? "Signed in" : "Revoked"}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}


      {activeTab === "pay" && (
        <div className="flex flex-col gap-3.5">
          <div className="flex flex-wrap items-center gap-3 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm">
            <label className="flex items-center gap-2">
              <span className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                Month
              </span>
              <select
                value={activeMonth}
                onChange={(e) => setPayMonth(e.target.value)}
                className="focus-ring cursor-pointer rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 text-[12.5px] font-bold text-[var(--text-secondary)] outline-none"
              >
                {availableMonths.length === 0 && <option value="">No records yet</option>}
                {availableMonths.map((month) => (
                  <option key={month} value={month}>
                    {monthLabel(month)}
                  </option>
                ))}
              </select>
            </label>

            <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
              {[
                { label: "people", value: String(payTotalsRow.people), detail: "with records" },
                { label: "days worked", value: formatHours(payTotalsRow.daysWorked), detail: "half days counted as half" },
                { label: "hours", value: formatHours(payTotalsRow.hours), detail: `${formatHours(payTotalsRow.overtime)} overtime` },
                { label: "bonus", value: formatCurrency(payTotalsRow.bonus), detail: "recorded this month" },
              ].map((stat, index) => (
                <div
                  key={stat.label}
                  className={`flex shrink-0 flex-col justify-center ${
                    index > 0 ? "border-l border-[var(--border-soft)] pl-4" : ""
                  }`}
                >
                  <dt className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                    {stat.label}
                  </dt>
                  <dd className="m-0 flex items-baseline gap-1.5">
                    <span className="tnum font-mono text-[17px] font-bold leading-tight text-[var(--text-primary)]">
                      {stat.value}
                    </span>
                    <span className="whitespace-nowrap text-[11px] font-semibold text-[var(--text-tertiary)]">
                      {stat.detail}
                    </span>
                  </dd>
                </div>
              ))}
            </dl>
          </div>

          <div className="overflow-hidden rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] shadow-sm">
            {payRows.length === 0 ? (
              <p className="px-4 py-12 text-center text-xs font-bold text-[var(--text-tertiary)]">
                No attendance recorded for this month.
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full border-collapse text-left text-xs">
                  <thead>
                    <tr className="border-b border-[var(--border-soft)] bg-bg-soft text-[10px] font-semibold uppercase tracking-wider text-[var(--text-tertiary)]">
                      <th className="px-4 py-3">Person</th>
                      <th className="px-4 py-3 text-right">Days worked</th>
                      <th className="px-4 py-3 text-right">Present</th>
                      <th className="px-4 py-3 text-right">Half</th>
                      <th className="px-4 py-3 text-right">Leave</th>
                      <th className="px-4 py-3 text-right">Absent</th>
                      <th className="px-4 py-3 text-right">Hours</th>
                      <th className="px-4 py-3 text-right">Overtime</th>
                      <th className="px-4 py-3 text-right">Bonus</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[var(--border-soft)]">
                    {payRows.map((line) => (
                      <tr key={line.membershipId} className="hover:bg-[var(--bg-base)]">
                        <td className="px-4 py-3">
                          <span className="block font-bold text-[var(--text-primary)]">
                            {line.name}
                          </span>
                          <span className="block text-[10.5px] capitalize text-[var(--text-tertiary)]">
                            {line.role.replace(/_/g, " ")}
                          </span>
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono font-bold text-[var(--text-primary)]">
                          {formatHours(line.daysWorked)}
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono text-[var(--text-secondary)]">
                          {line.present}
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono text-[var(--text-secondary)]">
                          {line.halfDays}
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono text-[var(--text-secondary)]">
                          {line.leave}
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono text-[var(--text-tertiary)]">
                          {line.absent}
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono text-[var(--text-primary)]">
                          {formatHours(line.hours)}
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono text-[var(--warning-strong)]">
                          {formatHours(line.overtime)}
                        </td>
                        <td className="tnum px-4 py-3 text-right font-mono font-bold text-[var(--text-primary)]">
                          {formatCurrency(line.bonus)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Said plainly, because the number people want is not here. */}
          <p className="m-0 text-[11px] font-medium text-[var(--text-tertiary)]">
            These are the hours and bonuses actually recorded. No wage rate is
            stored anywhere in the app, so no pay figure is calculated - this
            is what the person working out the pay should start from.
          </p>
        </div>
      )}


      {/* One person, across the three tables that know about them. Opened
          from a row rather than living on a screen of its own: the question
          is always about somebody you are already looking at. */}
      {openMember && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
          onClick={() => setOpenMember(null)}
        >
          <div
            className="animate-fade-in-up flex max-h-[85vh] w-full max-w-2xl flex-col overflow-hidden rounded-2xl border border-[var(--border)] bg-[var(--surface)] shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex shrink-0 items-center gap-3 border-b border-[var(--border-soft)] px-5 py-4">
              <div className="min-w-0">
                <p className="m-0 truncate text-sm font-extrabold tracking-tight text-[var(--text-primary)]">
                  {history.name || openMember.member_name}
                </p>
                <p className="m-0 text-[11.5px] font-semibold text-[var(--text-tertiary)]">
                  {formatRole(openMember.role)} &middot; last 30 days
                </p>
              </div>
              <button
                onClick={() => setOpenMember(null)}
                aria-label="Close"
                className="focus-ring ml-auto cursor-pointer rounded-lg p-1 text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto p-5">
              {historyLoading ? (
                <p className="py-12 text-center text-xs font-bold text-[var(--text-tertiary)]">
                  Reading their month...
                </p>
              ) : historyError ? (
                <p
                  role="alert"
                  className="rounded-xl border border-[var(--error)]/40 bg-[var(--error)]/10 px-4 py-3 text-xs font-bold text-[var(--error-strong)]"
                >
                  {historyError}
                </p>
              ) : (
                <div className="flex flex-col gap-4">
                  <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-4">
                    {[
                      {
                        label: "days worked",
                        value: formatHours(history.daysWorked),
                        detail: `${history.present} full, ${history.halfDays} half`,
                      },
                      {
                        label: "hours",
                        value: formatHours(history.hours),
                        detail: `${formatHours(history.overtime)} overtime`,
                      },
                      {
                        label: "bills rung up",
                        value: String(history.bills),
                        detail:
                          history.averageBill === null
                            ? "none yet"
                            : `avg ${formatCurrency(history.averageBill)}`,
                      },
                      {
                        label: "sold",
                        value: formatCurrency(history.gross),
                        detail:
                          history.perDayWorked === null
                            ? "no day worked"
                            : `${formatCurrency(history.perDayWorked)} a day`,
                      },
                    ].map((stat) => (
                      <div
                        key={stat.label}
                        className="rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-3"
                      >
                        <p className="m-0 font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                          {stat.label}
                        </p>
                        <p className="tnum m-0 mt-1 font-mono text-[17px] font-bold leading-tight text-[var(--text-primary)]">
                          {stat.value}
                        </p>
                        <p className="m-0 mt-0.5 truncate text-[10.5px] font-semibold text-[var(--text-tertiary)]">
                          {stat.detail}
                        </p>
                      </div>
                    ))}
                  </div>

                  <div className="flex flex-wrap items-center gap-2.5 rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-3">
                    <span className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                      Discount given
                    </span>
                    <span className="tnum font-mono text-[15px] font-bold text-[var(--warning-strong)]">
                      {formatCurrency(history.discountGiven)}
                    </span>
                    {/* The rupee total alone compares nobody: a busy cashier
                        always gives away more than a quiet one. */}
                    <span className="text-[11.5px] font-semibold text-[var(--text-tertiary)]">
                      {rate === null
                        ? "nothing sold to compare against"
                        : `${rate.toFixed(1)}% of what they sold`}
                    </span>
                    {history.bonus > 0 && (
                      <span className="ml-auto text-[11.5px] font-bold text-[var(--text-secondary)]">
                        Bonus {formatCurrency(history.bonus)}
                      </span>
                    )}
                  </div>

                  <div className="overflow-hidden rounded-[12px] border border-[var(--border-soft)]">
                    <table className="w-full border-collapse text-left text-xs">
                      <thead>
                        <tr className="border-b border-[var(--border-soft)] bg-bg-soft text-[10px] font-semibold uppercase tracking-wider text-[var(--text-tertiary)]">
                          <th className="px-3 py-2">Day</th>
                          <th className="px-3 py-2">Marked</th>
                          <th className="px-3 py-2 text-right">Hours</th>
                          <th className="px-3 py-2 text-right">Overtime</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-[var(--border-soft)]">
                        {history.sessions.length === 0 ? (
                          <tr>
                            <td
                              colSpan={4}
                              className="px-3 py-8 text-center text-[var(--text-tertiary)]"
                            >
                              No attendance recorded in this window.
                            </td>
                          </tr>
                        ) : (
                          history.sessions.map((session) => (
                            <tr key={session.id}>
                              <td className="px-3 py-2 font-semibold text-[var(--text-primary)]">
                                {formatDate(session.date)}
                              </td>
                              <td className="px-3 py-2 capitalize text-[var(--text-secondary)]">
                                {session.status.replace(/_/g, " ").toLowerCase()}
                              </td>
                              <td className="tnum px-3 py-2 text-right font-mono text-[var(--text-primary)]">
                                {session.hours ?? "--"}
                              </td>
                              <td className="tnum px-3 py-2 text-right font-mono text-[var(--warning-strong)]">
                                {session.overtime}
                              </td>
                            </tr>
                          ))
                        )}
                      </tbody>
                    </table>
                  </div>

                  <p className="m-0 text-[11px] font-medium text-[var(--text-tertiary)]">
                    Sales are credited to whoever was signed in when the bill
                    was rung up. Where a shop shares one login they all land on
                    that one person, which is the honest answer rather than a
                    split invented to look fair.
                  </p>
                </div>
              )}
            </div>
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
