import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** Process a return against this bill. */
export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const body = await req.json().catch(() => ({}));
  return proxyToApi((shopId) => `/shops/${shopId}/sales/${id}/return/`, {
    method: "POST",
    body,
  });
}
