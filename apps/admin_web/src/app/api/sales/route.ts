import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function GET() {
  return proxyToApi((shopId) => `/shops/${shopId}/sales/`);
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/sales/`, {
    method: "POST",
    body,
  });
}
