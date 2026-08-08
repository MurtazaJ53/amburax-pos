import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function GET(req: NextRequest) {
  const date = req.nextUrl.searchParams.get("date");
  const query = date ? `?date=${encodeURIComponent(date)}` : "";
  return proxyToApi((shopId) => `/shops/${shopId}/reports/day-book/${query}`);
}
