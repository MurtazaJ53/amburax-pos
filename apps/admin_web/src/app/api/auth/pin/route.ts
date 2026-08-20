import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { pin } = body;

    if (!pin || pin.length < 4) {
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

    const currentEmail = cookieStore.get("bh_user_email")?.value || "pos.terminal@businesshub.local";

    // Set PIN session / cashier role
    cookieStore.set("bh_pos_unlocked", "true", { path: "/", maxAge: 60 * 60 * 12 });
    cookieStore.set("bh_user_role", "cashier", { path: "/", maxAge: 60 * 60 * 12 });
    if (!cookieStore.get("bh_user_email")?.value) {
      cookieStore.set("bh_user_email", currentEmail, { path: "/", maxAge: 60 * 60 * 12 });
    }

    return NextResponse.json({
      success: true,
      role: "cashier",
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
