import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/**
 * What the shop has been paying, per item and supplier.
 *
 * `item_id` is forwarded so the detail view can pull the full series behind a
 * headline figure — the overview omits the points to keep the payload small.
 */
export async function GET(req: NextRequest) {
  const itemId = req.nextUrl.searchParams.get("item_id") ?? "";
  const supplierId = req.nextUrl.searchParams.get("supplier_id") ?? "";
  const query = new URLSearchParams();
  if (itemId) query.set("item_id", itemId);
  if (supplierId) query.set("supplier_id", supplierId);
  const suffix = query.toString() ? `?${query.toString()}` : "";

  return proxyToApi(
    (shopId) => `/shops/${shopId}/purchases/price-history/${suffix}`,
  );
}
