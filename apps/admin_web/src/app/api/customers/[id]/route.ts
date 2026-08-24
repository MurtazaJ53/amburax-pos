import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** One customer.
 *
 *  CustomerDetailView on the server has been a RetrieveUpdateDestroy view all
 *  along, so editing a customer was always possible — there was simply no
 *  route here to reach it from the browser, and therefore no way in the web
 *  app to correct a misspelled name or a wrong phone number.
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/customers/${id}/`);
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/customers/${id}/`, {
    method: "PATCH",
    body,
  });
}
