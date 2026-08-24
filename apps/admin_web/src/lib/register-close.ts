/** The end-of-day register close.
 *
 *  This used to be held in localStorage. That meant the over/short figure —
 *  the one number on the screen that can get a cashier accused of taking
 *  money — lived on a single machine, vanished when site data was cleared,
 *  and could not be reviewed by the owner from anywhere else. It is a server
 *  record now: `/api/sales/register`, one row per shop per business day.
 *
 *  What has not changed is the rule that matters: an unentered float is not
 *  zero, it is unanswered, and no over/short is shown until a person has
 *  typed it. The float was once hardcoded to 5,000, which made every reading
 *  a comparison against money nobody had counted.
 */

export type RegisterClose = {
  /** Shop-local date, YYYY-MM-DD. */
  date: string;
  /** Cash physically in the drawer before trading, as entered by a person. */
  openingFloat: number;
  /** Cash counted at close, as entered by a person. */
  countedCash: number;
  notes: string;
  /** ISO timestamp of when the day was locked, or null while still open. */
  closedAt: string | null;
  /** True once someone has actually typed the float. */
  floatEntered: boolean;
  /** Who locked it, for the audit trail. Null while the day is open. */
  closedByName: string | null;
};

/** What the server sends back for one business day. */
export type RegisterPayload = {
  /** Cash the API summed from the tender rows. Never computed in the browser:
   *  a till figure the client can choose is a till figure that can be made to
   *  say anything. */
  cashSales: number;
  /** Float + cash taken, or the snapshot if the day is already locked. */
  expectedCash: number;
  close: RegisterClose;
};

export function emptyClose(date: string): RegisterClose {
  return {
    date,
    openingFloat: 0,
    countedCash: 0,
    notes: "",
    closedAt: null,
    floatEntered: false,
    closedByName: null,
  };
}

function toMoney(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

/** Reads the API response, tolerating anything that is not one.
 *
 *  A malformed payload must leave the screen showing an unanswered day rather
 *  than a confident zero: the difference between the two is the difference
 *  between "we do not know" and "the drawer is empty".
 */
export function readRegisterPayload(payload: unknown, date: string): RegisterPayload {
  const body = (payload ?? {}) as {
    cash_sales?: unknown;
    expected_cash?: unknown;
    business_date?: unknown;
    session?: Record<string, unknown> | null;
  };
  const day = typeof body.business_date === "string" ? body.business_date : date;
  const session = body.session ?? null;

  const close: RegisterClose = session
    ? {
        date: day,
        openingFloat: toMoney(session.opening_float),
        countedCash: toMoney(session.counted_cash),
        notes: typeof session.notes === "string" ? session.notes : "",
        closedAt: typeof session.closed_at === "string" ? session.closed_at : null,
        floatEntered: session.float_entered === true,
        closedByName:
          typeof session.closed_by_name === "string" ? session.closed_by_name : null,
      }
    : emptyClose(day);

  return {
    cashSales: toMoney(body.cash_sales),
    expectedCash: toMoney(body.expected_cash),
    close,
  };
}

/** The body the API expects when saving or locking a count. */
export function closeRequestBody(close: RegisterClose, lock: boolean) {
  return {
    business_date: close.date,
    opening_float: close.openingFloat,
    counted_cash: close.countedCash,
    float_entered: close.floatEntered,
    notes: close.notes,
    lock,
  };
}

/** What the drawer should hold: the float plus the cash actually taken. */
export function expectedInTill(openingFloat: number, cashSales: number): number {
  return toMoney(openingFloat) + (Number.isFinite(cashSales) ? cashSales : 0);
}

/**
 * Counted minus expected. Positive is over, negative is short.
 *
 * Returns null when no float has been entered, because a difference measured
 * against an unknown baseline is not a difference — it is a guess, and this
 * is the number that decides whether someone is accused of a shortfall.
 */
export function discrepancy(
  close: Pick<RegisterClose, "openingFloat" | "countedCash">,
  cashSales: number,
  floatEntered: boolean,
): number | null {
  if (!floatEntered) return null;
  return close.countedCash - expectedInTill(close.openingFloat, cashSales);
}

/** Is this text something a person can be part-way through typing as money?
 *
 *  The drawer inputs are plain text, not number spinners: a counted till must
 *  never be nudged by a stray scroll wheel or arrow key. That trade means the
 *  field has to reject letters itself rather than rely on the browser, and it
 *  has to accept the half-finished states — "" , "10." — that typing a decimal
 *  passes through, or the dot is eaten as fast as it is typed.
 */
export function isMoneyInput(text: string): boolean {
  return /^\d*\.?\d{0,2}$/.test(text);
}

/** The number behind a money field, treating an unfinished entry as zero. */
export function moneyValue(text: string): number {
  const value = parseFloat(text);
  return Number.isFinite(value) && value >= 0 ? value : 0;
}
