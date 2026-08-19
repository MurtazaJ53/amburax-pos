import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

import { clientAddress } from "@/lib/proxy";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



const API_BASE_URL = process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { email, password } = body;

    if (!email || !password) {
      return NextResponse.json(
        { error: "Email and password are required" },
        { status: 400 }
      );
    }

    // 1. Call Backend Session Token API
    let tokenRes: Response;
    const forwardedFor = await clientAddress();

    try {
      tokenRes = await fetch(`${API_BASE_URL}/session/token/`, {
        method: "POST",
        // The caller's address, so Django rate-limits sign-in attempts per
        // person rather than lumping the whole website into one bucket. This
        // is the endpoint where that matters most: five failed attempts from
        // anyone would otherwise lock out everybody.
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          ...(forwardedFor ? { "X-Forwarded-For": forwardedFor } : {}),
        },
        body: JSON.stringify({ email: email.trim(), password }),
      });
    } catch {
      // No offline fallback. This used to grant a session with NO password
      // check to any address containing "demo", "owner" or "admin" whenever
      // the backend was unreachable — and "admin" got platform_admin. Anyone
      // able to disrupt the network path (public wifi, DNS) could walk into
      // the admin UI. An unreachable backend means we cannot authenticate,
      // so say so.
      return NextResponse.json(
        { error: "Cannot reach backend server. Please check your connection." },
        { status: 503 }
      );
    }

    if (!tokenRes.ok) {
      const errData = await tokenRes.json().catch(() => ({}));
      const message =
        errData.detail ||
        errData.non_field_errors?.[0] ||
        errData.error ||
        "Invalid email or password. Please check your credentials.";
      return NextResponse.json({ error: message }, { status: tokenRes.status });
    }

    const tokenData = await tokenRes.json();
    const accessToken = tokenData.access;
    const refreshToken = tokenData.refresh;

    // 2. Fetch User Profile and Shop Memberships
    let sessionUser: Record<string, unknown> = {
      email,
      full_name: email.split("@")[0],
    };
    // Only the fields this route reads from the session payload.
    type SessionMembership = {
      status?: string;
      role?: string;
      shop_id?: string;
      shop?: { id?: string };
    };
    let memberships: SessionMembership[] = [];
    let activeShopId = "";
    let userRole = "owner";

    try {
      const sessionRes = await fetch(`${API_BASE_URL}/session/`, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: "application/json",
        },
      });

      if (sessionRes.ok) {
        const sessionData = await sessionRes.json();
        sessionUser = sessionData.user || sessionUser;
        memberships = sessionData.memberships || [];
        if (memberships.length > 0) {
          const firstActive = memberships.find((m) => m.status === "active") || memberships[0];
          activeShopId = firstActive.shop?.id || firstActive.shop_id || "";
          userRole = firstActive.role || "owner";
        }
      }
    } catch {
      // Session fetch error handled gracefully
    }

    // 3. Set Secure Cookies
    const cookieStore = await cookies();
    const cookieOptions = {
      path: "/",
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax" as const,
      maxAge: 60 * 60 * 24 * 7, // 7 days
    };

    cookieStore.set("bh_access_token", accessToken, cookieOptions);
    if (refreshToken) {
      cookieStore.set("bh_refresh_token", refreshToken, cookieOptions);
    }
    cookieStore.set("bh_user_email", sessionUser.email || email, { path: "/", maxAge: 60 * 60 * 24 * 7 });
    cookieStore.set("bh_user_role", sessionUser.is_platform_admin ? "platform_admin" : userRole, { path: "/", maxAge: 60 * 60 * 24 * 7 });
    if (activeShopId) {
      cookieStore.set("bh_active_shop", activeShopId, { path: "/", maxAge: 60 * 60 * 24 * 7 });
    }

    return NextResponse.json({
      success: true,
      user: sessionUser,
      memberships,
      activeShopId,
      role: sessionUser.is_platform_admin ? "platform_admin" : userRole,
      defaultRoute: userRole === "cashier" ? "/pos" : "/",
    });
  } catch (err) {
    return NextResponse.json(
      { error: errorMessage(err, "An unexpected error occurred during sign in") },
      { status: 500 }
    );
  }
}
