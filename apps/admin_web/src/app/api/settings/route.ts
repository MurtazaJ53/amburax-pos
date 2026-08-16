import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function GET() {
  return proxyToApi((shopId) => `/shops/${shopId}/settings/`);
}

export async function PATCH(req: NextRequest) {
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/settings/`, {
    method: "PATCH",
    body,
  });
}
