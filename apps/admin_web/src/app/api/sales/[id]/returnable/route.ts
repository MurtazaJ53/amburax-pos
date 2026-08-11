import { proxyToApi } from "@/lib/proxy";

/**
 * What is still returnable on this bill, after any earlier returns.
 *
 * Read before showing the return form, so the form offers only quantities that
 * can actually be accepted rather than letting the counter submit something
 * the server will reject with a customer waiting.
 */
export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/sales/${id}/returnable/`);
}
