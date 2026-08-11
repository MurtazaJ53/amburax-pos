import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** Stocktakes for this shop. */
export async function GET() {
  return proxyToApi((shopId) => `/shops/${shopId}/inventory/stocktakes/`);
}

/** Begin a count. The backend refuses a second open one. */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  return proxyToApi((shopId) => `/shops/${shopId}/inventory/stocktakes/`, {
    method: "POST",
    body,
  });
}
