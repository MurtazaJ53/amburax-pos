import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/expenses/${id}/`, {
    method: "DELETE",
  });
}
