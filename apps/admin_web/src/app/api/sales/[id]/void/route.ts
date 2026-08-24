import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  // The browser posts, but SaleVoidView on the server implements patch().
  // Forwarding POST made every void fail with "Method POST not allowed".
  return proxyToApi((shopId) => `/shops/${shopId}/sales/${id}/void/`, {
    method: "PATCH",
    body: {},
  });
}
