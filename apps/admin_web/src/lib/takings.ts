/** Reading the takings payload, and the small decisions the panel needs.
 *
 *  Kept out of the component so the parsing and the labelling can be tested:
 *  these figures are what a shopkeeper judges the business by, and a chart
 *  axis that mislabels a month is worse than no chart.
 */

import type { Granularity } from "./date-ranges";

export type TakingsPoint = { label: string; amount: number };
export type TakingsSlice = { key: string; label: string; amount: number };

export type Takings = {
  from: string;
  to: string;
  days: number;
  total: number;
  billCount: number;
  averageBill: number;
  previousTotal: number;
  granularity: Granularity;
  series: TakingsPoint[];
  mix: TakingsSlice[];
};

const MONTHS = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

function toNumber(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export const EMPTY_TAKINGS: Takings = {
  from: "",
  to: "",
  days: 0,
  total: 0,
  billCount: 0,
  averageBill: 0,
  previousTotal: 0,
  granularity: "hour",
  series: [],
  mix: [],
};

/** Parse the API response, tolerating anything that is not one.
 *
 *  A malformed payload yields empty figures rather than partial ones: a
 *  headline total with a series that failed to parse is a chart that
 *  contradicts the number above it.
 */
export function readTakings(payload: unknown): Takings {
  const body = (payload ?? {}) as Record<string, unknown>;
  const series = Array.isArray(body.series) ? body.series : [];
  const mix = Array.isArray(body.mix) ? body.mix : [];

  return {
    from: typeof body.from === "string" ? body.from : "",
    to: typeof body.to === "string" ? body.to : "",
    days: toNumber(body.days),
    total: toNumber(body.total),
    billCount: toNumber(body.bill_count),
    averageBill: toNumber(body.average_bill),
    previousTotal: toNumber(body.previous_total),
    granularity:
      body.granularity === "day" || body.granularity === "month"
        ? body.granularity
        : "hour",
    series: series
      .map((point) => {
        const row = (point ?? {}) as Record<string, unknown>;
        return {
          label: typeof row.label === "string" ? row.label : "",
          amount: toNumber(row.amount),
        };
      })
      .filter((point) => point.label !== ""),
    mix: mix
      .map((slice) => {
        const row = (slice ?? {}) as Record<string, unknown>;
        return {
          key: typeof row.key === "string" ? row.key : "OTHER",
          label: typeof row.label === "string" ? row.label : "Other",
          amount: toNumber(row.amount),
        };
      })
      .filter((slice) => slice.amount > 0),
  };
}

/** A series label as a person reads it, given how the window is bucketed. */
export function axisLabel(label: string, granularity: Granularity): string {
  if (granularity === "hour") return label;
  const parts = label.split("-");
  if (granularity === "month") {
    const month = Number(parts[1]);
    if (!parts[0] || !Number.isFinite(month) || month < 1 || month > 12) return label;
    return `${MONTHS[month - 1]} ${parts[0].slice(2)}`;
  }
  const month = Number(parts[1]);
  const day = Number(parts[2]);
  if (!Number.isFinite(month) || !Number.isFinite(day) || month < 1 || month > 12) {
    return label;
  }
  return `${day} ${MONTHS[month - 1]}`;
}

/** The busiest bucket, or null when nothing was taken. */
export function peakPoint(series: TakingsPoint[]): TakingsPoint | null {
  let best: TakingsPoint | null = null;
  for (const point of series) {
    if (point.amount > 0 && (best === null || point.amount > best.amount)) {
      best = point;
    }
  }
  return best;
}

/** Percent change against the previous period, or null when it cannot be one.
 *
 *  Null rather than 100% when the previous period took nothing: every figure
 *  is infinitely more than zero, and "+100%" reads as a real comparison.
 */
export function percentChange(current: number, previous: number): number | null {
  if (!Number.isFinite(current) || !Number.isFinite(previous)) return null;
  if (previous <= 0) return null;
  return Math.round(((current - previous) / previous) * 100);
}

/** What the busiest bucket should be called on screen. */
export function peakLabel(granularity: Granularity): string {
  if (granularity === "hour") return "Best hour";
  if (granularity === "day") return "Best day";
  return "Best month";
}
