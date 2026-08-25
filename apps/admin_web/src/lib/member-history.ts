/** Reading one person's history payload.
 *
 *  Kept out of the component so the awkward parts are pinned by tests: a
 *  figure that is genuinely unknown must stay unknown rather than becoming a
 *  confident zero, because these numbers are how somebody gets judged.
 */

export type MemberHistory = {
  membershipId: string;
  name: string;
  role: string;
  hasPin: boolean;
  from: string;
  to: string;
  present: number;
  halfDays: number;
  leave: number;
  absent: number;
  daysWorked: number;
  hours: number;
  overtime: number;
  bonus: number;
  bills: number;
  gross: number;
  collected: number;
  discountGiven: number;
  /** Null when they rang nothing up. An average of no bills is not zero. */
  averageBill: number | null;
  /** Null when no day was worked. */
  perDayWorked: number | null;
  sessions: {
    id: string;
    date: string;
    status: string;
    hours: string | null;
    overtime: string;
    bonus: string;
    note: string;
  }[];
};

function toNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

/** A figure that may legitimately be absent. Zero is a claim; null is not. */
function toNullableNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export const EMPTY_HISTORY: MemberHistory = {
  membershipId: "",
  name: "",
  role: "",
  hasPin: false,
  from: "",
  to: "",
  present: 0,
  halfDays: 0,
  leave: 0,
  absent: 0,
  daysWorked: 0,
  hours: 0,
  overtime: 0,
  bonus: 0,
  bills: 0,
  gross: 0,
  collected: 0,
  discountGiven: 0,
  averageBill: null,
  perDayWorked: null,
  sessions: [],
};

export function readMemberHistory(payload: unknown): MemberHistory {
  const body = (payload ?? {}) as Record<string, unknown>;
  const attendance = (body.attendance ?? {}) as Record<string, unknown>;
  const sales = (body.sales ?? {}) as Record<string, unknown>;
  const sessions = Array.isArray(body.recent_sessions) ? body.recent_sessions : [];

  return {
    membershipId: typeof body.membership_id === "string" ? body.membership_id : "",
    name: typeof body.member_name === "string" ? body.member_name : "",
    role: typeof body.role === "string" ? body.role : "",
    hasPin: body.has_pos_pin === true,
    from: typeof body.from === "string" ? body.from : "",
    to: typeof body.to === "string" ? body.to : "",
    present: toNumber(attendance.present),
    halfDays: toNumber(attendance.half_days),
    leave: toNumber(attendance.leave),
    absent: toNumber(attendance.absent),
    daysWorked: toNumber(attendance.days_worked),
    hours: toNumber(attendance.hours),
    overtime: toNumber(attendance.overtime),
    bonus: toNumber(attendance.bonus),
    bills: toNumber(sales.bills),
    gross: toNumber(sales.gross),
    collected: toNumber(sales.collected),
    discountGiven: toNumber(sales.discount_given),
    averageBill: toNullableNumber(sales.average_bill),
    perDayWorked: toNullableNumber(sales.per_day_worked),
    sessions: sessions.map((row) => {
      const session = (row ?? {}) as Record<string, unknown>;
      return {
        id: typeof session.id === "string" ? session.id : "",
        date: typeof session.session_date === "string" ? session.session_date : "",
        status: typeof session.status === "string" ? session.status : "ABSENT",
        hours: typeof session.total_hours === "string" ? session.total_hours : null,
        overtime: String(session.overtime_hours ?? "0"),
        bonus: String(session.bonus_amount ?? "0"),
        note: typeof session.note === "string" ? session.note : "",
      };
    }),
  };
}

/** Discount as a share of what they sold, or null when they sold nothing.
 *
 *  This is the figure a shopkeeper actually watches: a rupee total means
 *  nothing without the sales behind it, and a busy cashier will always give
 *  away more than a quiet one.
 */
export function discountRate(history: MemberHistory): number | null {
  if (history.gross <= 0) return null;
  return (history.discountGiven / history.gross) * 100;
}
