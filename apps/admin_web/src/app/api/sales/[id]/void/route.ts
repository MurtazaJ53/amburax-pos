import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/sales/${id}/void/`, {
    method: "POST",
    body: {},
  });
}
