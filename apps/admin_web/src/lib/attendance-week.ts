import type { AttendanceSession } from "@/lib/types";

/** The timesheet behind wages: who worked, how long, how much of it was overtime.
 *
 *  Sessions arrive one row per person per day. What a shopkeeper actually
 *  needs before paying anyone is the week, so the rolling-up happens here
 *  where it can be tested — week boundaries and half-days are easy to get
 *  quietly wrong, and the number decides what someone is paid.
 */

export type WeekRow = {
  membershipId: string;
  name: string;
  role: string;
  /** Days with any attendance recorded, half days included. */
  daysPresent: number;
  hours: number;
  overtime: number;
  /** True while a session for this person has no clock-out. */
  onShift: boolean;
};

function toNumber(value: string | null | undefined): number {
  if (value === null || value === undefined || value === "") return 0;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

/**
 * The Monday of the week a date falls in, as YYYY-MM-DD.
 *
 * Monday rather than Sunday because that is how an Indian shop's week is
 * counted and how wages are reckoned.
 */
export function weekStart(dateKey: string): string {
  const [year, month, day] = dateKey.split("-").map(Number);
  const date = new Date(Date.UTC(year, (month ?? 1) - 1, day ?? 1));
  // getUTCDay: 0 is Sunday, so Sunday sits at the END of the week, six days
  // after its Monday.
  const weekday = date.getUTCDay();
  const backToMonday = weekday === 0 ? 6 : weekday - 1;
  date.setUTCDate(date.getUTCDate() - backToMonday);
  return date.toISOString().slice(0, 10);
}

/** Whether a session belongs to the week containing `reference`. */
export function isInWeek(sessionDate: string, reference: string): boolean {
  return weekStart(sessionDate) === weekStart(reference);
}

/**
 * One row per person who has any session in the reference week, ordered by
 * hours worked so the longest shifts are read first.
 */
export function summariseWeek(
  sessions: AttendanceSession[],
  reference: string,
): WeekRow[] {
  const rows = new Map<string, WeekRow & { days: Set<string> }>();

  for (const session of sessions) {
    if (session.tombstone) continue;
    if (!session.session_date || !isInWeek(session.session_date, reference)) continue;
    // ABSENT and LEAVE are recorded days, but nobody stood at the counter for
    // them, so they must not count toward days present or hours.
    const worked = session.status === "PRESENT" || session.status === "HALF_DAY";

    const row = rows.get(session.membership_id) ?? {
      membershipId: session.membership_id,
      name: session.member_name,
      role: session.member_role,
      daysPresent: 0,
      hours: 0,
      overtime: 0,
      onShift: false,
      days: new Set<string>(),
    };

    if (worked) {
      row.days.add(session.session_date);
      row.hours += toNumber(session.total_hours);
      row.overtime += toNumber(session.overtime_hours);
    }
    if (session.clock_in_at && !session.clock_out_at) {
      row.onShift = true;
    }
    rows.set(session.membership_id, row);
  }

  return [...rows.values()]
    .map(({ days, ...row }) => ({ ...row, daysPresent: days.size }))
    .sort((a, b) => b.hours - a.hours);
}
