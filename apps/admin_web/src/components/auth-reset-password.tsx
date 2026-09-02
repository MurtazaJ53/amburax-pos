"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";
import { AlertCircle, ArrowRight, CheckCircle2, Lock, Store } from "lucide-react";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

/**
 * Choose a new password, using the token from the emailed link.
 *
 * The token arrives in the query string and is handed straight to the server
 * route; nothing about it is stored in the browser. A missing token is said
 * plainly rather than rendering a form that cannot possibly work - the
 * failure a person hits by opening /reset-password on its own, or through an
 * email client that mangled the link.
 *
 * No session is issued on success. The person signs in with the password they
 * just chose, which proves the reset actually took rather than assuming it.
 */
export function AuthResetPassword({ token }: { token: string }) {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    // Checked here as well as on the server: catching a typo before the token
    // is spent saves somebody having to ask for a whole new email.
    if (password !== confirmPassword) {
      setError("Those two passwords are not the same.");
      return;
    }

    setIsLoading(true);
    try {
      const res = await fetch("/api/auth/password-reset/confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, password }),
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok || !data.success) {
        throw new Error(
          data.error || "That reset link could not be used. Please request a new one.",
        );
      }

      setDone(true);
    } catch (err) {
      setError(errorMessage(err, "Could not change your password. Please try again."));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen w-full bg-[var(--bg-base)] flex items-center justify-center px-4 py-8">
      <div className="w-full max-w-md flex flex-col items-center">
        <div className="flex flex-col items-center text-center mb-6">
          <div className="w-20 h-20 rounded-[26px] bg-gradient-to-br from-[var(--primary-light)] to-[var(--primary-hover)] flex items-center justify-center shadow-[0_12px_28px_rgba(14,165,233,0.38)] mb-4">
            <Store className="w-10 h-10 text-[var(--text-primary)]" />
          </div>
          <h1 className="text-2xl sm:text-3xl font-[900] text-[var(--text-primary)] tracking-tight">
            Business Hub
          </h1>
        </div>

        <div className="w-full bg-[var(--surface)] border border-[var(--border-soft)] rounded-[28px] shadow-[0_10px_30px_rgba(14,165,233,0.06),0_4px_12px_rgba(0,0,0,0.03)] p-6 sm:p-7">
          <div className="flex items-center justify-between pb-4 border-b border-[var(--bg-soft)] mb-5">
            <span className="text-base font-extrabold text-[var(--text-primary)]">
              Choose a new password
            </span>
            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-extrabold tracking-wider bg-[var(--primary)]/10 text-[var(--primary-hover)] border border-[var(--primary)]/20 uppercase">
              <Lock className="w-3.5 h-3.5" />
              RESET
            </span>
          </div>

          {error && (
            <div
              role="alert"
              className="mb-5 p-3.5 bg-[var(--error)]/10 border border-[var(--error)]/30 rounded-2xl flex items-start gap-2.5 text-xs font-semibold text-[var(--error-strong)]"
            >
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5 text-[var(--error)]" />
              <span>{error}</span>
            </div>
          )}

          {!token ? (
            <div className="space-y-4">
              <p className="text-xs font-semibold text-[var(--text-secondary)] leading-relaxed">
                This page needs the link from your reset email. Open that link, or ask
                for a new one.
              </p>
              <a
                href="/forgot-password"
                className="min-h-[48px] w-full flex items-center justify-center gap-2 px-3 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-soft)] hover:border-[var(--primary)] transition-colors text-xs font-extrabold text-[var(--text-primary)]"
              >
                Send a new reset link
              </a>
            </div>
          ) : done ? (
            <div className="space-y-4">
              <div
                role="status"
                className="p-3.5 bg-[var(--success)]/10 border border-[var(--success)]/30 rounded-2xl flex items-start gap-2.5 text-xs font-semibold text-[var(--success-strong)]"
              >
                <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5 text-[var(--success)]" />
                <span>
                  Your password has been changed. Sign in with it now — any other device
                  that was signed in has been signed out.
                </span>
              </div>
              <button
                type="button"
                onClick={() => router.replace("/login")}
                className="w-full h-13 py-3.5 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 cursor-pointer"
              >
                <span>GO TO SIGN IN</span>
                <ArrowRight className="w-4 h-4" />
              </button>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label
                  htmlFor="reset-password"
                  className="block text-xs font-bold text-[var(--text-secondary)] mb-1.5"
                >
                  New password
                </label>
                <div className="relative">
                  <Lock className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                  <input
                    id="reset-password"
                    type="password"
                    required
                    minLength={8}
                    autoComplete="new-password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="New password (8+ characters)"
                    className="w-full pl-10 pr-4 py-3.5 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none transition-all"
                  />
                </div>
              </div>

              <div>
                <label
                  htmlFor="reset-password-confirm"
                  className="block text-xs font-bold text-[var(--text-secondary)] mb-1.5"
                >
                  Type it again
                </label>
                <div className="relative">
                  <Lock className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                  <input
                    id="reset-password-confirm"
                    type="password"
                    required
                    minLength={8}
                    autoComplete="new-password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="Confirm new password"
                    className="w-full pl-10 pr-4 py-3.5 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none transition-all"
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={isLoading}
                className="w-full h-13 py-3.5 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 mt-3 cursor-pointer disabled:opacity-60"
              >
                {isLoading ? (
                  <div className="w-5 h-5 border-2 border-[var(--primary-dark)] border-t-transparent rounded-full animate-spin" />
                ) : (
                  <>
                    <span>SAVE NEW PASSWORD</span>
                    <ArrowRight className="w-4 h-4" />
                  </>
                )}
              </button>

              <p className="text-[11px] font-medium text-[var(--text-tertiary)] text-center leading-relaxed">
                This link works once and expires an hour after it was sent.
              </p>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
