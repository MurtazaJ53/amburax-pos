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

  /** The ceiling, and the silence around it.
   *
   *  25 pages of 200 rows is 5,000 products, and a real shop reached it: a
   *  catalogue of about five thousand sits exactly on the line. Past it the
   *  function returned a short list that looked precisely like a complete
   *  one - the same defect it was written to fix, one order of magnitude
   *  further out. These pin the difference between "that is all of it" and
   *  "that is all I was willing to fetch".
   */
  describe("when there is more than it will fetch", () => {
    /** A server with no end: every page offers another. */
    function endlessServer() {
      let issued = 0;
      const fetchMock = vi.fn(async () => {
        issued += 1;
        return {
          ok: true,
          json: async () => rows(issued * 200, 200),
          headers: { get: () => `cursor-${issued}` },
        } as unknown as Response;
      });
      vi.stubGlobal("fetch", fetchMock);
      return fetchMock;
    }

    it("says so instead of returning a short list quietly", async () => {
      endlessServer();
      const incomplete = vi.fn();

      await fetchAllPages("/api/inventory", { onIncomplete: incomplete });

      expect(incomplete).toHaveBeenCalledTimes(1);
    });

    it("says how many it did load, so the screen can be specific", async () => {
      endlessServer();
      const incomplete = vi.fn();

      const loaded = await fetchAllPages("/api/inventory", { onIncomplete: incomplete });

      expect(incomplete).toHaveBeenCalledWith(loaded.length);
    });

    it("still hands back everything it managed to read", async () => {
      // Truncated is not the same as failed. The till has to open.
      endlessServer();

      const loaded = await fetchAllPages("/api/inventory", { onIncomplete: vi.fn() });

      expect(loaded.length).toBe(5000);
    });

    it("does not cry wolf when the walk finished properly", async () => {
      // The bug this nearly shipped with: the cursor variable is still set
      // after the last successful request, so testing it directly would
      // report every complete walk as truncated.
      server([
        { rows: rows(0, 200), next: "c1" },
        { rows: rows(200, 85), next: null },
      ]);
      const incomplete = vi.fn();

      await fetchAllPages("/api/inventory", { onIncomplete: incomplete });

      expect(incomplete).not.toHaveBeenCalled();
    });

    it("does not cry wolf on a single-page list", async () => {
      server([{ rows: rows(0, 12), next: null }]);
      const incomplete = vi.fn();

      await fetchAllPages("/api/inventory", { onIncomplete: incomplete });

      expect(incomplete).not.toHaveBeenCalled();
    });

    it("does not report a caller's own ceiling as a truncation", async () => {
      // `max` is the caller saying "this is enough", which is a different
      // thing from the walk running out of room.
      endlessServer();
      const incomplete = vi.fn();

      await fetchAllPages("/api/inventory", { max: 50, onIncomplete: incomplete });

      expect(incomplete).not.toHaveBeenCalled();
    });

    it("does not report a stalled server as a truncation", async () => {
      // A repeated cursor means the server stopped making progress. That is
      // its own fault and its own message, not "there is more to read".
      server([
        { rows: rows(0, 200), next: "same" },
        { rows: rows(200, 200), next: "same" },
      ]);
      const incomplete = vi.fn();

      await fetchAllPages("/api/inventory", { onIncomplete: incomplete });

      expect(incomplete).not.toHaveBeenCalled();
    });

    it("works for callers that pass no handler at all", async () => {
      // Six callers predate this option and none of them should break.
      endlessServer();

      await expect(fetchAllPages("/api/inventory")).resolves.toHaveLength(5000);
    });
  });
});
