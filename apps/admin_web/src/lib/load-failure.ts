import { ApiError } from "@/lib/admin-api";

/** What to tell somebody whose screen would not load.
 *
 *  Six pages rendered one hardcoded sentence for every possible failure:
 *  "Backend Connection Error — Next.js Server Component failed to fetch data
 *  from the Django backend", followed by advice to check the api container.
 *
 *  That is right for exactly one cause. It is wrong, and alarming, for the
 *  commonest one: a cashier opening a screen their role does not include gets
 *  told the server is broken, and rings the shop owner about an outage that
 *  is not happening. The status was on the error object the whole time.
 */
export type LoadFailure = {
  title: string;
  detail: string;
  /** The raw upstream message. Shown only when it would help somebody fix
   *  something — never for a refusal, where it is noise about a non-problem. */
  technical: string | null;
};

export function describeLoadFailure(error: unknown, subject: string): LoadFailure {
  const raw = error instanceof Error && error.message ? error.message : String(error ?? "");

  if (error instanceof ApiError) {
    if (error.status === 403) {
      return {
        title: "Not your part of the shop",
        detail: `Your role does not include ${subject}. An owner or admin can change that from Team.`,
        technical: null,
      };
    }
    if (error.status === 401) {
      return {
        title: "Signed out",
        detail: "This session has ended. Sign in again to carry on.",
        technical: null,
      };
    }
    if (error.status === 404) {
      return {
        title: "Nothing here",
        detail: `This shop has no ${subject} to show. If you expected some, check you have the right shop selected.`,
        technical: null,
      };
    }
    if (error.status === 429) {
      return {
        title: "Too many requests",
        detail: "The server is asking for a pause. Wait a minute, then reload.",
        technical: null,
      };
    }
    // A genuine upstream fault. This is the only case where a technical
    // message helps, because somebody has to go and read a log.
    return {
      title: "The server could not answer",
      detail: `Something went wrong loading ${subject}. Reload the page — if it keeps happening, check the api container.`,
      technical: raw,
    };
  }

  // fetch() itself threw: nothing was reached at all.
  return {
    title: "Could not reach the server",
    detail: `This site could not contact the Business Hub API to load ${subject}. Check that the api container is running.`,
    technical: raw,
  };
}
