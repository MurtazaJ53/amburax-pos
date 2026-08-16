import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/inventory/${id}/`, {
    method: "PATCH",
    body,
  });
}

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/inventory/${id}/`, {
    method: "DELETE",
  });
}
