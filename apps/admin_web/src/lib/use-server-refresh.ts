"use client";

import { useRouter } from "next/navigation";
import { useCallback } from "react";

/** Pull this page's server-rendered figures again after a write.
 *
 *  Every screen here is a server component that fetches its data and hands it
 *  to a client component as props. Those props are rendered once, on the
 *  server. A client component that saves something and then re-fetches its
 *  own list updates that list and nothing else - the summary tiles above it,
 *  the counts in the header and anything else the page fetched are still the
 *  figures from when the page was opened.
 *
 *  That is why a change appeared to need a reload, or a trip to another
 *  screen and back: both re-run the server component, which was the only
 *  thing refreshing those numbers.
 *
 *  router.refresh() re-runs it in place. The server data is fetched again and
 *  reconciled into the page while client state - open dialogs, what is typed,
 *  scroll position - is kept, which a reload would throw away.
 *
 *  Call it after a write succeeds, alongside any local re-fetch rather than
 *  instead of one: the local fetch updates the list immediately, this brings
 *  the rest of the page with it.
 */
export function useServerRefresh(): () => void {
  const router = useRouter();
  return useCallback(() => {
    router.refresh();
  }, [router]);
}
