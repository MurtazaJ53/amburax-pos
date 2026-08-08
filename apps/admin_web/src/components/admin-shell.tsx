"use client";

import React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import {
  ArrowLeftRight,
  BookOpen,
  ClipboardList,
  Tags,
  LayoutDashboard,
  ShoppingCart,
  Package,
  Users,
  Receipt,
  FileSpreadsheet,
  Stethoscope,
  Upload,
  TrendingDown,
  TrendingUp,
  Clock,
  Settings,
  Shield,
  Truck,
  LogOut,
  Store,
  CreditCard,
  Layers,
  Bell,
  ShieldCheck,
} from "lucide-react";

import { formatRole } from "@/lib/formatters";
import { formatPlanTier } from "@/lib/plans";
import type { SessionPayload, ShopMembership } from "@/lib/types";
import { ThemeSwitcher } from "@/components/theme-switcher";
import { LanguageSwitcher } from "@/components/language-switcher";
import { useT } from "@/lib/i18n";

type AdminShellProps = {
  session: SessionPayload;
  activeShop: ShopMembership | null;
  activeRoute:
    | "notifications"
    | "overview"
    | "pos"
    | "inventory"
    | "customers"
    | "sales"
    | "expenses"
    | "attendance"
    | "insights"
    | "data-health"
    | "import"
    | "billing"
    | "tally"
    | "reports"
    | "suppliers"
    | "transfers"
    | "labels"
    | "day-book"
    | "purchase-orders"
    | "purchases"
    | "chat"
    | "settings"
    | "pulse"
    | "team"
    | "security"
    | "sessions"
    | "audit"
    | "plan"
    | "payments"
    | "migration"
    | "erpnext"
    | "platform";
  title: string;
  subtitle: string;
  surfaceMode?: "product" | "internal";
  children: ReactNode;
};

