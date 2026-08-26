import { NextRequest } from "next/server";

import { proxyToApi } from "@/lib/proxy";

/** Take back what one import created.
 *
 *  Rows that have been used since - a product that has sold, a customer who
 *  owes money - are kept and reported rather than removed, so this can come
 *  back having done only part of the job. That is the point.
 */
export async function POST(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyToApi((shopId) => `/shops/${shopId}/imports/${id}/undo/`, {
    method: "POST",
    body: {},
  });
}
