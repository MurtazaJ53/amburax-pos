import { proxyToApi } from "@/lib/proxy";

/** One stocktake, with every counted line. */
export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/inventory/stocktakes/${id}/`);
}
