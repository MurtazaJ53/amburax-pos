"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";

import { useT } from "@/lib/i18n";
import { GST_STATES, gstinStateMismatch } from "@/lib/gst-states";
import {
  Store,
  Mail,
  Lock,
  ArrowRight,
  AlertCircle,
  KeyRound,
  CheckCircle2,
  User,
  Delete,
  Globe,
} from "lucide-react";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}


type AuthPanelMode = "login" | "register" | "join" | "pin";

export function AuthLogin() {
  const router = useRouter();
  const t = useT();
  const [panelMode, setPanelMode] = useState<AuthPanelMode>("login");

  // Cloud login state
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [_rememberMe, _setRememberMe] = useState(true);

  // PIN unlock state
  const [pin, setPin] = useState("");

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
      setTimeout(() => {
        router.push(data.defaultRoute || "/");
        router.refresh();
      }, 500);
    } catch (err) {
      setError(errorMessage(err, "Failed to sign in. Please verify your connection."));
    } finally {
      setIsLoading(false);
    }
  };

  // 2. PIN Unlock Submit
  const handlePinSubmit = async (pinValue = pin) => {
    if (pinValue.length < 4) return;
    setError(null);
    setIsLoading(true);

    try {
      const res = await fetch("/api/auth/pin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pin: pinValue }),
      });

      const data = await res.json();

      if (!res.ok || !data.success) {
        throw new Error(data.error || "Incorrect PIN");
      }

      setSuccessMsg("Terminal unlocked! Opening POS...");
      setTimeout(() => {
        router.push("/pos");
        router.refresh();
      }, 400);
    } catch (err) {
      setError(errorMessage(err, "Failed to unlock terminal."));
      setPin("");
    } finally {
      setIsLoading(false);
    }
  };

  const handlePinDigit = (digit: string) => {
    if (pin.length < 4) {
      const nextPin = pin + digit;
      setPin(nextPin);
      if (nextPin.length === 4) {
        handlePinSubmit(nextPin);
      }
    }
  };

  const handlePinBackspace = () => {
    setPin((prev) => prev.slice(0, -1));
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
      setTimeout(() => {
        router.push("/");
        router.refresh();
      }, 500);
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
      setTimeout(() => {
        router.push(data.defaultRoute || "/");
        router.refresh();
      }, 500);
    } catch (err) {
      setError(errorMessage(err, "Failed to join shop."));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-[var(--bg-app)] flex flex-col items-center justify-center p-4 sm:p-6 select-none">
      <div className="w-full max-w-[440px] flex flex-col items-center">
        
        {/* Brand Hero matching Flutter _BrandHero */}
        <div className="flex flex-col items-center text-center mb-6">
          <div className="w-20 h-20 rounded-[26px] bg-gradient-to-br from-[var(--primary-light)] to-[var(--primary-hover)] flex items-center justify-center shadow-[0_12px_28px_rgba(14,165,233,0.38)] mb-4">
            <Store className="w-10 h-10 text-white" />
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
              {panelMode === "pin" && "Staff Login"}
            </span>
            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-extrabold tracking-wider bg-[var(--primary)]/10 text-[var(--primary-hover)] border border-[var(--primary)]/20 uppercase">
              {panelMode === "login" && <Globe className="w-3.5 h-3.5" />}
              {panelMode === "register" && <Store className="w-3.5 h-3.5" />}
              {panelMode === "join" && <User className="w-3.5 h-3.5" />}
              {panelMode === "pin" && <KeyRound className="w-3.5 h-3.5" />}
              {panelMode === "login" && "CLOUD"}
              {panelMode === "register" && "SIGN UP"}
              {panelMode === "join" && "INVITE"}
              {panelMode === "pin" && "SECURE PIN"}
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
                className="w-full h-13 py-3.5 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 mt-3 cursor-pointer"
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

              <div className="flex justify-between items-center pt-3 text-xs">
                <button
                  type="button"
                  onClick={() => setPanelMode("register")}
                  className="font-bold text-[var(--primary)] hover:underline"
                >
                  {t("webCreateShop")}
                </button>
                <button
                  type="button"
                  onClick={() => setPanelMode("join")}
                  className="font-bold text-[var(--primary)] hover:underline"
                >
                  {t("webJoinWithCode")}
                </button>
              </div>

              <div className="pt-2 text-center">
                <button
                  type="button"
                  onClick={() => setPanelMode("pin")}
                  className="text-xs font-bold text-[var(--text-secondary)] hover:text-[var(--primary)] transition-colors"
                >
                  {t("webStaffPinLogin")}
                </button>
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
                  placeholder="Mobile (optional)"
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              <div className="grid grid-cols-[1.5fr_1fr] gap-3">
                <select
                  value={regBusinessType}
                  onChange={(e) => setRegBusinessType(e.target.value)}
                  className="w-full px-3.5 py-3 bg-[var(--bg-base)] border border-[var(--border-soft)] focus:border-[var(--primary)] focus:bg-[var(--surface)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] outline-none"
                >
                  <option value="retail">Retail</option>
                  <option value="wholesale">Wholesale</option>
                  <option value="grocery">Grocery</option>
                  <option value="pharmacy">Pharmacy</option>
                  <option value="restaurant">Restaurant</option>
                  <option value="service">Service</option>
                  <option value="other">Other</option>
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
                className="w-full h-13 py-3.5 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 mt-3 cursor-pointer"
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
                className="w-full h-13 py-3.5 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 mt-3 cursor-pointer"
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
          {panelMode === "pin" && (
            <div className="space-y-5">
              <p className="text-xs font-medium text-[var(--text-secondary)] text-center -mt-1 mb-2 leading-relaxed">
                {t("webPinHint")}
              </p>

              {/* 4-digit PIN dots */}
              <div className="flex justify-center items-center gap-4 py-2">
                {[0, 1, 2, 3].map((idx) => (
                  <div
                    key={idx}
                    className={`w-5 h-5 rounded-full border-2 transition-all ${
                      pin.length > idx
                        ? "bg-[var(--primary)] border-[var(--primary)] scale-110 shadow-md shadow-[var(--primary)]/30"
                        : "bg-[var(--bg-soft)] border-[var(--border)]"
                    }`}
                  />
                ))}
              </div>

              {/* Numeric Keypad */}
              <div className="grid grid-cols-3 gap-2.5 pt-2 max-w-[260px] mx-auto">
                {["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((num) => (
                  <button
                    key={num}
                    type="button"
                    onClick={() => handlePinDigit(num)}
                    className="h-13 bg-[var(--bg-base)] hover:bg-[var(--bg-app)] active:bg-[var(--border-soft)] border border-[var(--border-soft)] rounded-2xl text-xl font-bold text-[var(--text-primary)] shadow-sm transition-all flex items-center justify-center cursor-pointer"
                  >
                    {num}
                  </button>
                ))}
                <button
                  type="button"
                  onClick={() => setPin("")}
                  className="h-13 bg-[var(--bg-base)] hover:bg-[var(--bg-app)] border border-[var(--border-soft)] rounded-2xl text-xs font-bold text-[var(--text-secondary)] shadow-sm flex items-center justify-center cursor-pointer"
                >
                  CLEAR
                </button>
                <button
                  type="button"
                  onClick={() => handlePinDigit("0")}
                  className="h-13 bg-[var(--bg-base)] hover:bg-[var(--bg-app)] border border-[var(--border-soft)] rounded-2xl text-xl font-bold text-[var(--text-primary)] shadow-sm flex items-center justify-center cursor-pointer"
                >
                  0
                </button>
                <button
                  type="button"
                  onClick={handlePinBackspace}
                  className="h-13 bg-[var(--bg-base)] hover:bg-[var(--bg-app)] border border-[var(--border-soft)] rounded-2xl text-[var(--text-secondary)] shadow-sm flex items-center justify-center cursor-pointer"
                >
                  <Delete className="w-5 h-5" />
                </button>
              </div>

              <button
                type="button"
                onClick={() => handlePinSubmit(pin)}
                disabled={pin.length < 4 || isLoading}
                className="w-full h-13 py-3.5 bg-[var(--primary)] hover:bg-[var(--primary-hover)] disabled:bg-[var(--border)] text-white text-xs font-extrabold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 mt-2 cursor-pointer"
              >
                {isLoading ? (
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  <>
                    <span>UNLOCK TERMINAL</span>
                    <ArrowRight className="w-4 h-4" />
                  </>
                )}
              </button>

              <div className="text-center pt-2">
                <button
                  type="button"
                  onClick={() => setPanelMode("login")}
                  className="text-xs font-bold text-[var(--text-secondary)] hover:text-[var(--primary)] transition-colors"
                >
                  {t("webSignInCloud")}
                </button>
              </div>
            </div>
          )}

        </div>

        {/* Footer */}
        <p className="mt-6 text-center text-xs font-semibold text-[var(--text-tertiary)]">
          Business Hub Cloud POS v2.4 • Synced & Secure
        </p>
      </div>
    </div>
  );
}
