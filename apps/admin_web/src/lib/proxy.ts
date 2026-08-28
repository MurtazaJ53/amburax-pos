import { cookies, headers as nextHeaders } from "next/headers";
import { NextResponse } from "next/server";

/**
 * Shared plumbing for the /api/* proxy routes.
 *
 * Every route does the same four things: read the token and active shop from
 * HTTP-only cookies, call Django with the token attached, pass the status
 * through, and never let the token near the browser. The existing routes each
 * spell that out again, so a fix has to be made in fifty places. New routes
 * use this.
 */
const API_BASE_URL = process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

type ProxyContext = { token: string; shopId: string };

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

/** The client address as nginx recorded it, for onward rate limiting. */
export async function clientAddress(): Promise<string> {
  const incoming = await nextHeaders();
  return incoming.get("x-forwarded-for") ?? incoming.get("x-real-ip") ?? "";
}

async function readContext(): Promise<ProxyContext | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get("bh_access_token")?.value;
  const shopId = cookieStore.get("bh_active_shop")?.value;
  if (!token || !shopId) return null;
  return { token, shopId };
}

/**
 * Call a shop-scoped Django endpoint and return its response verbatim.
 *
 * `path` is templated with the active shop id, so callers never choose which
 * shop they are acting on -- that comes from the session cookie, not from
 * anything the browser sent.
 */
export async function proxyToApi(
  buildPath: (shopId: string) => string,
  init: { method?: string; body?: unknown } = {},
): Promise<NextResponse> {
  try {
    const context = await readContext();
    if (!context) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const headers: Record<string, string> = {
      Authorization: `Bearer ${context.token}`,
      Accept: "application/json",
    };
    // Pass the caller's address through to Django. Without it every request
    // arrives from this container, so the whole site shares one rate-limit
    // bucket and five failed sign-ins lock everybody out at once.
    //
    // Forwarded exactly as received: nginx appends the peer address it observed
    // to the end of the chain, and Django counts from the end (NUM_PROXIES), so
    // a value the browser invented sits earlier in the list and is ignored.
    const forwarded = await clientAddress();
    if (forwarded) headers["X-Forwarded-For"] = forwarded;
    if (init.body !== undefined) headers["Content-Type"] = "application/json";

    const res = await fetch(`${API_BASE_URL}${buildPath(context.shopId)}`, {
      method: init.method ?? "GET",
      headers,
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      cache: "no-store",
    });

    const text = await res.text();
    if (!res.ok) {
      // Django's own validation messages are the useful part -- "only 3 in
      // stock, cannot send 5" is worth showing. Pass it through rather than
      // flattening every failure to "Backend returned 400".
      return NextResponse.json(
        { error: extractDetail(text, res.status) },
        { status: res.status },
      );
    }

    const out = NextResponse.json(text ? JSON.parse(text) : {});
    // The next-page cursor rides in a header so the body can stay the shape
    // every existing client already parses. It has to be forwarded here or it
    // stops at this hop and the screen never learns there is more to load.
    // Paging travels in headers so the body stays a bare array - the mobile
    // client throws on anything else. Forwarded here rather than in each
    // route, because a route that forgets one pages silently wrongly.
    for (const header of [
      "X-Next-Cursor",
      "X-Total-Count",
      "X-Page-Count",
      "X-Page",
    ]) {
      const value = res.headers.get(header);
      if (value) out.headers.set(header, value);
    }
    return out;
  } catch (error) {
    return NextResponse.json(
      { error: errorMessage(error, "Could not reach the Business Hub API.") },
      { status: 502 },
    );
  }
}

/** Pull a readable sentence out of a DRF error body. */
function extractDetail(text: string, status: number): string {
  try {
    const parsed = JSON.parse(text);
    if (typeof parsed?.detail === "string") return parsed.detail;
    for (const value of Object.values(parsed ?? {})) {
      if (typeof value === "string") return value;
      if (Array.isArray(value) && typeof value[0] === "string") return value[0];
    }
  } catch {
    // Not JSON -- an HTML error page, most likely.
  }
  return `The server returned ${status}.`;
}
