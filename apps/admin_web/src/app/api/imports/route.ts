import { proxyToApi } from "@/lib/proxy";

/** Recent imports, newest first.
 *
 *  "Undo the last import" is not what somebody wants when they spot a
 *  mistake - they want the one that went wrong, which may not be the last if
 *  they have imported again since. This is the list they pick from.
 */
export async function GET() {
  return proxyToApi((shopId) => `/shops/${shopId}/imports/`);
}
