import { describe, expect, it } from "vitest";

import {
  monthLabel,
  monthOf,
  monthsIn,
  paySheet,
  payTotals,
  type AttendanceRow,
} from "./pay-sheet";

const row = (over: Partial<AttendanceRow> = {}): AttendanceRow => ({
  membership_id: "m1",
  member_name: "Asha",
  member_role: "Cashier",
  session_date: "2026-08-03",
  status: "PRESENT",
  total_hours: "8",
  overtime_hours: "0",
  bonus_amount: "0",
  ...over,
});

describe("monthOf", () => {
  it("takes the month from a date", () => {
    expect(monthOf("2026-08-03")).toBe("2026-08");
  });

  it("is empty for anything that is not a date", () => {
    expect(monthOf("")).toBe("");
    expect(monthOf("03/08/2026")).toBe("");
  });
});

describe("monthsIn", () => {
  it("lists each month once, newest first", () => {
    const months = monthsIn([
      row({ session_date: "2026-07-01" }),
      row({ session_date: "2026-08-03" }),
      row({ session_date: "2026-08-04" }),
    ]);
    expect(months).toEqual(["2026-08", "2026-07"]);
  });

  it("ignores unusable dates rather than inventing a month", () => {
    expect(monthsIn([row({ session_date: "rubbish" })])).toEqual([]);
  });
});

describe("paySheet", () => {
  it("counts a full day and a half day correctly", () => {
    const [line] = paySheet(
      [
        row({ session_date: "2026-08-01" }),
        row({ session_date: "2026-08-02", status: "HALF_DAY", total_hours: "4" }),
      ],
      "2026-08",
    );
    expect(line.present).toBe(1);
    expect(line.halfDays).toBe(1);
    expect(line.daysWorked).toBe(1.5);
    expect(line.hours).toBe(12);
  });

  it("counts leave and absence without adding hours", () => {
    const [line] = paySheet(
      [
        row({ session_date: "2026-08-01", status: "LEAVE", total_hours: "8" }),
        row({ session_date: "2026-08-02", status: "ABSENT", total_hours: "8" }),
      ],
      "2026-08",
    );
    // Hours recorded against a leave day are a data-entry mistake, not
    // overtime. Adding them would inflate somebody's month.
    expect(line.hours).toBe(0);
    expect(line.leave).toBe(1);
    expect(line.absent).toBe(1);
    expect(line.daysWorked).toBe(0);
  });

  it("pays a bonus whatever the day was marked", () => {
    const [line] = paySheet(
      [row({ status: "LEAVE", bonus_amount: "500" })],
      "2026-08",
    );
    expect(line.bonus).toBe(500);
  });

  it("keeps people apart and puts the busiest first", () => {
    const sheet = paySheet(
      [
        row({ membership_id: "m1", member_name: "Asha" }),
        row({ membership_id: "m2", member_name: "Bilal", session_date: "2026-08-02" }),
        row({ membership_id: "m2", member_name: "Bilal", session_date: "2026-08-03" }),
      ],
      "2026-08",
    );
    expect(sheet.map((line) => line.name)).toEqual(["Bilal", "Asha"]);
  });

  it("excludes other months entirely", () => {
    const sheet = paySheet(
      [row({ session_date: "2026-07-30" }), row({ session_date: "2026-08-01" })],
      "2026-08",
    );
    expect(sheet[0].daysWorked).toBe(1);
  });

  it("sums overtime only for days worked", () => {
    const [line] = paySheet(
      [
        row({ overtime_hours: "2" }),
        row({ session_date: "2026-08-02", status: "ABSENT", overtime_hours: "3" }),
      ],
      "2026-08",
    );
    expect(line.overtime).toBe(2);
  });

  it("treats unreadable figures as zero rather than NaN", () => {
    const [line] = paySheet([row({ total_hours: null, bonus_amount: "" })], "2026-08");
    expect(line.hours).toBe(0);
    expect(line.bonus).toBe(0);
  });

  it("returns nothing for a month with no rows", () => {
    expect(paySheet([row()], "2026-01")).toEqual([]);
  });
});

describe("payTotals", () => {
  it("adds the month up across everyone", () => {
    const sheet = paySheet(
      [
        row({ membership_id: "m1", overtime_hours: "1", bonus_amount: "100" }),
        row({ membership_id: "m2", member_name: "Bilal", bonus_amount: "50" }),
      ],
      "2026-08",
    );
    const totals = payTotals(sheet);
    expect(totals.people).toBe(2);
    expect(totals.daysWorked).toBe(2);
    expect(totals.hours).toBe(16);
    expect(totals.overtime).toBe(1);
    expect(totals.bonus).toBe(150);
  });

  it("is all zeros for an empty sheet", () => {
    expect(payTotals([])).toEqual({
      people: 0,
      daysWorked: 0,
      hours: 0,
      overtime: 0,
      bonus: 0,
    });
  });
});

describe("monthLabel", () => {
  it("reads as a person says it", () => {
    expect(monthLabel("2026-08")).toBe("August 2026");
  });

  it("returns the raw value rather than inventing a month", () => {
    expect(monthLabel("2026-13")).toBe("2026-13");
    expect(monthLabel("nonsense")).toBe("nonsense");
  });
});
