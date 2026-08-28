import { describeLoadFailure } from "@/lib/load-failure";

/** The panel a screen shows instead of itself when its data would not load.
 *
 *  One panel, so the wording is decided once from the actual status rather
 *  than six times from a guess. See lib/load-failure.ts for why the guess was
 *  wrong.
 */
export function PageLoadError({
  error,
  subject,
}: {
  error: unknown;
  /** What the page was trying to load, in the shopkeeper's words —
   *  "your products", "your team", not "inventory data from backend". */
  subject: string;
}) {
  const { title, detail, technical } = describeLoadFailure(error, subject);

  return (
    <div className="panel rounded-xl border-[var(--error)]/20 bg-[var(--error)]/5 p-8">
      <p className="mb-2 text-lg font-semibold text-[var(--error)]">{title}</p>
      <p className="text-sm leading-relaxed text-[var(--text-secondary)]">{detail}</p>
      {technical && (
        <pre className="mt-4 max-w-full overflow-x-auto whitespace-pre-wrap rounded bg-black/40 p-4 text-left font-mono text-xs text-[var(--error)]">
          {technical}
        </pre>
      )}
    </div>
  );
}
