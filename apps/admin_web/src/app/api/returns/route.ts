import { proxyToApi } from "@/lib/proxy";

/** Returns processed by this shop. */
export async function GET() {
  return proxyToApi((shopId) => `/shops/${shopId}/returns/`);
}
