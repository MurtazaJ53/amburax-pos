import { proxyToApi } from "@/lib/proxy";

export async function GET() {
  return proxyToApi((shopId) => `/shops/${shopId}/team/`);
}
