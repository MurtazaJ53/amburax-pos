"use client";

/**
 * Last-resort UI for a server render that threw.
 *
 * Without this file Next serves its own blank "This page couldn't load", and
 * the cause is visible only in the container log — which on a droplet means
 * nobody sees it. Production strips the message, but the digest is kept and
 * matches the line in the log, so quoting it back makes the report useful.
 */
export default function AppError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-[var(--bg-app)] p-6">
      <div className="w-full max-w-md rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-6 shadow-sm text-center">
        <h1 className="text-lg font-black text-[var(--text-primary)]">
          Something went wrong on the server
        </h1>
        <p className="mt-2 text-xs font-semibold text-[var(--text-secondary)]">
          This page failed to load. Trying again often works; if it does not,
          the API may be unreachable.
        </p>

        {error.digest && (
          <p className="mt-4 font-mono text-[10px] text-[var(--text-tertiary)] break-all">
            Reference: {error.digest}
          </p>
        )}

        <div className="mt-5 flex items-center justify-center gap-3">
          <button
            type="button"
            onClick={reset}
            className="rounded-2xl bg-[var(--primary)]/12 px-5 py-2.5 text-xs font-extrabold text-[var(--primary-dark)] hover:bg-[var(--primary-hover)] transition-colors border border-[var(--primary)]/25"
          >
            Try again
          </button>
          <a
            href="/login"
            className="rounded-2xl border border-[var(--border)] px-5 py-2.5 text-xs font-extrabold text-[var(--text-secondary)] hover:border-[var(--primary)] transition-colors"
          >
            Sign in
          </a>
        </div>
      </div>
    </div>
  );
}
