import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



const API_BASE_URL = process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      ownerName,
      owner_name,
      email,
      password,
      mobile,
      businessName,
      business_name,
      businessType,
      business_type,
      stateCode,
      state_code,
      gstin,
      planTier,
      plan_tier,
    } = body;

    const payload = {
      owner_name: (ownerName || owner_name || "").trim(),
      email: (email || "").trim().toLowerCase(),
      password,
      // No placeholder fallback. This used to default to "9876543210", which
      // gave every shop that skipped the field a fake number indistinguishable
      // from a real one — unreachable, and impossible to spot later.
      mobile: (mobile || "").trim(),
      business_name: (businessName || business_name || "").trim(),
      business_type: businessType || business_type || "retail",
      state_code: (stateCode || state_code || "").trim(),
      gstin: (gstin || "").trim(),
      plan_tier: planTier || plan_tier || "starter",
    };

    // Mobile is required, not optional. It is how a shop owner is reached
    // about their own account, and the only number WhatsApp reminders can
    // ever send from. Enforced here rather than only in the form, so the
    // rule holds for any caller.
    if (!payload.mobile || payload.mobile.replace(/\D/g, "").length < 10) {
      return NextResponse.json(
        { error: "A 10-digit mobile number is required" },
        { status: 400 }
      );
    }

    if (!payload.email || !payload.password || !payload.owner_name || !payload.business_name) {
      return NextResponse.json(
        { error: "Owner name, business name, email, and password are required" },
        { status: 400 }
      );
    }

    const regRes = await fetch(`${API_BASE_URL}/register/`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(payload),
    });

    if (!regRes.ok) {
      const errData = await regRes.json().catch(() => ({}));
      const message =
        errData.detail ||
        errData.email?.[0] ||
        errData.business_name?.[0] ||
        errData.owner_name?.[0] ||
        errData.password?.[0] ||
        errData.non_field_errors?.[0] ||
        "Registration failed. Please review your details.";
      return NextResponse.json({ error: message }, { status: regRes.status });
    }

    const regData = await regRes.json();
    const accessToken = regData.access;
    const refreshToken = regData.refresh;
    const shopId = regData.shop_id;

    // Set secure cookies
    const cookieStore = await cookies();
    const cookieOptions = {
      path: "/",
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax" as const,
      maxAge: 60 * 60 * 24 * 7,
    };

    if (accessToken) cookieStore.set("bh_access_token", accessToken, cookieOptions);
    if (refreshToken) cookieStore.set("bh_refresh_token", refreshToken, cookieOptions);
    cookieStore.set("bh_user_email", regData.email || payload.email, { path: "/", maxAge: 60 * 60 * 24 * 7 });
    cookieStore.set("bh_user_role", regData.role || "owner", { path: "/", maxAge: 60 * 60 * 24 * 7 });
    if (shopId) cookieStore.set("bh_active_shop", shopId, { path: "/", maxAge: 60 * 60 * 24 * 7 });

    return NextResponse.json({
      success: true,
      shopId,
      shopName: regData.shop_name,
      shopSlug: regData.shop_slug,
      role: regData.role || "owner",
      email: regData.email || payload.email,
      defaultRoute: "/",
    });
  } catch (err) {
    return NextResponse.json(
      { error: errorMessage(err, "An unexpected error occurred during registration") },
      { status: 500 }
    );
  }
}
