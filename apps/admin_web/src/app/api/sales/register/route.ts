import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** The end-of-day register close.
 *
 *  This used to live in localStorage, which meant the over/short figure - the
 *  one number that can get a cashier accused of taking money - existed on a
 *  single machine and died with a cleared browser. It is a server record now.
 */
export async function GET(req: NextRequest) {
  const date = req.nextUrl.searchParams.get("date");
  const query = date ? `?date=${encodeURIComponent(date)}` : "";
  return proxyToApi((shopId) => `/shops/${shopId}/sales/register/${query}`);
}

export async function PUT(req: NextRequest) {
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/sales/register/`, {
    method: "PUT",
    body,
  });
}
