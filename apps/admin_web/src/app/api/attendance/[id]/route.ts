import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/attendance/${id}/`, {
    method: "PATCH",
    body,
  });
}
