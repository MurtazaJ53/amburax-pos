#!/usr/bin/env node
/**
 * Sign in for real, then read real data. Run this after every deploy.
 *
 * scripts/smoke.mjs already requests every route and fails on a 5xx, and it
 * would have passed happily through the worst outage this app has had: every
 * page rendering while every API call returned 503, because the standalone
 * server was started without its env file and had no backend URL to call.
 * Unauthenticated routes answer 401 or redirect in that state, which looks
 * exactly like health.
 *
 * So this does the one thing that cannot be faked - it logs in and reads
 * something only a working backend can produce. A shop that cannot sell is
 * worse than a shop whose profit report is slightly wrong, and this is the
 * cheaper check by a wide margin.
 *
 * Usage:
 *   SMOKE_EMAIL=you@example.com SMOKE_PASSWORD=... \
 *     node scripts/smoke-auth.mjs https://your-site
 *
 * Exits non-zero with a plain sentence on the first failure.
 */

const BASE = (process.argv[2] ?? process.env.SMOKE_BASE_URL ?? "http://127.0.0.1:3000")
  .replace(/\/$/, "");
const EMAIL = process.env.SMOKE_EMAIL;
const PASSWORD = process.env.SMOKE_PASSWORD;

function fail(message) {
  // Never print the password, and never print the response body: an auth
  // error can carry a token or a session id, and this output gets pasted
  // into chat windows and issue trackers.
  console.error(`SMOKE FAIL: ${message}`);
  process.exit(1);
}

if (!EMAIL || !PASSWORD) {
  fail("set SMOKE_EMAIL and SMOKE_PASSWORD to an account on this deployment");
}

/** Cookies the server set, carried by hand - fetch does not keep a jar. */
const jar = new Map();

function remember(response) {
  const raw = response.headers.getSetCookie?.() ?? [];
  for (const cookie of raw) {
    const [pair] = cookie.split(";");
    const index = pair.indexOf("=");
    if (index > 0) jar.set(pair.slice(0, index).trim(), pair.slice(index + 1));
  }
}

function cookieHeader() {
  return [...jar].map(([name, value]) => `${name}=${value}`).join("; ");
}

async function call(path, options = {}) {
  const url = `${BASE}${path}`;
  let response;
  try {
    response = await fetch(url, {
      ...options,
      redirect: "manual",
      headers: {
        Accept: "application/json",
        ...(jar.size ? { Cookie: cookieHeader() } : {}),
        ...options.headers,
      },
    });
  } catch (error) {
    fail(`${path} could not be reached (${error.message}). Is the site up?`);
  }
  remember(response);
  return response;
}

const steps = [];

// 1. Sign in.
const login = await call("/api/auth/login", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
});
if (login.status === 503 || login.status === 502) {
  fail(
    `sign-in returned ${login.status}. The web app is running but cannot reach ` +
      "the backend - check BUSINESS_HUB_API_BASE_URL is set where the server runs.",
  );
}
if (!login.ok) fail(`sign-in returned ${login.status} for ${EMAIL}`);
if (jar.size === 0) fail("sign-in succeeded but set no session cookie");
steps.push("signed in");

// 2. The session has to name a shop, or nothing else can be read.
const session = await call("/api/auth/session");
if (!session.ok) fail(`session returned ${session.status} after a good sign-in`);
const who = await session.json().catch(() => null);
if (!who) fail("session returned something that is not JSON");
steps.push("session readable");

// 3. Read actual data. This is the step that separates "the page renders"
//    from "the shop can trade".
const inventory = await call("/api/inventory");
if (!inventory.ok) {
  fail(
    `reading stock returned ${inventory.status}. Pages will still render, so ` +
      "this is the failure a browser check misses.",
  );
}
const stock = await inventory.json().catch(() => null);
if (stock === null) fail("stock returned something that is not JSON");
const rows = Array.isArray(stock) ? stock : (stock.results ?? stock.items ?? []);
if (!Array.isArray(rows)) fail("stock did not come back as a list");
steps.push(`stock readable (${rows.length} row${rows.length === 1 ? "" : "s"})`);

console.log(`SMOKE OK: ${steps.join(" · ")}`);
console.log(`  ${BASE}`);
