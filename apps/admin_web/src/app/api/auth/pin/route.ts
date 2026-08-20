import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

const API_BASE_URL =
  process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { pin } = body;

    if (!pin || String(pin).length < 4) {
      return NextResponse.json(
        { error: "Please enter a valid 4-digit PIN" },
        { status: 400 }
      );
    }

    const cookieStore = await cookies();

    // A PIN here re-opens a session that already exists; it is not a way in.
    // The endpoint used to hand role=cashier to any caller who posted four
    // digits, with no shop, no session and no check against pos_pin_hash —
    // a gate labelled SECURE PIN that verified nothing. Requiring a signed-in
    // session first makes it a screen lock, which is what it actually is.
    const token = cookieStore.get("bh_access_token")?.value;
    const activeShop = cookieStore.get("bh_active_shop")?.value;
    if (!token || !activeShop) {
      return NextResponse.json(
        { error: "Sign in on this device first. The PIN unlocks an existing session." },
        { status: 401 }
      );
    }

    // The other half of the same fix. Requiring a session stopped the PIN
    // being a way in, but the digits themselves were still never checked: any
    // four would unlock the till, so one cashier could open another's session
    // and every sale after it would carry the wrong name. The server owns the
    // comparison, because the hash must never reach the browser and the
    // attempt has to be counted somewhere an attacker cannot reset.
    const verify = await fetch(
      `${API_BASE_URL}/shops/${activeShop}/pos-pin/verify/`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ pin: String(pin) }),
        cache: "no-store",
      }
    );

    if (!verify.ok) {
      const detail = await verify.json().catch(() => null);
      // Pass the server's own status through. A wrong PIN is 401, a PIN that
      // was never set is 409, and too many attempts is 429 — the lock screen
      // needs to tell those three apart or it sends a cashier round in circles.
      return NextResponse.json(
        {
          error:
            typeof detail?.detail === "string"
              ? detail.detail
              : "That PIN is not correct.",
          code: typeof detail?.code === "string" ? detail.code : undefined,
        },
        { status: verify.status }
      );
    }

    const verified = await verify.json();
    // The role comes from the membership the server just checked, not from a
    // constant. Handing every unlock "cashier" would have quietly demoted an
    // owner on their own till.
    const role = typeof verified?.role === "string" ? verified.role : "cashier";

    const currentEmail =
      cookieStore.get("bh_user_email")?.value || "pos.terminal@businesshub.local";

    cookieStore.set("bh_pos_unlocked", "true", { path: "/", maxAge: 60 * 60 * 12 });
    cookieStore.set("bh_user_role", role, { path: "/", maxAge: 60 * 60 * 12 });
    if (!cookieStore.get("bh_user_email")?.value) {
      cookieStore.set("bh_user_email", currentEmail, { path: "/", maxAge: 60 * 60 * 12 });
    }

    return NextResponse.json({
      success: true,
      role,
      shopId: activeShop,
      defaultRoute: "/pos",
    });
  } catch (err) {
    return NextResponse.json(
      { error: errorMessage(err, "Failed to authenticate PIN") },
      { status: 500 }
    );
  }
}
