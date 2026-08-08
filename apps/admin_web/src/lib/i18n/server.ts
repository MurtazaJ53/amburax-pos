import { cookies } from "next/headers";

import { isLocale, translatorFor, type Locale, type Translate } from "@/lib/i18n/shared";

/**
 * Translation for server components.
 *
 * `useT()` is a hook and cannot run on the server, so server-rendered tables
 * had no way to reach the dictionary and kept their English hardcoded. This
 * reads the same cookie the root layout reads, so the first paint is already
 * in the right language rather than flipping after hydration.
 *
 * Deliberately not in index.tsx: that file is "use client", and deliberately
 * not in shared.ts either, because importing next/headers there would drag a
 * server-only module into every client bundle that imports the locale list.
 */
export async function getServerT(): Promise<Translate> {
  return translatorFor(await getServerLocale());
}

export async function getServerLocale(): Promise<Locale> {
  const stored = (await cookies()).get("bh_locale")?.value;
  return isLocale(stored) ? stored : "en";
}
