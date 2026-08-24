import type { Sale } from "@/lib/types";

/**
 * Derived figures for the home screen.
 *
 * The dashboard projection gives us today's total and count but no shape: no
 * hourly curve, no payment split, no busiest hour. All three are recoverable
 * from the day's own sale rows, which we already fetch, so they cost one
 * extra API call rather than a backend change.
 *
 * Everything here is pure so it can be unit tested and reused by any other
 * screen that wants the same treatment.
 */

export type PaymentMixSlice = {
  /** Canonical mode key, e.g. "CASH". */
  key: string;
  /** Human label for the legend. */
  label: string;
  /** Summed sale totals for this mode, in major units. */
  amount: number;
  /** How many bills used it. */
  count: number;
};

export type HourBucket = {
  /** 0–23 in the shop's own timezone. */
  hour: number;
  label: string;
  amount: number;
  count: number;
};

export type TodayShape = {
  /** One bucket per trading hour, oldest first. */
  hourly: HourBucket[];
  mix: PaymentMixSlice[];
  /** Mean bill value, or 0 when there are no bills. */
  averageBill: number;
  /** The single best hour, or null when the day has no sales yet. */
  bestHour: HourBucket | null;
  /** Sum of every CASH bill today. */
  cashTaken: number;
};

const MODE_LABELS: Record<string, string> = {
  CASH: "Cash",
  UPI: "UPI",
  BANK: "Bank",
  CARD: "Card",
  CREDIT: "Khata",
  SPLIT: "Split",
  OTHER: "Other",
};

/** Legend order, so the bar segments don't reshuffle between renders. */
const MODE_ORDER = ["UPI", "CASH", "CARD", "BANK", "CREDIT", "SPLIT", "OTHER"];

/**
 * The hour a timestamp falls in *for the shop*, not for whichever server
 * happens to render the page. A shop in Asia/Kolkata reading its busiest hour
 * off a UTC clock would see every figure shifted by five and a half hours.
 */
export function hourInTimeZone(iso: string, timeZone: string): number | null {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit",
      hour12: false,
      timeZone,
    }).formatToParts(date);
    const hourPart = parts.find((part) => part.type === "hour")?.value;
    if (hourPart === undefined) {
      return null;
    }
    // "24" is a legal en-GB rendering of midnight.
    const hour = Number(hourPart) % 24;
    return Number.isFinite(hour) ? hour : null;
  } catch {
    // An unrecognised IANA zone should degrade to the server clock rather
    // than blanking the whole card.
    return date.getHours();
  }
}

export function formatHourLabel(hour: number): string {
  const suffix = hour < 12 ? "AM" : "PM";
  const twelve = hour % 12 === 0 ? 12 : hour % 12;
  return `${twelve} ${suffix}`;
}

function saleAmount(sale: Sale): number {
  const value = Number(sale.total_amount);
  return Number.isFinite(value) ? value : 0;
}

/**
 * Bills that count toward takings. Voided and tombstoned rows are excluded
 * for the same reason they are excluded from the projection: they did not
 * happen.
 */
export function isCountableSale(sale: Sale): boolean {
  if (sale.tombstone) {
    return false;
  }
  const status = (sale.status || "").toUpperCase();
  return status !== "VOID" && status !== "VOIDED" && status !== "CANCELLED";
}

/**
 * Builds the hourly curve between the first and last sale of the day. We do
 * not pad out to a full 24 hours: a shop that trades 9 to 9 should not be
 * shown twelve hours of flat line implying it was open and idle.
 */
export function buildHourlyBuckets(sales: Sale[], timeZone: string): HourBucket[] {
  const byHour = new Map<number, HourBucket>();

  for (const sale of sales) {
    if (!isCountableSale(sale)) {
      continue;
    }
    const hour = hourInTimeZone(sale.occurred_at || sale.sale_date, timeZone);
    if (hour === null) {
      continue;
    }
    const bucket = byHour.get(hour) ?? {
      hour,
      label: formatHourLabel(hour),
      amount: 0,
      count: 0,
    };
    bucket.amount += saleAmount(sale);
    bucket.count += 1;
    byHour.set(hour, bucket);
  }

  if (byHour.size === 0) {
    return [];
  }

  const hours = [...byHour.keys()].sort((a, b) => a - b);
  const first = hours[0];
  const last = hours[hours.length - 1];

  const filled: HourBucket[] = [];
  for (let hour = first; hour <= last; hour += 1) {
    filled.push(
      byHour.get(hour) ?? { hour, label: formatHourLabel(hour), amount: 0, count: 0 },
    );
  }
  return filled;
}

