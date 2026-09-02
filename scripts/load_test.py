"""Drive the reads that matter and report how long they took.

`seed_load` fills a shop with a hundred times the data. This is the other
half: it asks the API the questions a shopkeeper actually asks, many times,
and prints what came back and how slowly. Together they turn every performance
claim in this project into a measurement.

The endpoints are not a sample of the API. They are the ones the scale review
named, in the order a slow morning is felt:

  inventory list        the till's search, paged
  inventory summary     stock on hand, summed from the movement ledger - the
                        query FUTURE.md predicts will slow first
  sales list            the history screen, paged on occurred_at
  dashboard             the first screen after sign-in
  best sellers          an aggregate over sale lines
  debtors               who owes money, summed from the khata ledger

Run it from a machine that can reach the API, against a box you are willing
to make slow:

    python scripts/load_test.py --base-url http://127.0.0.1:8001/api/v1 \\
        --email owner@example.com --password ... --shop-id <uuid> --rounds 30

It refuses production by name. That is not politeness: a load test against the
box a shop is selling from is an outage you caused on purpose, and the numbers
would be wrong anyway because a real till is competing for the same disk.
Override with --i-know-this-is-not-production only if you are certain the host
you typed is a staging copy.

Reading the output: p95 is the number to care about, because it is roughly the
worst thing a person notices in a session, and the rows column is there so a
fast empty answer is never mistaken for a fast one. An endpoint that returns
0 rows quickly has measured nothing.
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

#: Hosts that are the live shop. Matched as substrings of the URL's host.
PRODUCTION_HOSTS = (
    "api.indianwasteportal.com",
    "businesshub.pro",
    "157.245.102.242",
)

TIMEOUT_SECONDS = 60


def _request(url: str, *, token: str = "", payload: dict | None = None) -> tuple[int, bytes]:
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(
        url,
        data=body,
        method="POST" if body else "GET",
        headers={
            "Accept": "application/json",
            **({"Content-Type": "application/json"} if body else {}),
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def sign_in(base_url: str, email: str, password: str) -> str:
    status, raw = _request(
        f"{base_url}/session/token/", payload={"email": email, "password": password}
    )
    if status != 200:
        raise SystemExit(f"Sign-in failed ({status}): {raw.decode('utf-8', 'replace')[:300]}")
    return json.loads(raw)["access"]


def row_count(raw: bytes) -> int | str:
    """How many rows came back, so a fast empty answer is not read as fast."""
    try:
        parsed = json.loads(raw)
    except Exception:
        return "?"
    if isinstance(parsed, list):
        return len(parsed)
    if isinstance(parsed, dict):
        for key in ("results", "items", "rows", "data"):
            value = parsed.get(key)
            if isinstance(value, list):
                return len(value)
        return len(parsed)
    return "?"


def endpoints(shop_id: str) -> list[tuple[str, str]]:
    return [
        ("inventory list", f"shops/{shop_id}/inventory/?page_size=50"),
        ("inventory summary", f"shops/{shop_id}/inventory/summary/"),
        ("sales list", f"shops/{shop_id}/sales/?page_size=50"),
        ("dashboard", f"shops/{shop_id}/projections/dashboard/"),
        ("best sellers", f"shops/{shop_id}/reports/best-sellers/"),
        ("debtors", f"shops/{shop_id}/customers/debtors/"),
    ]


def measure(base_url: str, token: str, path: str, rounds: int) -> dict:
    timings: list[float] = []
    statuses: set[int] = set()
    rows: int | str = "?"
    for _ in range(rounds):
        started = time.perf_counter()
        status, raw = _request(f"{base_url}/{path}", token=token)
        timings.append((time.perf_counter() - started) * 1000)
        statuses.add(status)
        if status == 200:
            rows = row_count(raw)
    timings.sort()
    # p95 by nearest rank: with 30 rounds that is the 29th slowest, which is a
    # real observation rather than an interpolation between two of them.
    p95_index = max(0, min(len(timings) - 1, int(round(0.95 * len(timings))) - 1))
    return {
        "rounds": rounds,
        "rows": rows,
        "statuses": sorted(statuses),
        "p50_ms": round(statistics.median(timings), 1),
        "p95_ms": round(timings[p95_index], 1),
        "max_ms": round(timings[-1], 1),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True, help="e.g. http://127.0.0.1:8001/api/v1")
    parser.add_argument("--email", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--shop-id", required=True)
    parser.add_argument("--rounds", type=int, default=30)
    parser.add_argument(
        "--i-know-this-is-not-production",
        action="store_true",
        help="Required to run against a host that looks like the live shop.",
    )
    args = parser.parse_args()

    base_url = args.base_url.rstrip("/")
    host = (urllib.parse.urlparse(base_url).hostname or "").lower()
    looks_live = any(known in host for known in PRODUCTION_HOSTS)
    if looks_live and not args.i_know_this_is_not_production:
        print(
            f"Refusing to load-test {host}: that is the live shop. A till "
            "cannot sell while this is running, and the numbers would be wrong "
            "anyway because real traffic is competing for the same disk. "
            "Point this at a staging copy.",
            file=sys.stderr,
        )
        return 2

    token = sign_in(base_url, args.email, args.password)

    print(f"{base_url}  shop {args.shop_id}  {args.rounds} rounds per endpoint")
    print(f"{'endpoint':<20}{'rows':>8}{'p50 ms':>10}{'p95 ms':>10}{'max ms':>10}  status")
    worst = 0.0
    for label, path in endpoints(args.shop_id):
        result = measure(base_url, token, path, args.rounds)
        worst = max(worst, result["p95_ms"])
        statuses = ",".join(str(s) for s in result["statuses"])
        print(
            f"{label:<20}{str(result['rows']):>8}{result['p50_ms']:>10}"
            f"{result['p95_ms']:>10}{result['max_ms']:>10}  {statuses}"
        )

    print()
    # A number to argue with, not a verdict. 1000 ms is where a screen stops
    # feeling like it responded and starts feeling like it is loading.
    print(f"worst p95: {worst:.0f} ms", "- slow enough to feel" if worst > 1000 else "- fine")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
