"use client";

/** The app's own way of saying something, and of asking.
 *
 *  Everything used window.alert and window.confirm. Those are the browser's
 *  dialogs, not the app's, and it shows: they carry the host name in the
 *  title, they are styled by Chrome rather than by anything here, and the
 *  message inside was whatever string happened to be handy - one of them
 *  printed a raw JSON error body at a shopkeeper.
 *
 *  They also block. window.confirm freezes the page until it is answered,
 *  which is exactly wrong at a till with a customer waiting.
 *
 *  This replaces both. `say` states something; `ask` asks and resolves to
 *  true or false, so a call site reads almost as it did before, with an await
 *  in front of it.
 */
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { AlertTriangle, Info } from "lucide-react";

type Tone = "info" | "warning" | "danger";

type Request = {
  title: string;
  body?: string;
  tone: Tone;
  /** Present only when an answer is wanted. */
  resolve?: (answer: boolean) => void;
  confirmLabel: string;
};

type DialogApi = {
  /** State something. */
  say: (title: string, body?: string, tone?: Tone) => void;
  /** Ask something. Resolves true only if they agree. */
  ask: (
    title: string,
    body?: string,
    options?: { confirmLabel?: string; tone?: Tone },
  ) => Promise<boolean>;
};

const DialogContext = createContext<DialogApi | null>(null);

/** The dialog api, or a fallback that keeps the app working.
 *
 *  Falls back to the native dialogs rather than throwing: a component used
 *  outside the provider - a test, a screen rendered on its own - should still
 *  be able to tell somebody something.
 */
export function useDialog(): DialogApi {
  const api = useContext(DialogContext);
  return (
    api ?? {
      say: (title, body) => window.alert([title, body].filter(Boolean).join("\n\n")),
      ask: async (title, body) =>
        window.confirm([title, body].filter(Boolean).join("\n\n")),
    }
  );
}

export function DialogProvider({ children }: { children: React.ReactNode }) {
  const [request, setRequest] = useState<Request | null>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);

  const close = useCallback((answer: boolean) => {
    setRequest((current) => {
      current?.resolve?.(answer);
      return null;
    });
  }, []);

  const api = useMemo<DialogApi>(
    () => ({
      say: (title, body, tone = "info") =>
        setRequest({ title, body, tone, confirmLabel: "OK" }),
      ask: (title, body, options) =>
        new Promise<boolean>((resolve) =>
          setRequest({
            title,
            body,
            tone: options?.tone ?? "warning",
            confirmLabel: options?.confirmLabel ?? "Yes, continue",
            resolve,
          }),
        ),
    }),
    [],
  );

  // Escape answers no. A dialog that can only be dismissed by finding the
  // right button is a dialog people click through without reading.
  useEffect(() => {
    if (!request) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") close(false);
    };
    window.addEventListener("keydown", onKey);
    // Focus lands on the action, so Enter answers it and a screen reader
    // announces what is being asked rather than the page behind it.
    confirmRef.current?.focus();
    return () => window.removeEventListener("keydown", onKey);
  }, [request, close]);

  const asking = Boolean(request?.resolve);
  const tone = request?.tone ?? "info";
  const accent =
    tone === "danger"
      ? "var(--error-strong)"
      : tone === "warning"
        ? "var(--warning-strong)"
        : "var(--primary-dark)";

  return (
    <DialogContext.Provider value={api}>
      {children}

      {request && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="app-dialog-title"
          className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm"
          // Clicking away answers no, matching Escape. Never yes: a dialog
          // that agrees to something because somebody missed it is worse than
          // one that has to be asked twice.
          onMouseDown={() => close(false)}
        >
          <div
            onMouseDown={(event) => event.stopPropagation()}
            className="motion-safe:animate-in motion-safe:fade-in motion-safe:zoom-in-95 w-full max-w-md rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-2xl duration-150"
          >
            <div className="flex items-start gap-3">
              <span
                className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-full"
                style={{
                  backgroundColor: `color-mix(in srgb, ${accent} 12%, transparent)`,
                  color: accent,
                }}
              >
                {tone === "info" ? (
                  <Info className="h-4 w-4" />
                ) : (
                  <AlertTriangle className="h-4 w-4" />
                )}
              </span>
              <div className="min-w-0 flex-1">
                <h2
                  id="app-dialog-title"
                  className="m-0 text-[14.5px] font-extrabold text-[var(--text-primary)]"
                >
                  {request.title}
                </h2>
                {request.body && (
                  <p className="m-0 mt-1.5 whitespace-pre-line text-[13px] font-semibold leading-relaxed text-[var(--text-secondary)]">
                    {request.body}
                  </p>
                )}
              </div>
            </div>

            <div className="mt-5 flex justify-end gap-2">
              {asking && (
                <button
                  type="button"
                  onClick={() => close(false)}
                  className="focus-ring cursor-pointer rounded-[10px] border border-[var(--border-soft)] px-4 py-2 text-[12px] font-extrabold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
                >
                  Cancel
                </button>
              )}
              <button
                ref={confirmRef}
                type="button"
                onClick={() => close(true)}
                className="focus-ring cursor-pointer rounded-[10px] px-4 py-2 text-[12px] font-extrabold text-white transition-opacity hover:opacity-90"
                style={{ backgroundColor: accent }}
              >
                {request.confirmLabel}
              </button>
            </div>
          </div>
        </div>
      )}
    </DialogContext.Provider>
  );
}
