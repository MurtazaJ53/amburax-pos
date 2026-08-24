import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** Takings for any date window: totals, payment mix, and a series.
 *
 *  The window is passed straight through. It is only ever a pair of dates,
 *  and the server clamps the span and picks the bucketing itself.
 */
export async function GET(req: NextRequest) {
  const from = req.nextUrl.searchParams.get("from") ?? "";
  const to = req.nextUrl.searchParams.get("to") ?? "";
  const query = new URLSearchParams();
  if (from) query.set("from", from);
  if (to) query.set("to", to);
  const suffix = query.toString() ? `?${query.toString()}` : "";
  return proxyToApi((shopId) => `/shops/${shopId}/sales/takings/${suffix}`);
}
