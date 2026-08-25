/** A month's attendance, per person.
 *
 *  Every field this needs was already being recorded per day - hours worked,
 *  overtime, a bonus, whether it was a full day, a half day or leave - and
 *  nothing ever added them up. The screen showed a list of days and left the
 *  arithmetic to whoever was doing the pay, on paper, once a month.
 *
 *  This does not calculate pay. It cannot: no wage rate is stored anywhere in
 *  the product. What it does is total the things that ARE recorded, so the
 *  person working out the pay starts from figures the system stands behind
 *  rather than from a pile of rows.
 */

export type AttendanceRow = {
  membership_id: string;
  member_name: string;
  member_role: string;
  session_date: string;
  status: "PRESENT" | "ABSENT" | "HALF_DAY" | "LEAVE";
  total_hours: string | null;
  overtime_hours: string;
  bonus_amount: string;
};

export type PayRow = {
  membershipId: string;
  name: string;
  role: string;
  present: number;
  halfDays: number;
  leave: number;
  absent: number;
  /** Full days equivalent: a half day counts as half. */
  daysWorked: number;
  hours: number;
  overtime: number;
  bonus: number;
};

function toNumber(value: string | number | null | undefined): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

/** YYYY-MM for a date string, or "" when it is not a date. */
export function monthOf(sessionDate: string): string {
  return /^\d{4}-\d{2}-\d{2}$/.test(sessionDate) ? sessionDate.slice(0, 7) : "";
}

/** Every month present in these rows, newest first. */
export function monthsIn(rows: AttendanceRow[]): string[] {
  const months = new Set<string>();
  for (const row of rows) {
    const month = monthOf(row.session_date);
    if (month) months.add(month);
  }
  return [...months].sort().reverse();
}

/** Total one month, one line per person, busiest first.
 *
 *  Absent and leave days are counted but contribute no hours - a leave day
 *  with hours recorded against it is a data entry mistake, not overtime, and
 *  silently adding it would inflate somebody's month.
 */
export function paySheet(rows: AttendanceRow[], month: string): PayRow[] {
  const byPerson = new Map<string, PayRow>();

  for (const row of rows) {
    if (month && monthOf(row.session_date) !== month) continue;

    const existing = byPerson.get(row.membership_id) ?? {
      membershipId: row.membership_id,
      name: row.member_name || "Unknown",
      role: row.member_role || "",
      present: 0,
      halfDays: 0,
      leave: 0,
      absent: 0,
      daysWorked: 0,
      hours: 0,
      overtime: 0,
      bonus: 0,
    };

    if (row.status === "PRESENT") {
      existing.present += 1;
      existing.daysWorked += 1;
    } else if (row.status === "HALF_DAY") {
      existing.halfDays += 1;
      existing.daysWorked += 0.5;
    } else if (row.status === "LEAVE") {
      existing.leave += 1;
    } else {
      existing.absent += 1;
    }

    // Hours only count on a day actually worked.
    if (row.status === "PRESENT" || row.status === "HALF_DAY") {
      existing.hours += toNumber(row.total_hours);
      existing.overtime += toNumber(row.overtime_hours);
    }
    // A bonus is paid whatever the day was marked.
    existing.bonus += toNumber(row.bonus_amount);

    byPerson.set(row.membership_id, existing);
  }

  return [...byPerson.values()].sort(
    (a, b) => b.daysWorked - a.daysWorked || a.name.localeCompare(b.name),
  );
}

/** The month's totals across everyone, for the strip above the table. */
export function payTotals(rows: PayRow[]) {
  return rows.reduce(
    (sum, row) => ({
      people: sum.people + 1,
      daysWorked: sum.daysWorked + row.daysWorked,
      hours: sum.hours + row.hours,
      overtime: sum.overtime + row.overtime,
      bonus: sum.bonus + row.bonus,
    }),
    { people: 0, daysWorked: 0, hours: 0, overtime: 0, bonus: 0 },
  );
}

/** "August 2026" from "2026-08". */
export function monthLabel(month: string): string {
  const [year, monthNumber] = month.split("-").map(Number);
  if (!year || !monthNumber || monthNumber < 1 || monthNumber > 12) return month;
  const names = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  return `${names[monthNumber - 1]} ${year}`;
}
