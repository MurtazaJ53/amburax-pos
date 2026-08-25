import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** One expense.
 *
 *  ExpenseDetailView on the server has been a RetrieveUpdateDestroy view all
 *  along, so correcting an entry was always possible - there was simply no
 *  route here to reach it, and the only way to fix a wrong amount was to
 *  delete the row and type it again, which loses who recorded it and when.
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/expenses/${id}/`);
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/expenses/${id}/`, {
    method: "PATCH",
    body,
  });
}

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/expenses/${id}/`, {
    method: "DELETE",
  });
}
