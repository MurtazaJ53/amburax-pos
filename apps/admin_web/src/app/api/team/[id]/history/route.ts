import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** One person's attendance and selling, over one window.
 *
 *  The product could say who is on the team, who worked today and who sold
 *  the most - each from its own table - and could not say how one person is
 *  doing. This is the join.
 */
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const query = new URLSearchParams();
  for (const key of ["date_from", "date_to"]) {
    const value = req.nextUrl.searchParams.get(key);
    if (value) query.set(key, value);
  }
  const suffix = query.toString() ? `?${query.toString()}` : "";
  return proxyToApi((shopId) => `/shops/${shopId}/team/${id}/history/${suffix}`);
}
