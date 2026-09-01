/** Fetch every page of a keyset-paged list, not just the first one.
 *
 *  The server returns a bare array and names the next page in an
 *  X-Next-Cursor header. A caller that reads only the body gets the first
 *  page and has no way to know there was ever a second - there is no count,
 *  no flag, and nothing in the response that looks wrong.
 *
 *  That is not hypothetical. The till loaded the catalogue with a bare
 *  `fetch("/api/inventory")` and searched it in memory, so on a shop of 285
 *  products it could not sell 85 of them. Searching for one answered "Nothing
 *  matches", which reads as "you do not stock this" - and a shopkeeper
 *  believes the app before they believe the shelf. The same defect was found
 *  and fixed in the mobile client, and never carried across.
 *
 *  So it lives here once rather than in each caller. Three clients dropped
 *  this cursor independently; a fourth will too, unless there is a single
 *  function to reach for.
 */

/** Pages to walk before giving up. 25 x 200 rows is 5,000 items - past any
 *  single shop this app is built for, and short enough that a server looping
 *  on its own cursor stops being a browser tab stuck downloading. */
const MAX_PAGES = 25;

export type FetchAllOptions = {
  /** Rows per request. The server's own default applies when omitted. */
  limit?: number;
  /** Extra query parameters, applied to every page. */
  params?: Record<string, string>;
  /** Ceiling on rows returned, across all pages. */
  max?: number;
  signal?: AbortSignal;
  /** Called when the walk stopped with pages still unread.
   *
   *  The ceiling is real - 25 pages of 200 rows is 5,000 - and a shop can
   *  reach it. Without this the function returns a short list that looks
   *  exactly like a complete one: the very defect it was written to fix,
   *  reappearing one order of magnitude further out. A caller that passes
   *  this can say so on screen; one that does not is no worse off than it
   *  was. */
  onIncomplete?: (loaded: number) => void;
};

export async function fetchAllPages<T = unknown>(
  path: string,
  options: FetchAllOptions = {},
): Promise<T[]> {
  const { limit, params, max, signal, onIncomplete } = options;
  const rows: T[] = [];
  let cursor: string | null = null;
  /** A cursor handed to us that we have NOT spent yet.
   *
   *  Cleared at the top of every request and set only when the server offers
   *  a further page, so after the loop it is non-null in exactly one case:
   *  the page budget ran out while there was still more to read. Asking
   *  "is `cursor` set" instead would be wrong - the last successful request
   *  leaves it set on a perfectly complete walk. */
  let unspentCursor: string | null = null;

  for (let page = 0; page < MAX_PAGES; page++) {
    const query = new URLSearchParams(params ?? {});
    if (limit) query.set("limit", String(limit));
    if (cursor) query.set("cursor", cursor);

    const suffix = query.toString() ? `?${query.toString()}` : "";
    const response = await fetch(`${path}${suffix}`, { signal });
    if (!response.ok) {
      throw new Error(`Failed to load ${path} (${response.status})`);
    }

    const body = await response.json();
    if (!Array.isArray(body)) {
      throw new Error(`${path} did not return a list`);
    }
    rows.push(...(body as T[]));

    // This page is spent. Anything below that stops the walk leaves it clear,
    // which is what makes the check after the loop mean what it says.
    unspentCursor = null;

    const next = response.headers.get("X-Next-Cursor");
    if (!next) break;
    if (max !== undefined && rows.length >= max) break;
    // The same cursor twice means the server made no progress. Stopping with
    // what we have beats looping forever in somebody's browser.
    if (next === cursor) break;
    cursor = next;
    unspentCursor = next;
  }

  // Reached only by running out of pages with more to read. A walk that ended
  // because the server said there was no next page is complete; one cut short
  // by `max` was cut short on purpose by the caller; one that stopped on a
  // repeated cursor stopped because the server was not making progress.
  if (unspentCursor) {
    onIncomplete?.(rows.length);
  }

  return max === undefined ? rows : rows.slice(0, max);
}
