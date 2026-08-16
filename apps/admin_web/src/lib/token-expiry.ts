/**
 * Reading the expiry out of a JWT without verifying it.
 *
 * The server verifies the signature; this only needs to know when to renew, so
 * decoding the payload is enough. Kept out of the middleware file so it can be
 * tested — the middleware itself runs on the edge runtime and is awkward to
 * exercise directly, and this is the part that decides whether a session
 * survives the day.
 */

/** Seconds until this token expires. Zero for anything unreadable. */
export function secondsUntilExpiry(token: string, nowMs: number = Date.now()): number {
  try {
    const [, payload] = token.split(".");
    if (!payload) return 0;
    // Base64url, and atob is the only decoder available on the edge runtime.
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    const exp = (JSON.parse(json) as { exp?: number }).exp;
    if (typeof exp !== "number") return 0;
    return exp - Math.floor(nowMs / 1000);
  } catch {
    // Unreadable means unusable. Treating it as expired sends it down the
    // refresh path, which fails cleanly, rather than to Django as garbage.
    return 0;
  }
}

/** Renew this long before expiry: longer than any single request can take. */
export const RENEW_WITHIN_SECONDS = 5 * 60;

/** Whether this token should be exchanged before the request goes out. */
export function needsRenewal(token: string, nowMs: number = Date.now()): boolean {
  return secondsUntilExpiry(token, nowMs) <= RENEW_WITHIN_SECONDS;
}
