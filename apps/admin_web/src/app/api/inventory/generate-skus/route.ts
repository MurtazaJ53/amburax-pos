import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** Give products that cannot be printed a code that can be.
 *
 *  The label screen could only report that a product needed a SKU - once per
 *  product, a few hundred times - and offered no way to act on it. Typing
 *  them by hand is not a real answer at that scale, so this is the route that
 *  makes the message actionable.
 */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  return proxyToApi((shopId) => `/shops/${shopId}/inventory/generate-skus/`, {
    method: "POST",
    body,
  });
}
