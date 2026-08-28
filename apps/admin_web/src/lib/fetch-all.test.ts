import { afterEach, describe, expect, it, vi } from "vitest";

import { fetchAllPages } from "./fetch-all";

/** Reading a whole list, not the first page of it.
 *
 *  The till loaded the catalogue with a bare fetch and searched it in memory,
 *  so on 285 products it could not sell 85 of them - and searching for one
 *  answered "Nothing matches", which reads as "you do not stock this". The
 *  same defect had already been found and fixed in the mobile client.
 *
 *  The test that matters is the first one: a caller that stops at page one
 *  gets a plausible-looking answer, so only a multi-page fixture can tell the
 *  difference between working and broken.
 */
function server(pages: { rows: unknown[]; next: string | null }[]) {
  const seen: (string | null)[] = [];
  const fetchMock = vi.fn(async (url: string) => {
    const cursor = new URL(url, "http://x").searchParams.get("cursor");
    seen.push(cursor);
    const page = pages[seen.length - 1] ?? { rows: [], next: null };
    return {
      ok: true,
      json: async () => page.rows,
      headers: { get: (name: string) => (name === "X-Next-Cursor" ? page.next : null) },
    } as unknown as Response;
  });
  vi.stubGlobal("fetch", fetchMock);
  return { seen, fetchMock };
}

const rows = (from: number, count: number) =>
  Array.from({ length: count }, (_, i) => ({ id: `item-${from + i}` }));

describe("fetching every page", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("returns rows from beyond the first page", () => {
    // 285 products across two pages used to arrive as 200.
    server([
      { rows: rows(1, 200), next: "cursor-1" },
      { rows: rows(201, 85), next: null },
    ]);

    return fetchAllPages("/api/inventory").then((all) => {
      expect(all).toHaveLength(285);
      expect(all[284]).toEqual({ id: "item-285" });
    });
  });

  it("sends back the cursor it was given", async () => {
    const { seen } = server([
      { rows: rows(1, 2), next: "cursor-1" },
      { rows: rows(3, 2), next: "cursor-2" },
      { rows: rows(5, 1), next: null },
    ]);

    await fetchAllPages("/api/inventory");
    expect(seen).toEqual([null, "cursor-1", "cursor-2"]);
  });

  it("makes one request when there is one page", async () => {
    const { fetchMock } = server([{ rows: rows(1, 3), next: null }]);

    await fetchAllPages("/api/inventory");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("keeps other query parameters on every page", async () => {
    const calls: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) => {
        calls.push(url);
        const cursor = new URL(url, "http://x").searchParams.get("cursor");
        return {
          ok: true,
          json: async () => rows(1, 1),
          headers: { get: () => (cursor ? null : "cursor-1") },
        } as unknown as Response;
      }),
    );

    await fetchAllPages("/api/inventory", { params: { q: "tea" } });
    expect(calls).toHaveLength(2);
    for (const url of calls) expect(url).toContain("q=tea");
  });

  it("does not loop forever when a server repeats its cursor", async () => {
    const { fetchMock } = server(
      Array.from({ length: 60 }, () => ({ rows: rows(1, 1), next: "stuck" })),
    );

    const all = await fetchAllPages("/api/inventory");
    expect(all.length).toBeGreaterThan(0);
    expect(fetchMock.mock.calls.length).toBeLessThan(4);
  });

  it("stops at a ceiling when one is given", async () => {
    server([
      { rows: rows(1, 200), next: "cursor-1" },
      { rows: rows(201, 200), next: "cursor-2" },
    ]);

    const all = await fetchAllPages("/api/inventory", { max: 250 });
    expect(all).toHaveLength(250);
  });

  it("reports a failed request rather than returning a short list", async () => {
    // Returning what arrived before the failure would look like a small shop.
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ ok: false, status: 503 }) as unknown as Response),
    );

    await expect(fetchAllPages("/api/inventory")).rejects.toThrow("503");
  });

  it("refuses a response that is not a list", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        ({
          ok: true,
          json: async () => ({ detail: "nope" }),
          headers: { get: () => null },
        }) as unknown as Response,
      ),
    );

    await expect(fetchAllPages("/api/inventory")).rejects.toThrow("did not return a list");
  });

  it("handles an empty list", async () => {
    server([{ rows: [], next: null }]);
    expect(await fetchAllPages("/api/inventory")).toEqual([]);
  });
});
