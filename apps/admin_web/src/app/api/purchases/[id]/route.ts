import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** One purchase, with the lines it was made of.
 *
 *  The list only ever carried a count of items, so a bill could be entered
 *  line by line and then never read back - "12 items" tells nobody what
 *  arrived or what it cost. This is the route that answers "what was on that
 *  bill", which is also how a wrong entry gets spotted.
 */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/purchases/${id}/`);
}
