"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";

import { useT } from "@/lib/i18n";
import { LanguageSwitcher } from "@/components/language-switcher";
import { GST_STATES, gstinStateMismatch } from "@/lib/gst-states";
import { BUSINESS_TYPE_OPTIONS } from "@/lib/business-types";
import {
  Store,
  Mail,
  Lock,
  ArrowRight,
  AlertCircle,
  CheckCircle2,
  User,
  Globe,
} from "lucide-react";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}


/** The panels this screen can actually show.
 *
 *  "pin" is deliberately not among them. A counter PIN unlocks a session that
 *  already exists — the server requires an authenticated caller and refuses to
 *  issue a session from four digits — so it can never be a way in, and the
 *  sign-in screen is the one place it can never work. The whole PIN pad lived
 *  here behind a mode nothing ever selected: a Staff Login that no staff could
 *  reach, and a Team page counting PINs that nothing could set.
 *
 *  The server half is built and tested. What it is waiting for is a locked
 *  till screen, which needs the lock enforced in middleware rather than drawn
 *  over the page — see FUTURE.md.
 */
type AuthPanelMode = "login" | "register" | "join";

export function AuthLogin({
  notice,
  initialMode = "login",
}: { notice?: string; initialMode?: AuthPanelMode } = {}) {
  const router = useRouter();
  const t = useT();
  // /register opens straight on the sign-up panel. It used to be a separate
  // screen with its own form, which collected a name, an email, a phone and a
  // password and then sent none of it anywhere - two sign-up flows, and the
  // duplicate was the broken one.
  const [panelMode, setPanelMode] = useState<AuthPanelMode>(initialMode);

  // Cloud login state
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [_rememberMe, _setRememberMe] = useState(true);

  // Register state
  const [regOwnerName, setRegOwnerName] = useState("");
  const [regBusinessName, setRegBusinessName] = useState("");
  const [regEmail, setRegEmail] = useState("");
  const [regPassword, setRegPassword] = useState("");
  const [regMobile, setRegMobile] = useState("");
  const [regBusinessType, setRegBusinessType] = useState("retail");
  const [regStateCode, setRegStateCode] = useState("");
  const [regGstin, setRegGstin] = useState("");

  // Join state
  const [joinCode, setJoinCode] = useState("");
  const [joinName, setJoinName] = useState("");
  const [joinPassword, setJoinPassword] = useState("");

  // Global state
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // 1. Cloud Sign In Submit
  const handleCloudLogin = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    setError(null);
    setSuccessMsg(null);
    setIsLoading(true);

    try {
      const res = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });

      const data = await res.json();

      if (!res.ok || !data.success) {
        throw new Error(data.error || "Invalid credentials. Please try again.");
      }

      setSuccessMsg("Signed in successfully! Redirecting...");
      // Straight there. The half-second pause here was purely so the
      // success message could be read, and it is time somebody spends
      // looking at a screen that has already finished its work.
      //
      // refresh() before replace(), not after: called afterwards it
      // re-rendered the page just navigated to, so the dashboard - three
      // sequential calls and a render - was built twice. Called first it
      // clears the cached signed-out payload, which is what it was for.
      //
      // replace() rather than push(), so Back from the dashboard does not
      // return to a sign-in form for a session that already exists.
      router.refresh();
      router.replace(data.defaultRoute || "/");
    } catch (err) {
      setError(errorMessage(err, "Failed to sign in. Please verify your connection."));
    } finally {
      setIsLoading(false);
    }
  };

  // 3. Register Submit
  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setIsLoading(true);

    try {
      const res = await fetch("/api/auth/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          ownerName: regOwnerName,
          businessName: regBusinessName,
          email: regEmail,
          password: regPassword,
          mobile: regMobile,
          businessType: regBusinessType,
          stateCode: regStateCode,
          gstin: regGstin,
        }),
      });

      const data = await res.json();

      if (!res.ok || !data.success) {
        throw new Error(data.error || "Registration failed. Please check your fields.");
      }

      setSuccessMsg("Shop created successfully! Redirecting...");
      // Straight there. The half-second pause here was purely so the
      // success message could be read, and it is time somebody spends
      // looking at a screen that has already finished its work.
      //
      // refresh() before replace(), not after: called afterwards it
      // re-rendered the page just navigated to, so the dashboard - three
      // sequential calls and a render - was built twice. Called first it
      // clears the cached signed-out payload, which is what it was for.
      //
      // replace() rather than push(), so Back from the dashboard does not
      // return to a sign-in form for a session that already exists.
      router.refresh();
      router.replace("/");
    } catch (err) {
      setError(errorMessage(err, "Failed to create shop."));
    } finally {
      setIsLoading(false);
    }
  };

  // 4. Join Submit
  const handleJoin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setIsLoading(true);

    try {
      const res = await fetch("/api/auth/join", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          token: joinCode,
          name: joinName,
          password: joinPassword,
        }),
      });

      const data = await res.json();

      if (!res.ok || !data.success) {
        throw new Error(data.error || "Invite code invalid or expired.");
      }

      setSuccessMsg("Joined shop successfully! Redirecting...");
      // Straight there. The half-second pause here was purely so the
      // success message could be read, and it is time somebody spends
      // looking at a screen that has already finished its work.
      //
      // refresh() before replace(), not after: called afterwards it
      // re-rendered the page just navigated to, so the dashboard - three
      // sequential calls and a render - was built twice. Called first it
      // clears the cached signed-out payload, which is what it was for.
      //
      // replace() rather than push(), so Back from the dashboard does not
      // return to a sign-in form for a session that already exists.
      router.refresh();
      router.replace(data.defaultRoute || "/");
    } catch (err) {
      setError(errorMessage(err, "Failed to join shop."));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-[var(--bg-app)] flex flex-col items-center justify-center p-4 sm:p-6 select-none">
      <div className="w-full max-w-[440px] flex flex-col items-center">

        {/* Language first, before anything asks for a decision. This is the
            first screen anyone meets, and someone who cannot read it cannot
            reach the settings page where the switcher used to live. Each
            option is written in its own script for the same reason. */}
        <div className="w-full flex justify-end mb-3">
          <LanguageSwitcher />
        </div>

        {/* Brand Hero matching Flutter _BrandHero */}
        <div className="flex flex-col items-center text-center mb-6">
          <div className="w-20 h-20 rounded-[26px] bg-gradient-to-br from-[var(--primary-light)] to-[var(--primary-hover)] flex items-center justify-center shadow-[0_12px_28px_rgba(14,165,233,0.38)] mb-4">
            <Store className="w-10 h-10 text-[var(--text-primary)]" />
          </div>
          <h1 className="text-2xl sm:text-3xl font-[900] text-[var(--text-primary)] tracking-tight">
            Business Hub
          </h1>
          <p className="text-xs sm:text-sm font-semibold text-[var(--text-secondary)] mt-1">
            Point of sale & business command center
          </p>
        </div>

        {/* Main Panel matching Flutter MobilePanel */}
        <div className="w-full bg-[var(--surface)] border border-[var(--border-soft)] rounded-[28px] shadow-[0_10px_30px_rgba(14,165,233,0.06),0_4px_12px_rgba(0,0,0,0.03)] p-6 sm:p-7">
          
          {/* Header Action tag matching MobileTag */}
          <div className="flex items-center justify-between pb-4 border-b border-[var(--bg-soft)] mb-5">
            <span className="text-base font-extrabold text-[var(--text-primary)]">
              {panelMode === "login" && "Cloud Sign-in"}
              {panelMode === "register" && "Create your shop"}
              {panelMode === "join" && "Join a shop"}
            </span>
            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-extrabold tracking-wider bg-[var(--primary)]/10 text-[var(--primary-hover)] border border-[var(--primary)]/20 uppercase">
              {panelMode === "login" && <Globe className="w-3.5 h-3.5" />}
              {panelMode === "register" && <Store className="w-3.5 h-3.5" />}
              {panelMode === "join" && <User className="w-3.5 h-3.5" />}
              {panelMode === "login" && "CLOUD"}
              {panelMode === "register" && "SIGN UP"}
              {panelMode === "join" && "INVITE"}
            </span>
          </div>

          {/* Feedback Alerts */}
          {error && (
            <div className="mb-5 p-3.5 bg-[var(--error)]/10 border border-[var(--error)]/30 rounded-2xl flex items-center gap-2.5 text-xs font-semibold text-[var(--error-strong)]">
              <AlertCircle className="w-4 h-4 shrink-0 text-[var(--error)]" />
              <span>{error}</span>
            </div>
          )}

          {successMsg && (
            <div className="mb-5 p-3.5 bg-[var(--success)]/10 border border-[var(--success)]/30 rounded-2xl flex items-center gap-2.5 text-xs font-semibold text-[var(--success-strong)]">
              <CheckCircle2 className="w-4 h-4 shrink-0 text-[var(--success)]" />
              <span>{successMsg}</span>
            </div>
          )}

          {/* MODE: CLOUD LOGIN */}
          {panelMode === "login" && (
            <form onSubmit={handleCloudLogin} className="space-y-4">
              <p className="text-xs font-medium text-[var(--text-secondary)] text-center -mt-1 mb-2 leading-relaxed">
                Sign in to sync with the cloud backend.
              </p>

              <div>
                <label className="block text-xs font-bold text-[var(--text-secondary)] mb-1.5">
                  Email
                </label>
                <div className="relative">
                  <Mail className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="Email"
                    className="w-full pl-10 pr-4 py-3.5 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none transition-all"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-[var(--text-secondary)] mb-1.5">
                  Password
                </label>
                <div className="relative">
                  <Lock className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                  <input
                    type="password"
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Password"
                    className="w-full pl-10 pr-4 py-3.5 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none transition-all"
                  />
                </div>
              </div>

              <button
                type="submit"
                disabled={isLoading}
                className="w-full h-13 py-3.5 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 mt-3 cursor-pointer"
              >
                {isLoading ? (
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  <>
                    <span>SIGN IN</span>
                    <ArrowRight className="w-4 h-4" />
                  </>
                )}
              </button>

              {/* Why the visitor was sent here, said where they are looking.
                  It used to render above the whole page - a strip of text by
                  the top edge, a screen away from the form it is about. On a
                  tall window somebody could sign in without ever seeing it. */}
              {notice && (
                <p
                  role="status"
                  className="m-0 mt-3 rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning)]/10 px-4 py-3 text-center text-[12px] font-bold text-[var(--warning-strong)]"
                >
                  {notice}
                </p>
              )}

              {/* The other three ways in. These were 12px text links, which put
                  the most frequent action on this screen — a cashier punching a
                  PIN with a customer waiting — on the smallest target of all.
                  Real buttons, 48px tall, thumb-reachable, in frequency order:
                  staff sign in many times a day, a shop is created once ever. */}
              <div className="pt-4 mt-1 border-t border-[var(--border-soft)] space-y-2">
                {/* Staff PIN is deliberately absent here. It unlocks a session
                    that already exists, so on a signed-out browser — which is
                    every first run — there is nothing for it to unlock, and no
                    shop, and no staff. Offering it was a door to nowhere. It
                    lives on the locked POS screen instead. */}
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setPanelMode("register")}
                    className="min-h-[48px] flex items-center justify-center gap-2 px-3 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-soft)] hover:border-[var(--primary)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--primary)] transition-colors"
                  >
                    <Store className="w-4 h-4 shrink-0 text-[var(--text-secondary)]" />
                    <span className="text-xs font-extrabold text-[var(--text-primary)]">
                      {t("webCreateShop")}
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => setPanelMode("join")}
                    className="min-h-[48px] flex items-center justify-center gap-2 px-3 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-soft)] hover:border-[var(--primary)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--primary)] transition-colors"
                  >
                    <User className="w-4 h-4 shrink-0 text-[var(--text-secondary)]" />
                    <span className="text-xs font-extrabold text-[var(--text-primary)]">
                      {t("webJoinWithCode")}
                    </span>
                  </button>
                </div>
              </div>
            </form>
          )}

          {/* MODE: REGISTER / CREATE SHOP */}
          {panelMode === "register" && (
            <form onSubmit={handleRegister} className="space-y-3.5">
              <p className="text-xs font-medium text-[var(--text-secondary)] text-center -mt-1 mb-2 leading-relaxed">
                Set up a new business workspace in under a minute.
              </p>

              <div>
                <input
                  type="text"
                  required
                  value={regOwnerName}
                  onChange={(e) => setRegOwnerName(e.target.value)}
                  placeholder="Your name *"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <div>
                <input
                  type="text"
                  required
                  value={regBusinessName}
                  onChange={(e) => setRegBusinessName(e.target.value)}
                  placeholder="Business name *"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <div>
                <input
                  type="email"
                  required
                  value={regEmail}
                  onChange={(e) => setRegEmail(e.target.value)}
                  placeholder="Email *"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <div>
                <input
                  type="password"
                  required
                  minLength={8}
                  value={regPassword}
                  onChange={(e) => setRegPassword(e.target.value)}
                  placeholder="Password (8+ characters) *"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <div>
                <input
                  type="tel"
                  value={regMobile}
                  onChange={(e) => setRegMobile(e.target.value)}
                  placeholder="Mobile number *"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <div className="grid grid-cols-[1.5fr_1fr] gap-3">
                <select
                  value={regBusinessType}
                  onChange={(e) => setRegBusinessType(e.target.value)}
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] outline-none"
                >
                  {/* Shared with the settings page, so the two can never drift.
                      Pharmacy and Restaurant are deliberately absent until the
                      app does what picking them implies — batch and expiry for
                      a pharmacy, tables and orders for a restaurant. Both are
                      planned. Offering a choice the product cannot honour
                      misleads on the first screen anyone meets. */}
                  {BUSINESS_TYPE_OPTIONS.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </select>

                {/* A named list, not a two-digit box. This code decides
                    CGST+SGST versus IGST on every bill, and nobody knows their
                    state code by heart — the old field invited a state name or
                    a missing leading zero, and rejected neither. */}
                <select
                  value={regStateCode}
                  onChange={(e) => setRegStateCode(e.target.value)}
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] outline-none"
                >
                  <option value="">State (for GST)</option>
                  {GST_STATES.map((s) => (
                    <option key={s.code} value={s.code}>
                      {s.name} ({s.code})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <input
                  type="text"
                  value={regGstin}
                  onChange={(e) => setRegGstin(e.target.value)}
                  placeholder="GSTIN (optional)"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none uppercase"
                />
                {/* A GSTIN carries its own state in its first two digits. When
                    it disagrees with the chosen state one of them is a typo,
                    and only the shopkeeper knows which — so say so rather than
                    silently trusting either. */}
                {gstinStateMismatch(regStateCode, regGstin) && (
                  <p className="mt-1.5 text-[11px] font-semibold text-[var(--warning-strong)]">
                    {gstinStateMismatch(regStateCode, regGstin)}
                  </p>
                )}
              </div>

              <button
                type="submit"
                disabled={isLoading}
                className="w-full h-13 py-3.5 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 mt-3 cursor-pointer"
              >
                {isLoading ? (
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  <span>CREATE SHOP</span>
                )}
              </button>

              <div className="text-center pt-2">
                <button
                  type="button"
                  onClick={() => setPanelMode("login")}
                  className="text-xs font-bold text-[var(--primary)] hover:underline"
                >
                  Already have an account? Sign in
                </button>
              </div>
            </form>
          )}

          {/* MODE: JOIN WITH CODE */}
          {panelMode === "join" && (
            <form onSubmit={handleJoin} className="space-y-4">
              <p className="text-xs font-medium text-[var(--text-secondary)] text-center -mt-1 mb-2 leading-relaxed">
                {t("webInviteHint")}
              </p>

              <div>
                <input
                  type="text"
                  required
                  value={joinCode}
                  onChange={(e) => setJoinCode(e.target.value)}
                  placeholder="Invite code *"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <div>
                <input
                  type="text"
                  value={joinName}
                  onChange={(e) => setJoinName(e.target.value)}
                  placeholder="Your name"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <div>
                <input
                  type="password"
                  required
                  minLength={8}
                  value={joinPassword}
                  onChange={(e) => setJoinPassword(e.target.value)}
                  placeholder="Set a password (8+ characters) *"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <button
                type="submit"
                disabled={isLoading}
                className="w-full h-13 py-3.5 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 mt-3 cursor-pointer"
              >
                {isLoading ? (
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  <span>{t("webJoinShop")}</span>
                )}
              </button>

              <div className="text-center pt-2">
                <button
                  type="button"
                  onClick={() => setPanelMode("login")}
                  className="text-xs font-bold text-[var(--primary)] hover:underline"
                >
                  {t("webBackToSignIn")}
                </button>
              </div>
            </form>
          )}

          {/* MODE: PIN LOGIN / LOCKSCREEN */}

        </div>

        {/* Footer */}
        <p className="mt-6 text-center text-xs font-semibold text-[var(--text-tertiary)]">
          Business Hub Cloud POS v2.4 • Synced & Secure
        </p>
      </div>
    </div>
  );
}
