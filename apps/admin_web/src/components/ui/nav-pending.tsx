"use client";

import { useLinkStatus } from "next/link";
import { Loader2 } from "lucide-react";

/** A spinner on the link that is currently being navigated to.
 *
 *  Every screen in this app is server-rendered, and each render makes two or
 *  three calls to the API before it can return any HTML. Next keeps the
 *  CURRENT page on screen until the next one is ready, which is the right
 *  behaviour and also means that for two or three seconds a tap on Stock does
 *  nothing observable at all. The app is working; it simply looks broken, so
 *  the tap gets repeated.
 *
 *  This does not make navigation faster. It makes it answer. A control that
 *  acknowledges a press within about a hundred milliseconds feels responsive
 *  even when the work behind it takes seconds, and one that stays silent
 *  feels broken even when it is quick.
 *
 *  Must be rendered INSIDE a <Link>: useLinkStatus reads the pending state of
 *  the nearest one above it.
 */
export function NavPending() {
  const { pending } = useLinkStatus();

  if (!pending) return null;

  return (
    <Loader2
      className="ml-auto h-3.5 w-3.5 shrink-0 animate-spin text-[var(--primary)]"
      aria-hidden="true"
    />
  );
}
