import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const body = await req.json().catch(() => ({}));
  return proxyToApi(
    (shopId) => `/shops/${shopId}/inventory/stocktakes/${id}/cancel/`,
    { method: "POST", body },
  );
}
