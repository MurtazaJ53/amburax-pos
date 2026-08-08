import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** Email a purchase order to its supplier. */
export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const body = await req.json().catch(() => ({}));
  return proxyToApi(
    (shopId) => `/shops/${shopId}/purchase-orders/${id}/send/`,
    { method: "POST", body },
  );
}
