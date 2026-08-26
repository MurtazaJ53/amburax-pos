import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** The customer list, one page at a time.
 *
 *  `cursor`, `limit` and `q` are forwarded because the list is keyset-paged.
 *  Without them this route always asks for the first page, and "load more"
 *  returns what is already on screen.
 */
export async function GET(req: NextRequest) {
  const incoming = req.nextUrl.searchParams;
  const params = new URLSearchParams();
  for (const key of ["cursor", "limit", "q"]) {
    const value = incoming.get(key);
    if (value) params.set(key, value);
  }
  const query = params.toString();
  return proxyToApi(
    (shopId) => `/shops/${shopId}/customers/${query ? `?${query}` : ""}`,
  );
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/customers/`, {
    method: "POST",
    body,
  });
}
