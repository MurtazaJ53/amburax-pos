import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";

import { clientAddress } from "@/lib/proxy";

/** One product's photo, passed through as an image.
 *
 *  This route deliberately does not use proxyToApi, which parses every
 *  response as JSON. That is right for the rest of the API and wrong here: the
 *  point of moving photos out of the product list is that a picture is fetched
 *  from its own address, so the browser can cache it. Turning it into JSON on
 *  the way through would give up exactly what was gained.
 *
 *  The cache headers are forwarded rather than invented. Django computes the
 *  ETag from the image bytes, and passing the browser's If-None-Match back
 *  lets it answer "not modified" with no body - which is what stops every
 *  photo being downloaded again each time a cache expires.
 */
const API_BASE_URL =
  process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const cookieStore = await cookies();
  const token = cookieStore.get("bh_access_token")?.value;
  const shopId = cookieStore.get("bh_active_shop")?.value;
  if (!token || !shopId) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const headers: Record<string, string> = { Authorization: `Bearer ${token}` };
  const forwarded = await clientAddress();
  if (forwarded) headers["X-Forwarded-For"] = forwarded;
  const ifNoneMatch = req.headers.get("if-none-match");
  if (ifNoneMatch) headers["If-None-Match"] = ifNoneMatch;

  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}/shops/${shopId}/inventory/${id}/image/`, {
      headers,
      cache: "no-store",
    });
  } catch {
    // A picture that cannot be fetched is not worth an error page. The screen
    // falls back to the product's initial, which is what it already shows for
    // a product that never had one.
    return new NextResponse(null, { status: 404 });
  }

  if (res.status === 304) return new NextResponse(null, { status: 304 });
  if (!res.ok) return new NextResponse(null, { status: res.status });

  const body = await res.arrayBuffer();
  const out = new NextResponse(body, { status: 200 });
  out.headers.set("Content-Type", res.headers.get("Content-Type") ?? "image/jpeg");
  const etag = res.headers.get("ETag");
  if (etag) out.headers.set("ETag", etag);
  out.headers.set(
    "Cache-Control",
    res.headers.get("Cache-Control") ?? "private, max-age=2592000",
  );
  return out;
}
