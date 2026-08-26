import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



const API_BASE_URL = process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const dateFrom = searchParams.get("date_from") || "";
    const dateTo = searchParams.get("date_to") || "";
    const membershipId = searchParams.get("membership_id") || "";
    const status = searchParams.get("status") || "";
    const q = searchParams.get("q") || "";
    // Keyset-paged now: one attendance row per person per day accumulates
    // forever, and this screen sends no date window of its own.
    const cursor = searchParams.get("cursor") || "";
    const limit = searchParams.get("limit") || "";

    const cookieStore = await cookies();
    const token = cookieStore.get("bh_access_token")?.value;
    const shopId = cookieStore.get("bh_active_shop")?.value;

    if (!token || !shopId) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const backendUrl = new URL(`${API_BASE_URL}/shops/${shopId}/attendance/`);
    if (dateFrom) backendUrl.searchParams.set("date_from", dateFrom);
    if (dateTo) backendUrl.searchParams.set("date_to", dateTo);
    if (membershipId) backendUrl.searchParams.set("membership_id", membershipId);
    if (status) backendUrl.searchParams.set("status", status);
    if (q) backendUrl.searchParams.set("q", q);
    if (cursor) backendUrl.searchParams.set("cursor", cursor);
    if (limit) backendUrl.searchParams.set("limit", limit);

    const res = await fetch(backendUrl.toString(), {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });

    if (!res.ok) {
      const text = await res.text();
      return NextResponse.json({ error: `Backend returned ${res.status}: ${text}` }, { status: res.status });
    }

    const data = await res.json();
    const out = NextResponse.json(data);
    const nextCursor = res.headers.get("X-Next-Cursor");
    if (nextCursor) out.headers.set("X-Next-Cursor", nextCursor);
    return out;
  } catch (error) {
    return NextResponse.json({ error: errorMessage(error, "Internal server error") }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const cookieStore = await cookies();
    const token = cookieStore.get("bh_access_token")?.value;
    const shopId = cookieStore.get("bh_active_shop")?.value;

    if (!token || !shopId) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await req.json();

    const res = await fetch(`${API_BASE_URL}/shops/${shopId}/attendance/`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text();
      return NextResponse.json({ error: `Backend returned ${res.status}: ${text}` }, { status: res.status });
    }

    const data = await res.json();
    return NextResponse.json(data);
  } catch (error) {
    return NextResponse.json({ error: errorMessage(error, "Internal server error") }, { status: 500 });
  }
}