export function buildPaymentMix(sales: Sale[]): PaymentMixSlice[] {
  const byMode = new Map<string, PaymentMixSlice>();

  const add = (key: string, amount: number, bills: number) => {
    if (amount <= 0) return;
    const slice = byMode.get(key) ?? {
      key,
      label: MODE_LABELS[key] ?? key,
      amount: 0,
      count: 0,
    };
    slice.amount += amount;
    slice.count += bills;
    byMode.set(key, slice);
  };

  for (const sale of sales) {
    if (!isCountableSale(sale)) {
      continue;
    }

    // A split bill is settled in two or more tenders, and its payment_mode is
    // the literal string "SPLIT". Bucketing on that alone put the whole sale
    // in a "Split" slice — so the cash half of it never reached the cash
    // figure the drawer is counted against at close. The tender rows are the
    // truth; payment_mode is only a summary of them.
    const tenders = (sale.payments ?? []).filter((payment) => {
      const value = Number(payment.amount);
      return Number.isFinite(value) && value > 0;
    });

    if (tenders.length > 0) {
      for (const tender of tenders) {
        add((tender.payment_method || "OTHER").toUpperCase(), Number(tender.amount), 1);
      }
      continue;
    }

    // No tender rows recorded — fall back to the summary so the money is
    // still counted somewhere rather than disappearing.
    add((sale.payment_mode || "OTHER").toUpperCase(), saleAmount(sale), 1);
  }

  return [...byMode.values()]
    .filter((slice) => slice.amount > 0)
    .sort((a, b) => {
      const rankA = MODE_ORDER.indexOf(a.key);
      const rankB = MODE_ORDER.indexOf(b.key);
      return (rankA < 0 ? MODE_ORDER.length : rankA) - (rankB < 0 ? MODE_ORDER.length : rankB);
    });
}

export function summariseToday(sales: Sale[], timeZone: string): TodayShape {
  const countable = sales.filter(isCountableSale);
  const hourly = buildHourlyBuckets(countable, timeZone);
  const mix = buildPaymentMix(countable);

  const total = countable.reduce((sum, sale) => sum + saleAmount(sale), 0);
  const averageBill = countable.length > 0 ? total / countable.length : 0;

  const bestHour = hourly.reduce<HourBucket | null>((best, bucket) => {
    if (bucket.count === 0) {
      return best;
    }
    return best === null || bucket.amount > best.amount ? bucket : best;
  }, null);

  const cashTaken = mix.find((slice) => slice.key === "CASH")?.amount ?? 0;

  return { hourly, mix, averageBill, bestHour, cashTaken };
}

/**
 * Percentage change, rounded. Returns null when there is no baseline to
 * compare against — "+100%" against a zero yesterday is noise, not insight.
 */
export function percentChange(current: number, previous: number): number | null {
  if (!Number.isFinite(current) || !Number.isFinite(previous) || previous <= 0) {
    return null;
  }
  return Math.round(((current - previous) / previous) * 100);
}

/** The shop-local calendar date, as YYYY-MM-DD, for API date filters. */
export function shopDateKey(date: Date, timeZone: string): string {
  try {
    return new Intl.DateTimeFormat("en-CA", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      timeZone,
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat("en-CA", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(date);
  }
}

export function addDays(dateKey: string, days: number): string {
  const [year, month, day] = dateKey.split("-").map(Number);
  const base = new Date(Date.UTC(year, (month ?? 1) - 1, day ?? 1));
  base.setUTCDate(base.getUTCDate() + days);
  return base.toISOString().slice(0, 10);
}
