import { NextRequest, NextResponse } from "next/server";

import { needsRenewal } from "@/lib/token-expiry";

/**
 * Keep the session's access token fresh, in one place.
 *
 * The access token used to last a year, so nothing ever needed renewing and
 * `bh_refresh_token` was written at login and never read again. Shortening the
 * token to twelve hours makes that gap fatal: the cookie survives for seven
 * days, so the browser would keep presenting an expired token and every screen
 * would fail with no way back except signing out by hand.
 *
 * Doing it here rather than in each route is deliberate. Fifty-five route
 * handlers read the token cookie directly, and renewal that lives in only some
 * of them is worse than none — the session would work on the pages that had it
 * and break on the pages that did not.
 *
 * Renewal is proactive rather than a reaction to a 401: the expiry is in the
 * token, so there is no reason to spend a failed request discovering it.
 */
const API_BASE_URL =
  process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

const ACCESS_COOKIE = "bh_access_token";
const REFRESH_COOKIE = "bh_refresh_token";

export async function middleware(req: NextRequest) {
  const access = req.cookies.get(ACCESS_COOKIE)?.value;
  const refresh = req.cookies.get(REFRESH_COOKIE)?.value;

  // Nothing to keep alive. Signed-out requests fall through to the route,
  // which answers 401 as it always did.
  if (!access || !refresh) return NextResponse.next();
  if (!needsRenewal(access)) return NextResponse.next();

  let renewed: { access: string; refresh: string } | null = null;
  try {
    const res = await fetch(`${API_BASE_URL}/session/token/refresh/`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ refresh }),
      cache: "no-store",
    });
    if (res.ok) {
      const data = (await res.json()) as { access?: string; refresh?: string };
      if (data.access) {
        renewed = { access: data.access, refresh: data.refresh ?? refresh };
      }
    }
  } catch {
    // The API is unreachable. Let the request through on the old token so a
    // brief network blip does not read as a sign-out.
  }

  if (!renewed) return NextResponse.next();

  // Hand the new token to the route handler in this same request, not just to
  // the browser for the next one — otherwise the call that triggered the
  // renewal still goes out with the expired token and fails.
  const headers = new Headers(req.headers);
  const jar = req.cookies;
  jar.set(ACCESS_COOKIE, renewed.access);
  jar.set(REFRESH_COOKIE, renewed.refresh);
  headers.set(
    "cookie",
    jar.getAll().map((c) => `${c.name}=${c.value}`).join("; "),
  );

  const response = NextResponse.next({ request: { headers } });
  const options = {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax" as const,
    path: "/",
    maxAge: 60 * 60 * 24 * 7,
  };
  response.cookies.set(ACCESS_COOKIE, renewed.access, options);
  response.cookies.set(REFRESH_COOKIE, renewed.refresh, options);
  return response;
}

export const config = {
  // Only the proxy routes. The auth routes mint and clear these cookies
  // themselves, and renewing underneath a login or logout would fight them.
  matcher: ["/api/((?!auth/).*)"],
};
