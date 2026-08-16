import { describe, expect, it } from "vitest";

import { RENEW_WITHIN_SECONDS, needsRenewal, secondsUntilExpiry } from "./token-expiry";

/** A JWT-shaped string with the given payload. Signature is never checked here. */
function tokenWith(payload: Record<string, unknown>): string {
  const b64 = Buffer.from(JSON.stringify(payload))
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  return `header.${b64}.signature`;
}

const NOW = 1_760_000_000_000; // fixed clock, in ms
const NOW_S = Math.floor(NOW / 1000);

describe("secondsUntilExpiry", () => {
  it("reads exp out of the payload", () => {
    expect(secondsUntilExpiry(tokenWith({ exp: NOW_S + 3600 }), NOW)).toBe(3600);
  });

  it("goes negative once the token has expired", () => {
    expect(secondsUntilExpiry(tokenWith({ exp: NOW_S - 60 }), NOW)).toBe(-60);
  });

  it("treats anything unreadable as expired", () => {
    // Garbage must take the refresh path, which fails cleanly, rather than
    // being forwarded to Django as a credential.
    expect(secondsUntilExpiry("", NOW)).toBe(0);
    expect(secondsUntilExpiry("not-a-jwt", NOW)).toBe(0);
    expect(secondsUntilExpiry("a.!!!not-base64!!!.c", NOW)).toBe(0);
    expect(secondsUntilExpiry(tokenWith({ sub: "u1" }), NOW)).toBe(0);
  });

  it("decodes base64url, not plain base64", () => {
    // Real tokens routinely contain - and _ where base64 would use + and /.
    // Getting this wrong makes a valid token look unreadable, so every request
    // would trigger a pointless refresh.
    const payload = { exp: NOW_S + 900, sub: "ÿÿÿ~~~???" };
    expect(secondsUntilExpiry(tokenWith(payload), NOW)).toBe(900);
  });
});

describe("needsRenewal", () => {
  it("leaves a token with plenty of life alone", () => {
    expect(needsRenewal(tokenWith({ exp: NOW_S + 3600 }), NOW)).toBe(false);
  });

  it("renews before expiry, not after", () => {
    // The margin has to exceed how long a request can take, or a token that
    // passed the check could expire midway through the call it passed for.
    expect(needsRenewal(tokenWith({ exp: NOW_S + RENEW_WITHIN_SECONDS - 1 }), NOW))
      .toBe(true);
    expect(needsRenewal(tokenWith({ exp: NOW_S + RENEW_WITHIN_SECONDS + 1 }), NOW))
      .toBe(false);
  });

  it("renews an already-expired token", () => {
    expect(needsRenewal(tokenWith({ exp: NOW_S - 1 }), NOW)).toBe(true);
  });

  it("renews an unreadable token", () => {
    expect(needsRenewal("junk", NOW)).toBe(true);
  });
});
