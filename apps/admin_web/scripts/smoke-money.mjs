#!/usr/bin/env node
/**
 * Read real figures back out of a deployment and check they agree.
 *
 * Three times in one session, green tests and a stale droplet looked
 * identical from the outside. Nothing caught it: smoke.mjs asks whether
 * routes answer, smoke-auth.mjs asks whether a login works and data comes
 * back - both are true of a server running last week's code. A deploy that
 * reports success is not a deploy that took.
 *
 * So this asks the only question that separates them: do the numbers agree
 * with each other? It needs no fixture and no known total, because it checks
 * relationships rather than values -
 *
 *   the GST rate table must sum to the GST headline
 *   the HSN table must sum to the same headline
 *   net revenue minus cost of goods must equal gross profit
 *
 * Every money bug this session broke one of those. The returns fix reached
 * the GST headline card and missed the table underneath it, which is exactly
 * the first check here, and it would have been caught in the seconds after
 * deploying rather than by a person reading two numbers off one screen.
 *
 * Run it as the LAST step of a deploy, against the deployed URL.
 *
 * Usage:
 *   SMOKE_EMAIL=you@example.com SMOKE_PASSWORD=... \
 *     node scripts/smoke-money.mjs https://your-site
 */

const BASE = (process.argv[2] ?? process.env.SMOKE_BASE_URL ?? "http://127.0.0.1:3000")
  .replace(/\/$/, "");
const EMAIL = process.env.SMOKE_EMAIL;
const PASSWORD = process.env.SMOKE_PASSWORD;

const problems = [];
const notes = [];

function fail(message) {
  console.error(`SMOKE FAIL: ${message}`);
  process.exit(1);
}

if (!EMAIL || !PASSWORD) {
  fail("set SMOKE_EMAIL and SMOKE_PASSWORD to an account on this deployment");
}

const jar = new Map();

function remember(response) {
  for (const cookie of response.headers.getSetCookie?.() ?? []) {
    const [pair] = cookie.split(";");
    const index = pair.indexOf("=");
    if (index > 0) jar.set(pair.slice(0, index).trim(), pair.slice(index + 1));
  }
}

async function call(path, options = {}) {
  let response;
  try {
    response = await fetch(`${BASE}${path}`, {
      ...options,
      redirect: "manual",
      headers: {
        Accept: "application/json",
        ...(jar.size
          ? { Cookie: [...jar].map(([k, v]) => `${k}=${v}`).join("; ") }
          : {}),
        ...options.headers,
      },
    });
  } catch (error) {
    fail(`${path} could not be reached (${error.message}). Is the site up?`);
  }
  remember(response);
  return response;
}

/** Money as a number of paise, so comparisons are exact. */
function paise(value) {
  return Math.round(Number(value ?? 0) * 100);
}

function rupees(value) {
  return (value / 100).toFixed(2);
}

/** Compare two figures that must be equal, and say which is which if not. */
function mustMatch(label, left, leftName, right, rightName) {
  if (left === right) {
    notes.push(`${label}: ${rupees(left)}`);
    return;
  }
  problems.push(
    `${label}: ${leftName} says ${rupees(left)}, ${rightName} says ` +
      `${rupees(right)} (out by ${rupees(Math.abs(left - right))})`,
  );
}

const login = await call("/api/auth/login", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
});
if (!login.ok) fail(`sign-in returned ${login.status} for ${EMAIL}`);
if (jar.size === 0) fail("sign-in succeeded but set no session cookie");

async function json(path) {
  const response = await call(path);
  if (!response.ok) {
    // A report a plan does not include is not a broken deploy.
    if (response.status === 403) return null;
    fail(`${path} returned ${response.status}`);
  }
  return response.json().catch(() => fail(`${path} did not return JSON`));
}

// --- GST: the tables must agree with the card above them -----------------
const gst = await json("/api/reports/gst-summary");
if (gst) {
  const headline = paise(gst.taxable_amount);

  const byRate = (gst.b2c_small ?? []).reduce(
    (sum, row) => sum + paise(row.taxable_amount),
    0,
  );
  mustMatch("GST taxable", byRate, "the rate table", headline, "the headline");

  const byHsn = (gst.hsn_summary ?? []).reduce(
    (sum, row) => sum + paise(row.taxable_amount),
    0,
  );
  // Only when HSN codes are actually recorded; a shop that leaves them blank
  // has an empty table, and an empty table is not a disagreement.
  if ((gst.hsn_summary ?? []).length > 0) {
    mustMatch("GST taxable", byHsn, "the HSN table", headline, "the headline");
  }
}

// --- P&L: the lines a reader adds up must add up -------------------------
const pl = await json("/api/reports/profit-loss");
if (pl) {
  mustMatch(
    "Gross profit",
    paise(pl.net_revenue) - paise(pl.cost_of_goods_sold),
    "net revenue less cost",
    paise(pl.gross_profit),
    "the gross profit line",
  );
  mustMatch(
    "Net profit",
    paise(pl.gross_profit) - paise(pl.total_expenses),
    "gross profit less expenses",
    paise(pl.net_profit),
    "the net profit line",
  );
}

// --- Day book: the parts must make the whole -----------------------------
const book = await json("/api/reports/day-book");
if (book?.jama) {
  const { total, ...parts } = book.jama;
  const summed = Object.values(parts).reduce((sum, value) => sum + paise(value), 0);
  mustMatch("Jama", summed, "its own parts", paise(total), "the total");
}

if (problems.length) {
  console.error("SMOKE FAIL: figures on this deployment disagree with each other.");
  for (const problem of problems) console.error(`  ${problem}`);
  console.error(
    "\nA report disagreeing with itself usually means this server is running " +
      "older code than you just deployed. Check the container actually restarted.",
  );
  process.exit(1);
}

console.log("SMOKE OK: every figure agrees with the figures it is made of.");
for (const note of notes) console.log(`  ${note}`);
console.log(`  ${BASE}`);
