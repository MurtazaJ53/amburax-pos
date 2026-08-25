/** The periods a shopkeeper actually asks about, and the maths behind them.
 *
 *  The dashboard only ever knew "today". Every other question — how was last
 *  month, how does this quarter compare, what did the year do — meant reading
 *  the sales list by eye.
 *
 *  All of it is done in the SHOP's calendar, not the browser's and not UTC. A
 *  shop in Kolkata closing at 11pm must not have its takings land on the next
 *  day because a server in another timezone said so.
 */

export type RangeKey =
  | "today"
  | "yesterday"
  | "last7"
  | "last30"
  | "last90"
  | "last180"
  | "last365"
  | "all"
  | "custom";

/** How the series should be bucketed. A year of daily bars is unreadable. */
export type Granularity = "hour" | "day" | "month";

export type DateRange = {
  /** Inclusive, YYYY-MM-DD in the shop's calendar. */
  from: string;
  /** Inclusive, YYYY-MM-DD in the shop's calendar. */
  to: string;
};

export type ResolvedRange = DateRange & {
  key: RangeKey;
  label: string;
  granularity: Granularity;
  /** How the comparison chip should read, e.g. "vs yesterday". */
  comparisonLabel: string;
  /** True when the window has no start date - "all time". `from` is empty,
   *  and callers must omit it rather than sending "" as a date. */
  unbounded: boolean;
};

export const RANGE_OPTIONS: { key: RangeKey; label: string }[] = [
  { key: "today", label: "Today" },
  { key: "yesterday", label: "Yesterday" },
  { key: "last7", label: "Last 7 days" },
  { key: "last30", label: "Last 30 days" },
  { key: "last90", label: "Last 3 months" },
  { key: "last180", label: "Last 6 months" },
  { key: "last365", label: "Last 12 months" },
  { key: "all", label: "All time" },
  { key: "custom", label: "Custom dates" },
];

/** Today in the shop's timezone as YYYY-MM-DD.
 *
 *  en-CA is used because it formats as YYYY-MM-DD, which is both the wire
 *  format and sortable as a string. Building it from getFullYear/getMonth
 *  would read the BROWSER's calendar, which is the bug this avoids.
 */
export function shopToday(timeZone: string, now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/** Shift a YYYY-MM-DD by whole days, staying on the calendar.
 *
 *  Done in UTC on purpose: a plain local Date crossing a daylight-saving
 *  boundary can land on the same day twice or skip one entirely.
 */
export function shiftDate(date: string, days: number): string {
  const [year, month, day] = date.split("-").map(Number);
  const shifted = new Date(Date.UTC(year, month - 1, day));
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}

/** Whole days from `from` to `to`, inclusive of both ends. */
export function daysInRange(range: DateRange): number {
  const start = Date.parse(`${range.from}T00:00:00Z`);
  const end = Date.parse(`${range.to}T00:00:00Z`);
  if (!Number.isFinite(start) || !Number.isFinite(end)) return 0;
  return Math.floor((end - start) / 86_400_000) + 1;
}

/** Bars a person can actually read for a window of this length. */
export function granularityFor(range: DateRange): Granularity {
  const days = daysInRange(range);
  if (days <= 1) return "hour";
  if (days <= 92) return "day";
  return "month";
}

/** Turn a chosen preset into real dates.
 *
 *  Every "last N" window ENDS today and includes it. A shopkeeper asking for
 *  the last 30 days means the last 30 days of trading up to and including
 *  this one, not a window that stops at midnight last night.
 */
export function resolveRange(
  key: RangeKey,
  today: string,
  custom?: Partial<DateRange>,
): ResolvedRange {
  const build = (from: string, to: string, label: string, comparisonLabel: string) => ({
    key,
    from,
    to,
    label,
    comparisonLabel,
    unbounded: false,
    granularity: granularityFor({ from, to }),
  });

  switch (key) {
    case "yesterday": {
      const day = shiftDate(today, -1);
      return build(day, day, "Yesterday", "vs the day before");
    }
    case "last7":
      return build(shiftDate(today, -6), today, "Last 7 days", "vs the 7 days before");
    case "last30":
      return build(shiftDate(today, -29), today, "Last 30 days", "vs the 30 days before");
    case "last90":
      return build(shiftDate(today, -89), today, "Last 3 months", "vs the 3 months before");
    case "last180":
      return build(shiftDate(today, -179), today, "Last 6 months", "vs the 6 months before");
    case "last365":
      return build(shiftDate(today, -364), today, "Last 12 months", "vs the year before");
    case "all":
      // No start date. There is nothing before all of history, so no
      // comparison is offered rather than one being invented.
      return {
        key,
        from: "",
        to: today,
        label: "All time",
        comparisonLabel: "",
        unbounded: true,
        granularity: "month" as Granularity,
      };
    case "custom": {
      // A half-filled custom range must not silently become something else.
      // Falling back to today keeps the screen honest until both ends are set.
      const from = custom?.from || today;
      const to = custom?.to || today;
      // Dates entered the wrong way round are swapped rather than refused: it
      // is obvious what was meant, and an error would be pedantry.
      const [start, end] = from <= to ? [from, to] : [to, from];
      return build(start, end, "Custom dates", "vs the period before");
    }
    case "today":
    default:
      return build(today, today, "Today", "vs yesterday");
  }
}

/** The equally-long window immediately before this one.
 *
 *  Equal length matters: comparing a 30-day month against a 31-day one
 *  manufactures a change that did not happen.
 */
export function previousPeriod(range: DateRange): DateRange {
  const length = daysInRange(range);
  const to = shiftDate(range.from, -1);
  return { from: shiftDate(to, -(length - 1)), to };
}

/** Is this range usable as typed? */
export function isValidRange(range: Partial<DateRange>): boolean {
  const pattern = /^\d{4}-\d{2}-\d{2}$/;
  if (!range.from || !range.to) return false;
  if (!pattern.test(range.from) || !pattern.test(range.to)) return false;
  return Number.isFinite(Date.parse(`${range.from}T00:00:00Z`));
}

/** A resolved window as the report APIs want it.
 *
 *  Built once by whichever screen owns the picker and handed down, so every
 *  panel on that screen is answering about the same period.
 */
export type ReportWindow = {
  /** Query string for the API: a bounded window, or all of history. */
  query: string;
  /** The equally-long window before it, for comparisons. Empty when there is
   *  nothing before - there is no period before all of history. */
  previousQuery: string;
  label: string;
};

/** Turn a resolved range into the query the report APIs understand. */
export function toReportWindow(range: ResolvedRange): ReportWindow {
  if (range.unbounded) {
    return { query: "all=1", previousQuery: "", label: range.label };
  }
  const previous = previousPeriod(range);
  return {
    query: `date_from=${range.from}&date_to=${range.to}`,
    previousQuery: `date_from=${previous.from}&date_to=${previous.to}`,
    label: range.label,
  };
}
