"use client";

import React, { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Store,
  Mail,
  Lock,
  User,
  Phone,
  Building,
  CheckCircle2,
  ArrowRight,
} from "lucide-react";

export function AuthRegister() {
  const router = useRouter();
  const [step, setStep] = useState<1 | 2>(1);

  // Step 1: Owner Info
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");

  // Step 2: Store Info
  const [storeName, setStoreName] = useState("");
  const [businessCategory, setBusinessCategory] = useState("Grocery & Supermarket");
  const [city, setCity] = useState("");

  const handleNextStep = (e: React.FormEvent) => {
    e.preventDefault();
    setStep(2);
  };

  const handleFinishRegister = (e: React.FormEvent) => {
    e.preventDefault();
    // Redirect to POS terminal
    router.push("/pos");
  };

  return (
    <div className="min-h-screen bg-[var(--bg-deep)] flex items-center justify-center p-4 relative overflow-hidden">
      {/* Glows */}
      <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-blue-600/10 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-cyan-600/10 rounded-full blur-3xl pointer-events-none" />

      <div className="w-full max-w-md bg-[var(--surface)] border border-[var(--border-soft)] rounded-3xl shadow-2xl overflow-hidden relative z-10 backdrop-blur-xl">
        {/* Header */}
        <div className="p-8 pb-6 text-center border-b border-[var(--border-soft)] bg-gradient-to-b from-[var(--bg-soft)] to-transparent">
          <div className="w-14 h-14 mx-auto rounded-2xl bg-gradient-to-tr from-blue-600 to-cyan-500 flex items-center justify-center shadow-lg shadow-blue-500/25 mb-4">
            <Store className="w-7 h-7 text-[var(--text-primary)]" />
          </div>
          <h1 className="text-xl font-extrabold text-[var(--text-primary)] tracking-tight">
            Create Business Hub Store
          </h1>
          <p className="text-xs text-[var(--text-tertiary)] mt-1">
            {step === 1 ? "Step 1 of 2: Store Owner Account" : "Step 2 of 2: Store & Business Profile"}
          </p>
        </div>

        {step === 1 ? (
          /* Step 1 Form */
          <form onSubmit={handleNextStep} className="p-8 space-y-4">
            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Your Full Name *
              </label>
              <div className="relative">
                <User className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  required
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  placeholder="e.g. Ramesh Patel"
                  className="w-full pl-10 pr-4 py-2.5 bg-[var(--bg-deep)] border border-[var(--border-soft)] rounded-xl text-xs text-white placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Email Address *
              </label>
              <div className="relative">
                <Mail className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="ramesh@example.com"
                  className="w-full pl-10 pr-4 py-2.5 bg-[var(--bg-deep)] border border-[var(--border-soft)] rounded-xl text-xs text-white placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Mobile Number (for OTP & WhatsApp Alerts) *
              </label>
              <div className="relative">
                <Phone className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="tel"
                  required
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+91 98000 00000"
                  className="w-full pl-10 pr-4 py-2.5 bg-[var(--bg-deep)] border border-[var(--border-soft)] rounded-xl text-xs text-white placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Create Strong Password *
              </label>
              <div className="relative">
                <Lock className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="At least 8 characters"
                  className="w-full pl-10 pr-4 py-2.5 bg-[var(--bg-deep)] border border-[var(--border-soft)] rounded-xl text-xs text-white placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>
            </div>

            <button
              type="submit"
              className="w-full py-3 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-bold rounded-xl shadow-lg shadow-blue-500/25 transition-all flex items-center justify-center gap-2 mt-4"
            >
              <span>Continue to Store Setup</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          </form>
        ) : (
          /* Step 2 Form */
          <form onSubmit={handleFinishRegister} className="p-8 space-y-4">
            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Store / Business Name *
              </label>
              <div className="relative">
                <Store className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  required
                  value={storeName}
                  onChange={(e) => setStoreName(e.target.value)}
                  placeholder="e.g. Patel Supermarket & Kirana"
                  className="w-full pl-10 pr-4 py-2.5 bg-[var(--bg-deep)] border border-[var(--border-soft)] rounded-xl text-xs text-white placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                Primary Business Industry
              </label>
              <select
                value={businessCategory}
                onChange={(e) => setBusinessCategory(e.target.value)}
                className="w-full px-3 py-2.5 bg-[var(--bg-deep)] border border-[var(--border-soft)] rounded-xl text-xs text-white outline-none"
              >
                <option value="Grocery & Supermarket">Grocery & Supermarket (FMCG)</option>
                <option value="Apparel & Footwear">Apparel & Footwear</option>
                <option value="Electronics & Mobile">Electronics & Mobile Accessories</option>
                <option value="Pharmacy & Healthcare">Pharmacy & Healthcare</option>
                <option value="Restaurant & Cafe">Restaurant & Quick Service Food</option>
                <option value="General Retail">General Retail</option>
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                City / Location
              </label>
              <div className="relative">
                <Building className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  value={city}
                  onChange={(e) => setCity(e.target.value)}
                  placeholder="e.g. Mumbai"
                  className="w-full pl-10 pr-4 py-2.5 bg-[var(--bg-deep)] border border-[var(--border-soft)] rounded-xl text-xs text-white placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>
            </div>

            <div className="p-3 rounded-xl bg-blue-500/10 border border-blue-500/20 text-xs text-blue-300">
              <div className="font-semibold mb-1">🎉 14-Day Free Pro Trial Included</div>
              <p className="text-[11px] text-[var(--text-tertiary)]">
                Unlimited products, 5 staff accounts, thermal receipt printing, and GST reports.
              </p>
            </div>

            <div className="flex items-center gap-3 pt-2">
              <button
                type="button"
                onClick={() => setStep(1)}
                className="px-4 py-2.5 bg-[var(--surface-strong)] hover:bg-[var(--surface)] text-xs text-[var(--text-secondary)] rounded-xl"
              >
                Back
              </button>
              <button
                type="submit"
                className="flex-1 py-3 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 text-xs font-bold rounded-xl shadow-lg shadow-blue-500/25 transition-all flex items-center justify-center gap-2"
              >
                <span>Launch Store</span>
                <CheckCircle2 className="w-4 h-4" />
              </button>
            </div>
          </form>
        )}

        {/* Footer */}
        <div className="p-4 bg-[var(--bg-soft)] border-t border-[var(--border-soft)] text-center text-xs text-[var(--text-tertiary)]">
          Already registered?{" "}
          <Link href="/login" className="text-[var(--text-primary)] font-semibold hover:underline">
            Sign in here
          </Link>
        </div>
      </div>
    </div>
  );
}
