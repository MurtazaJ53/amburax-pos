import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** The sales list.
 *
 *  Django has always accepted a date window, a payment mode and a search
 *  term here; this route forwarded none of them, so History could only ever
 *  filter whatever page of sales the browser happened to hold. A year-old
 *  bill was simply unreachable.
 *
 *  Only the parameters the server understands are passed on, so a stray
 *  query string cannot be used to shape the request.
 */
const FORWARDED = ["date_from", "date_to", "payment_mode", "status", "q", "limit"] as const;

export async function GET(req: NextRequest) {
  const query = new URLSearchParams();
  for (const key of FORWARDED) {
    const value = req.nextUrl.searchParams.get(key);
    if (value) query.set(key, value);
  }
  const suffix = query.toString() ? `?${query.toString()}` : "";
  return proxyToApi((shopId) => `/shops/${shopId}/sales/${suffix}`);
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/sales/`, {
    method: "POST",
    body,
  });
}
