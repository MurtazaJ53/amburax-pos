import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/customers/${id}/timeline/`);
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const body = await req.json();
  return proxyToApi((shopId) => `/shops/${shopId}/customers/${id}/ledger/`, {
    method: "POST",
    body,
  });
}
