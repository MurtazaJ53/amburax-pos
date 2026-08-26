import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** One supplier.
 *
 *  SupplierDetailView on the server has been a RetrieveUpdateDestroy view all
 *  along, so correcting a vendor's phone number or address was always
 *  possible - there was simply no route here to reach it. A number typed
 *  wrong once stayed wrong, and the only way round it was a second supplier
 *  record for the same vendor, which splits their balance and their price
 *  history in two.
 *
 *  Deleting is deliberately not exposed. A supplier carries a ledger, a
 *  balance and every price ever paid to them; removing one is not a
 *  correction, and the fix for a vendor you no longer use is to stop
 *  choosing them.
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/suppliers/${id}/`);
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/suppliers/${id}/`, {
    method: "PATCH",
    body,
  });
}
