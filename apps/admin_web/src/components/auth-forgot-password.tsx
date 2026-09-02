"use client";

import React, { useState } from "react";
import { AlertCircle, ArrowLeft, CheckCircle2, Mail, Store } from "lucide-react";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

/**
 * "Forgot password" - ask for an emailed reset link.
 *
 * The screen says exactly what the server said and nothing more. Two things
 * it deliberately never does:
 *
 *  - It does not tell the visitor whether the address has an account. Anybody
 *    can type anybody's email in here, so a different answer for "no such
 *    account" would turn this form into a free membership check.
 *  - It does not show a reset token. A token on screen would let whoever
 *    typed the address take over the account without ever seeing the inbox,
 *    which is the same hole with a friendlier face.
 *
 * And when the send fails it says so, plainly, instead of telling somebody to
 * keep watching an inbox nothing is coming to.
 */
export function AuthForgotPassword() {
  const [email, setEmail] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sentMessage, setSentMessage] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSentMessage(null);
    setIsLoading(true);

    try {
      const res = await fetch("/api/auth/password-reset", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok || !data.success) {
        // Includes the case that matters most: the API accepted the request
        // but the mail provider refused it. Nothing was sent, and the person
        // needs to know that rather than wait.
        throw new Error(
          data.error || "The reset email could not be sent. Please try again shortly.",
        );
      }

      setSentMessage(
        data.detail || "If an account exists for that email, a reset link is on its way.",
      );
    } catch (err) {
      setError(errorMessage(err, "Could not send the reset email. Please try again."));
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
              Reset your password
            </span>
            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-extrabold tracking-wider bg-[var(--primary)]/10 text-[var(--primary-hover)] border border-[var(--primary)]/20 uppercase">
              <Mail className="w-3.5 h-3.5" />
              EMAIL
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

          {sentMessage ? (
            <div className="space-y-4">
              <div
                role="status"
                className="p-3.5 bg-[var(--success)]/10 border border-[var(--success)]/30 rounded-2xl flex items-start gap-2.5 text-xs font-semibold text-[var(--success-strong)]"
              >
                <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5 text-[var(--success)]" />
                <span>{sentMessage}</span>
              </div>
              <p className="text-xs font-medium text-[var(--text-secondary)] leading-relaxed">
                The link works once and expires in an hour. If it does not arrive, check
                the spam folder, then ask again from this page.
              </p>
              <a
                href="/login"
                className="min-h-[48px] w-full flex items-center justify-center gap-2 px-3 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-soft)] hover:border-[var(--primary)] transition-colors text-xs font-extrabold text-[var(--text-primary)]"
              >
                <ArrowLeft className="w-4 h-4" />
                Back to sign in
              </a>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <p className="text-xs font-medium text-[var(--text-secondary)] text-center -mt-1 mb-2 leading-relaxed">
                Enter the email you sign in with. We&apos;ll send a link to choose a new
                password.
              </p>

              <div>
                <label
                  htmlFor="forgot-email"
                  className="block text-xs font-bold text-[var(--text-secondary)] mb-1.5"
                >
                  Email
                </label>
                <div className="relative">
                  <Mail className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                  <input
                    id="forgot-email"
                    type="email"
                    required
                    autoComplete="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="Email"
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
                  <span>SEND RESET LINK</span>
                )}
              </button>

              <div className="pt-4 mt-1 border-t border-[var(--border-soft)]">
                <a
                  href="/login"
                  className="min-h-[48px] w-full flex items-center justify-center gap-2 px-3 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-soft)] hover:border-[var(--primary)] transition-colors text-xs font-extrabold text-[var(--text-primary)]"
                >
                  <ArrowLeft className="w-4 h-4" />
                  Back to sign in
                </a>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
