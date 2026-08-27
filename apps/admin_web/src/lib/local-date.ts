/** Today, as the shopkeeper's calendar has it.
 *
 *  `new Date().toISOString().slice(0, 10)` is the obvious way to get a
 *  YYYY-MM-DD and it is wrong everywhere east of Greenwich. toISOString always
 *  renders UTC, so in India every moment between midnight and 05:30 belongs to
 *  the previous day.
 *
 *  That was not a rounding error. An expense recorded at 01:47 IST on 28 August
 *  was filed against 27 August, while the sales beside it were filed against
 *  the 28th - so the day book showed a shop that had paid out nothing while
 *  money had visibly left the till, and its cash-in-hand was overstated today
 *  and understated yesterday. The money was not lost, only filed on a day
 *  nobody would look for it. Shops closing late hit this every night.
 *
 *  The same trap catches a locally-built date: new Date(2026, 7, 1) is local
 *  midnight, which in IST is 31 July in UTC, so a "start of month" computed
 *  that way lands in the previous month.
 *
 *  So these read the calendar fields the browser already resolved for the
 *  user's own zone, and never re-render an instant in another one.
 *
 *  Not to be confused with shiftDate() in date-ranges.ts or addDays() in
 *  dashboard-metrics.ts. Those take a date STRING, rebuild it with Date.UTC
 *  and read it back with toISOString - UTC in, UTC out, symmetric on purpose
 *  so that adding a day cannot land twice on a daylight-saving boundary. They
 *  are correct and this does not replace them.
 */

/** A Date rendered as YYYY-MM-DD in the viewer's own timezone. */
export function toDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/** The date the shopkeeper would write on a receipt right now. */
export function todayKey(): string {
  return toDateKey(new Date());
}

/** Today, moved back by whole days, still in local time. */
export function daysAgoKey(days: number): string {
  const date = new Date();
  date.setDate(date.getDate() - days);
  return toDateKey(date);
}

/** The first of the current month, in local time. */
export function monthStartKey(): string {
  const now = new Date();
  return toDateKey(new Date(now.getFullYear(), now.getMonth(), 1));
}
