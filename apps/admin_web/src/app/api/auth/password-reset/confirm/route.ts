import { NextRequest, NextResponse } from "next/server";

import { clientAddress } from "@/lib/proxy";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

const API_BASE_URL = process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

/**
 * Spend a reset link: {token, password} -> a password sign-in accepts.
 *
 * The token arrives from the query string of the emailed link and goes
 * straight back out to Django. It is never written to a cookie and no session
 * is issued here: the person types their new password into the sign-in form
 * like anybody else, which is one fewer way to end up signed in as somebody
 * whose email was forwarded.
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({}));
    const token = typeof body?.token === "string" ? body.token.trim() : "";
    const password = typeof body?.password === "string" ? body.password : "";

    if (!token) {
      return NextResponse.json(
        { error: "This reset link is missing its token. Please use the link from the email." },
        { status: 400 },
      );
    }
    if (!password || password.length < 8) {
      return NextResponse.json(
        { error: "Choose a password of at least 8 characters." },
        { status: 400 },
      );
    }

    let res: Response;
    const forwardedFor = await clientAddress();
    try {
      res = await fetch(`${API_BASE_URL}/session/password-reset/confirm/`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          ...(forwardedFor ? { "X-Forwarded-For": forwardedFor } : {}),
        },
        body: JSON.stringify({ token, password }),
        cache: "no-store",
      });
    } catch {
      return NextResponse.json(
        {
          error:
            "Cannot reach the Business Hub server, so your password was not changed. " +
            "Please try again in a moment.",
        },
        { status: 503 },
      );
    }

    const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;

    if (!res.ok) {
      const passwordErrors = data.password;
      const message =
        (typeof data.detail === "string" && data.detail) ||
        (Array.isArray(passwordErrors) &&
          typeof passwordErrors[0] === "string" &&
          passwordErrors[0]) ||
        "That reset link could not be used. Please request a new one.";
      return NextResponse.json({ error: message }, { status: res.status });
    }

    return NextResponse.json({
      success: true,
      detail: data.detail,
      email: typeof data.email === "string" ? data.email : "",
    });
  } catch (err) {
    return NextResponse.json(
      {
        error: errorMessage(
          err,
          "An unexpected error occurred. Your password may not have been changed.",
        ),
      },
      { status: 500 },
    );
  }
}