export function AdminShell({
  session,
  activeShop,
  activeRoute,
  title,
  subtitle,
  children,
}: AdminShellProps) {
  const router = useRouter();
  const t = useT();
  const workspaceRole = activeShop?.role ?? null;
  const workspaceRoleLabel =
    activeShop?.role_label ?? (workspaceRole ? formatRole(workspaceRole) : "Staff");
  const workspacePlanLabel = activeShop ? formatPlanTier(activeShop.shop.plan_tier) : "Growth";
  const isPlatformAdmin = session?.user?.is_platform_admin ?? false;

  const handleLogout = async () => {
    try {
      await fetch("/api/auth/logout", { method: "POST" });
    } catch {
      // Ignore network errors on logout
    }
    router.push("/login");
    router.refresh();
  };

  // APK Core navigation items
  const mainNav = [
    { key: "overview", label: t("navHome"), href: "/", icon: LayoutDashboard },
    { key: "inventory", label: t("navStock"), href: "/inventory", icon: Package },
    { key: "customers", label: t("navClients"), href: "/customers", icon: Users },
    { key: "sales", label: t("navHistory"), href: "/sales", icon: Receipt },
    { key: "pos", label: t("navPos"), href: "/pos", icon: ShoppingCart, highlight: true },
  ];

  const adminNav = [
    { key: "day-book", label: "Day book (Roj Mel)", href: "/day-book", icon: BookOpen },
    { key: "insights", label: "Business pulse", href: "/insights", icon: TrendingUp },
    { key: "settings", label: t("settingsBusiness"), href: "/settings", icon: Settings },
    { key: "team", label: t("settingsStaff"), href: "/team", icon: Users },
    { key: "attendance", label: t("settingsAttendance"), href: "/attendance", icon: Clock },
    { key: "expenses", label: t("settingsExpenses"), href: "/expenses", icon: TrendingDown },
    { key: "suppliers", label: t("settingsPurchases"), href: "/suppliers", icon: Truck },
    { key: "purchase-orders", label: "Purchase orders", href: "/purchase-orders", icon: ClipboardList },
    { key: "transfers", label: "Stock transfers", href: "/transfers", icon: ArrowLeftRight },
    { key: "labels", label: "Barcode labels", href: "/labels", icon: Tags },
    { key: "import", label: t("settingsImport"), href: "/import", icon: Upload },
    { key: "data-health", label: t("healthTitle"), href: "/data-health", icon: Stethoscope },
    { key: "tally", label: "Accountant export", href: "/tally", icon: FileSpreadsheet },
    { key: "billing", label: t("settingsPlanBilling"), href: "/billing", icon: CreditCard },
    { key: "security", label: t("settingsSecurity"), href: "/security", icon: ShieldCheck },
  ];

  const advancedNav = [
    ...(isPlatformAdmin
      ? [
          { key: "migration", label: "Import & migration", href: "/migration", icon: Layers },
          { key: "platform", label: "Admin tools", href: "/platform/shops", icon: Shield },
        ]
      : []),
  ];

  return (
    <div className="min-h-screen bg-bg-app text-text-primary flex flex-col transition-colors duration-200">
      {/* Top Bar matching APK Header */}
      <header className="sticky top-0 z-40 bg-surface/90 backdrop-blur-md border-b border-border-soft px-4 lg:px-8 py-3 transition-colors duration-200">
        <div className="max-w-[1600px] mx-auto flex items-center justify-between gap-4">
          
          {/* Logo & Store Selector */}
          <div className="flex items-center gap-3">
            <Link href="/" className="flex items-center gap-2.5">
              <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-[var(--primary-light)] to-[var(--primary-hover)] flex items-center justify-center shadow-[0_4px_12px_rgba(14,165,233,0.3)]">
                <Store className="w-5 h-5 text-white" />
              </div>
              <div>
                <span className="text-base font-black text-text-primary tracking-tight hidden sm:inline">
                  Business Hub
                </span>
                <span className="block text-[10px] font-bold text-text-secondary uppercase tracking-wider">
                  Cloud POS
                </span>
              </div>
            </Link>

            {activeShop && (
              <div className="hidden md:flex items-center gap-2 ml-4 pl-4 border-l border-border-soft">
                <div className="px-3 py-1.5 bg-bg-base border border-border-soft rounded-xl flex items-center gap-2">
                  <span className="w-2 h-2 rounded-full bg-[var(--success)] animate-pulse" />
                  <span className="text-xs font-bold text-text-primary">{activeShop.shop.name}</span>
                  <span className="px-1.5 py-0.5 rounded-md text-[10px] font-extrabold bg-[var(--primary)]/10 text-primary uppercase">
                    {workspacePlanLabel}
                  </span>
                </div>
              </div>
            )}
          </div>

          {/* Quick Actions & Profile */}
          <div className="flex items-center gap-2.5">
            <Link
              href="/pos"
              className="px-4 py-2 bg-gradient-to-r from-[var(--primary-light)] to-[var(--primary-hover)] hover:from-[var(--primary)] hover:to-[var(--primary-dark)] text-white rounded-xl text-xs font-extrabold shadow-[0_4px_14px_rgba(14,165,233,0.3)] flex items-center gap-1.5 transition-all"
            >
              <ShoppingCart className="w-4 h-4" />
              <span className="hidden sm:inline">OPEN POS TERMINAL</span>
              <span className="sm:hidden">POS</span>
            </Link>

            <Link
              href="/notifications"
              className="p-2 rounded-xl bg-bg-base hover:bg-bg-soft border border-border-soft text-text-secondary transition-colors relative"
              title="Notifications"
            >
              <Bell className="w-4 h-4" />
              <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-[var(--primary)]" />
            </Link>

            <LanguageSwitcher />
            <ThemeSwitcher />



            {/* Profile pill */}
            <div className="flex items-center gap-2 pl-2 border-l border-border-soft">
              <div className="w-8 h-8 rounded-xl bg-gradient-to-tr from-[var(--primary)] to-[var(--primary-light)] text-white text-xs font-black flex items-center justify-center shadow-sm">
                {(session?.user?.full_name || session?.user?.email || "U").charAt(0).toUpperCase()}
              </div>
              <div className="hidden xl:block text-left">
                <p className="text-xs font-bold text-text-primary leading-tight truncate max-w-[120px]">
                  {session?.user?.full_name || session?.user?.email || "User"}
                </p>
                <p className="text-[10px] font-semibold text-text-secondary capitalize">
                  {workspaceRoleLabel}
                </p>
              </div>
              <button
                type="button"
                onClick={handleLogout}
                className="p-1.5 text-text-tertiary hover:text-[var(--error-strong)] rounded-lg hover:bg-[var(--error)]/10 transition-colors ml-1"
                title="Sign Out"
              >
                <LogOut className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Main Layout Grid */}
      <div className="flex-1 max-w-[1600px] w-full mx-auto p-4 sm:p-6 lg:p-8 grid grid-cols-1 lg:grid-cols-[250px_minmax(0,1fr)] gap-6">
        
        {/* Left Sidebar Navigation matching APK tabs */}
        <aside className="hidden lg:flex flex-col gap-6">
          
          {/* Main App Navigation Panel (Core Workflows) */}
          <div className="bg-surface border border-border-soft rounded-[24px] p-3.5 shadow-sm space-y-1 transition-colors duration-200">
            <div className="px-3 py-1.5 text-[10px] font-extrabold uppercase tracking-wider text-text-tertiary">
              Core Workflows
            </div>
            {mainNav.map((item) => {
              const Icon = item.icon;
              const isActive = activeRoute === item.key;
              return (
                <Link
                  key={item.key}
                  href={item.href}
                  className={`flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-bold transition-all ${
                    isActive
                      ? "bg-[var(--primary)] text-white shadow-[0_4px_12px_rgba(14,165,233,0.3)]"
                      : item.highlight
                      ? "bg-[var(--primary)]/10 text-primary hover:bg-[var(--primary)]/20"
                      : "text-text-secondary hover:bg-bg-soft hover:text-text-primary"
                  }`}
                >
                  <Icon className={`w-4 h-4 ${isActive ? "text-white" : ""}`} />
                  <span>{item.label}</span>
                </Link>
              );
            })}
          </div>

          {/* Shop Administration Panel (Manage) */}
          <div className="bg-surface border border-border-soft rounded-[24px] p-3.5 shadow-sm space-y-1 transition-colors duration-200">
            <div className="px-3 py-1.5 text-[10px] font-extrabold uppercase tracking-wider text-text-tertiary">
              {t("settingsManage")}
            </div>
            {adminNav.map((item) => {
              const Icon = item.icon;
              const isActive = activeRoute === item.key;
              return (
                <Link
                  key={item.key}
                  href={item.href}
                  className={`flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-bold transition-all ${
                    isActive
                      ? "bg-[var(--primary)] text-white shadow-[0_4px_12px_rgba(14,165,233,0.3)]"
                      : "text-text-secondary hover:bg-bg-soft hover:text-text-primary"
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  <span>{item.label}</span>
                </Link>
              );
            })}
          </div>

          {/* Advanced Panel (Pulse, devices, operations) */}
          {advancedNav.length > 0 && (
            <div className="bg-surface border border-border-soft rounded-[24px] p-3.5 shadow-sm space-y-1 transition-colors duration-200">
              <div className="px-3 py-1.5 text-[10px] font-extrabold uppercase tracking-wider text-text-tertiary">
                Advanced
              </div>
              {advancedNav.map((item) => {
                const Icon = item.icon;
                const isActive = activeRoute === item.key;
                return (
                  <Link
                    key={item.key}
                    href={item.href}
                    className={`flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-bold transition-all ${
                      isActive
                        ? "bg-[var(--primary)] text-white shadow-[0_4px_12px_rgba(14,165,233,0.3)]"
                        : "text-text-secondary hover:bg-bg-soft hover:text-text-primary"
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                    <span>{item.label}</span>
                  </Link>
                );
              })}
            </div>
          )}

          {/* Connected Server Card */}
          <div className="bg-gradient-to-br from-surface to-bg-soft border border-primary/20 rounded-[24px] p-4 text-xs transition-colors duration-200">
            <div className="flex items-center gap-2 text-primary font-extrabold mb-1">
              <span className="w-2 h-2 rounded-full bg-[var(--primary)] animate-pulse" />
              <span>Backend Connected</span>
            </div>
            <p className="text-[11px] text-text-secondary leading-relaxed">
              Real-time POS sync active. Currency: <b>{activeShop?.shop.currency_code || "INR"}</b>
            </p>
          </div>
        </aside>

        {/* Content Area */}
        <main className="flex-1 flex flex-col min-w-0">
          
          {/* Header Card */}
          <div className="bg-surface border border-border-soft rounded-[28px] p-6 sm:p-7 shadow-sm mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 transition-colors duration-200">
            <div>
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-[11px] font-extrabold bg-primary/10 text-primary mb-2 uppercase">
                <Store className="w-3.5 h-3.5" />
                <span>{activeShop?.shop.name || "Business Hub"}</span>
              </div>
              <h1 className="text-2xl sm:text-3xl font-[900] text-text-primary tracking-tight">
                {title}
              </h1>
              <p className="text-xs sm:text-sm font-medium text-text-secondary mt-1">
                {subtitle}
              </p>
            </div>

            <div className="flex items-center gap-3">
              <div className="p-3 bg-bg-base border border-border-soft rounded-2xl text-right transition-colors duration-200">
                <span className="block text-[10px] font-bold text-text-tertiary uppercase">Timezone</span>
                <span className="text-xs font-extrabold text-text-primary">
                  {activeShop?.shop.timezone || "Asia/Kolkata"}
                </span>
              </div>
              <div className="p-3 bg-bg-base border border-border-soft rounded-2xl text-right transition-colors duration-200">
                <span className="block text-[10px] font-bold text-text-tertiary uppercase">Currency</span>
                <span className="text-xs font-extrabold text-primary">
                  {activeShop?.shop.currency_code || "INR"}
                </span>
              </div>
            </div>
          </div>

          {/* Child Page Rendering */}
          <div className="flex-1">{children}</div>
        </main>
      </div>
    </div>
  );
}
