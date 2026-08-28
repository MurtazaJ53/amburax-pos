#!/usr/bin/env node
/**
 * Time the screens a shopkeeper actually waits on.
 *
 * Every performance claim in this project has been an estimate. The scale
 * review reasoned about a hundred times the data; the shop it reasoned about
 * had eight hundred products. This measures instead.
 *
 * Run it BEFORE seeding and again after. A single number after the fact is not
 * a measurement - "the day book takes 900ms" only means something next to what
 * it took yesterday.
 *
 * Percentiles, not averages. An average hides the slow tail, and the slow tail
 * is what a cashier notices: nineteen fast sales and one that hangs is
 * remembered as a slow till.
 *
 * The first request to each endpoint is discarded. A cold connection and an
 * unwarmed page cache are real, but they are paid once per deploy rather than
 * once per sale.
 *
 * Usage:
 *   SMOKE_EMAIL=you@example.com SMOKE_PASSWORD=... \
 *     node scripts/bench.mjs https://your-site [runs]
 */

const BASE = (process.argv[2] ?? process.env.SMOKE_BASE_URL ?? "http://127.0.0.1:3000")
  .replace(/\/$/, "");
const RUNS = Math.max(3, Number(process.argv[3] ?? 10));
const EMAIL = process.env.SMOKE_EMAIL;
const PASSWORD = process.env.SMOKE_PASSWORD;

function fail(message) {
  console.error(`BENCH FAIL: ${message}`);
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

const login = await call("/api/auth/login", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
});
if (!login.ok) fail(`sign-in returned ${login.status} for ${EMAIL}`);

/** What a shopkeeper waits on, named the way they would name it. */
const ENDPOINTS = [
  ["Stock list", "/api/inventory"],
  ["Customers", "/api/customers"],
  ["Sales history", "/api/sales"],
  ["Day book", "/api/reports/day-book"],
  ["Profit & loss", "/api/reports/profit-loss"],
  ["Who owes money", "/api/khata/debtors"],
  ["Best sellers", "/api/reports/best-sellers"],
];

function percentile(sorted, fraction) {
  const index = Math.min(sorted.length - 1, Math.floor(sorted.length * fraction));
  return sorted[index];
}

const results = [];

for (const [label, path] of ENDPOINTS) {
  // Discarded warm-up. Paid once per deploy, not once per sale.
  const first = await call(path);
  if (first.status === 403) {
    results.push({ label, skipped: "not on this plan" });
    continue;
  }
  if (!first.ok) {
    results.push({ label, skipped: `HTTP ${first.status}` });
    continue;
  }

  const timings = [];
  let bytes = 0;
  for (let run = 0; run < RUNS; run++) {
    const started = performance.now();
    const response = await call(path);
    const body = await response.arrayBuffer();
    timings.push(performance.now() - started);
    bytes = body.byteLength;
  }
  timings.sort((a, b) => a - b);
  results.push({
    label,
    p50: percentile(timings, 0.5),
    p95: percentile(timings, 0.95),
    max: timings[timings.length - 1],
    kb: bytes / 1024,
  });
}

const ms = (value) => `${value.toFixed(0)}ms`.padStart(8);

console.log(`\n${BASE}`);
console.log(`${RUNS} runs each, first discarded\n`);
console.log(
  "  " +
    "Screen".padEnd(18) +
    "p50".padStart(8) +
    "p95".padStart(8) +
    "slowest".padStart(8) +
    "size".padStart(10),
);
console.log("  " + "-".repeat(52));

for (const row of results) {
  if (row.skipped) {
    console.log("  " + row.label.padEnd(18) + `  (${row.skipped})`);
    continue;
  }
  console.log(
    "  " +
      row.label.padEnd(18) +
      ms(row.p50) +
      ms(row.p95) +
      ms(row.max) +
      `${row.kb.toFixed(0)} KB`.padStart(10),
  );
}

// Said rather than left to be inferred. A screen a shopkeeper waits a full
// second for is the finding, and a table is easy to skim past.
const slow = results.filter((row) => !row.skipped && row.p95 > 1000);
if (slow.length) {
  console.log("");
  for (const row of slow) {
    console.log(`  SLOW: ${row.label} takes ${row.p95.toFixed(0)}ms at p95.`);
  }
}
console.log("");
