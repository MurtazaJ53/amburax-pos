import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** Takings for any date window: totals, payment mix, and a series.
 *
 *  The window is passed straight through. It is only ever a pair of dates,
 *  and the server clamps the span and picks the bucketing itself.
 */
export async function GET(req: NextRequest) {
  const query = new URLSearchParams();
  for (const key of ["from", "to", "all"]) {
    const value = req.nextUrl.searchParams.get(key);
    if (value) query.set(key, value);
  }
  const suffix = query.toString() ? `?${query.toString()}` : "";
  return proxyToApi((shopId) => `/shops/${shopId}/sales/takings/${suffix}`);
}
