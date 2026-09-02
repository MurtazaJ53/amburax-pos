import { NextRequest, NextResponse } from "next/server";

import { clientAddress } from "@/lib/proxy";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

const API_BASE_URL = process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

/**
 * "I forgot my password" - ask Django to email a reset link.
 *
 * Server-side like every other call in this app: the browser never speaks to
 * the API directly and never holds anything. There is no cookie to set here,
 * because whoever is asking has no session yet - that is the whole problem
 * they are trying to solve.
 *
 * Django's answer is passed through as it is. Two things about it matter: the
 * 200 is identical whether or not the address has an account, so this route
 * must not add anything that distinguishes them; and a failed send comes back
 * as a 502, which must reach the screen as a failure rather than being
 * smoothed into a reassuring message about checking an inbox.
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({}));
    const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";

    if (!email) {
      return NextResponse.json({ error: "Email is required" }, { status: 400 });
    }

    let res: Response;
    const forwardedFor = await clientAddress();
    try {
      res = await fetch(`${API_BASE_URL}/session/password-reset/`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          // The caller's address, so Django rate-limits per person rather than
          // treating this whole server as one visitor. The limit is five an
          // hour, and without this header everybody shares it.
          ...(forwardedFor ? { "X-Forwarded-For": forwardedFor } : {}),
        },
        body: JSON.stringify({ email }),
        cache: "no-store",
      });
    } catch {
      // An unreachable API means no email was sent. Say that, rather than
      // returning the same soothing "check your inbox" the success path uses.
      return NextResponse.json(
        {
          error:
            "Cannot reach the Business Hub server, so no reset email was sent. " +
            "Please check your connection and try again.",
          emailSent: false,
        },
        { status: 503 },
      );
    }

    const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;

    if (!res.ok) {
      const emailErrors = data.email;
      const message =
        (typeof data.detail === "string" && data.detail) ||
        (Array.isArray(emailErrors) && typeof emailErrors[0] === "string" && emailErrors[0]) ||
        "The reset email could not be sent. Please try again shortly.";
      return NextResponse.json({ error: message, emailSent: false }, { status: res.status });
    }

    // Django says the same sentence, in the same shape, for an address with an
    // account and one without - and this route must not add a field that tells
    // them apart. An "emailSent" flag here did exactly that: false for an
    // unknown address, true for a delivered one, which is the enumeration hole
    // the identical 200 exists to close. A send that failed never reaches this
    // line; it arrives as the 502 handled above.
    return NextResponse.json({ success: true, detail: data.detail });
  } catch (err) {
    return NextResponse.json(
      { error: errorMessage(err, "An unexpected error occurred. No reset email was sent.") },
      { status: 500 },
    );
  }
}
