import { describe, expect, it } from "vitest";

import { isInWeek, summariseWeek, weekStart } from "./attendance-week";
import type { AttendanceSession } from "./types";

let n = 0;
function session(overrides: Partial<AttendanceSession> = {}): AttendanceSession {
  n += 1;
  return {
    id: `s-${n}`,
    membership_id: "m-1",
    member_name: "Sunita R",
    member_role: "staff",
    session_date: "2026-08-19",
    clock_in_at: "2026-08-19T04:00:00Z",
    clock_out_at: "2026-08-19T12:00:00Z",
    status: "PRESENT",
    total_hours: "8.00",
    overtime_hours: "0.00",
    bonus_amount: "0.00",
    note: "",
    tombstone: false,
    ...overrides,
  } as AttendanceSession;
}

describe("the week a day belongs to", () => {
  it("starts on Monday, the way wages are reckoned", () => {
    // 19 Aug 2026 is a Wednesday.
    expect(weekStart("2026-08-19")).toBe("2026-08-17");
  });

  it("keeps Monday itself as the start", () => {
    expect(weekStart("2026-08-17")).toBe("2026-08-17");
  });

  it("puts Sunday at the END of its week, not the start of the next", () => {
    // 23 Aug 2026 is a Sunday; it belongs with the Monday before it.
    expect(weekStart("2026-08-23")).toBe("2026-08-17");
  });

  it("rolls over on the following Monday", () => {
    expect(weekStart("2026-08-24")).toBe("2026-08-24");
  });

  it("groups two days of the same week together", () => {
    expect(isInWeek("2026-08-17", "2026-08-23")).toBe(true);
    expect(isInWeek("2026-08-24", "2026-08-23")).toBe(false);
  });
});

describe("the weekly timesheet", () => {
  const ref = "2026-08-19";

  it("adds up hours and days across the week", () => {
    const rows = summariseWeek(
      [
        session({ session_date: "2026-08-17", total_hours: "8.00" }),
        session({ session_date: "2026-08-18", total_hours: "7.50" }),
      ],
      ref,
    );
    expect(rows[0]).toMatchObject({ daysPresent: 2, hours: 15.5 });
  });

  it("leaves last week out of this week", () => {
    const rows = summariseWeek(
      [
        session({ session_date: "2026-08-19", total_hours: "8.00" }),
        session({ session_date: "2026-08-12", total_hours: "40.00" }),
      ],
      ref,
    );
    expect(rows[0].hours).toBe(8);
  });

  it("does not pay for a day marked absent", () => {
    const rows = summariseWeek(
      [session({ status: "ABSENT", total_hours: "8.00" })],
      ref,
    );
    expect(rows[0]).toMatchObject({ daysPresent: 0, hours: 0 });
  });

  it("counts a half day as a day present", () => {
    const rows = summariseWeek(
      [session({ status: "HALF_DAY", total_hours: "4.00" })],
      ref,
    );
    expect(rows[0]).toMatchObject({ daysPresent: 1, hours: 4 });
  });

  it("counts one day once, however many sessions it holds", () => {
    const rows = summariseWeek(
      [
        session({ session_date: "2026-08-19", total_hours: "4.00" }),
        session({ session_date: "2026-08-19", total_hours: "4.00" }),
      ],
      ref,
    );
    expect(rows[0]).toMatchObject({ daysPresent: 1, hours: 8 });
  });

  it("flags anyone still clocked in", () => {
    const rows = summariseWeek([session({ clock_out_at: null })], ref);
    expect(rows[0].onShift).toBe(true);
  });

  it("ignores deleted sessions", () => {
    expect(summariseWeek([session({ tombstone: true })], ref)).toEqual([]);
  });

  it("treats a missing total as zero rather than NaN", () => {
    const rows = summariseWeek([session({ total_hours: null })], ref);
    expect(rows[0].hours).toBe(0);
  });

  it("puts the longest week first", () => {
    const rows = summariseWeek(
      [
        session({ membership_id: "m-1", member_name: "A", total_hours: "6.00" }),
        session({ membership_id: "m-2", member_name: "B", total_hours: "9.00" }),
      ],
      ref,
    );
    expect(rows.map((r) => r.name)).toEqual(["B", "A"]);
  });
});
