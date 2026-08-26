import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** The product list, one page at a time.
 *
 *  `cursor` and `limit` are forwarded because the list is keyset-paged now.
 *  Without them this route would always ask for the first page, and the screen
 *  would load the same fifty products forever while believing it had more.
 */
export async function GET(req: NextRequest) {
  const incoming = req.nextUrl.searchParams;
  const params = new URLSearchParams();
  for (const key of ["cursor", "limit"]) {
    const value = incoming.get(key);
    if (value) params.set(key, value);
  }
  const query = params.toString();
  return proxyToApi(
    (shopId) => `/shops/${shopId}/inventory/${query ? `?${query}` : ""}`,
  );
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/inventory/`, {
    method: "POST",
    body,
  });
}
