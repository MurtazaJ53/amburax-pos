import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** Pending invites, with the code needed to accept each one.
 *
 *  This route was POST-only, so the Team page could create an invite and then
 *  never see it again: a GET answered 405, no pending list could be drawn,
 *  and the code was visible only in the browser's network trace. With no SMTP
 *  configured the emailed link never arrives either, which left a shop with
 *  no way whatsoever to add a second person.
 *
 *  The backend has always served this and always returned the code to the
 *  inviter. Only this hop was missing.
 */
export async function GET() {
  return proxyToApi((shopId) => `/shops/${shopId}/invites/`);
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/invites/`, {
    method: "POST",
    body,
  });
}
