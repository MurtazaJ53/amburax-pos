import { proxyToApi } from "@/lib/proxy";

/** The next free product code, for one still being typed in.
 *
 *  A suggestion, not a reservation - nothing is held until the product is
 *  saved. Two people adding a product at the same moment would be offered the
 *  same code, which is an acceptable trade for a counter convenience and is
 *  said out loud in the view rather than hidden.
 */
export async function GET() {
  return proxyToApi((shopId) => `/shops/${shopId}/inventory/suggest-sku/`);
}
