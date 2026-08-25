"use client";

import React, { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import {
  ArrowLeftRight,
  ClipboardCheck,
  LineChart,
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
  LayoutGrid,
  ChevronDown,
} from "lucide-react";

import { formatRole } from "@/lib/formatters";
import { hasShopFeature, formatPlanTier } from "@/lib/plans";
import type { ShopFeatureKey } from "@/lib/plans";
import type { SessionPayload, ShopMembership } from "@/lib/types";
import { TrialBanner } from "@/components/trial-banner";
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
    | "stocktake"
    | "price-history"
    | "day-book"
    | "purchase-orders"
    | "purchases"
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
  /**
   * "bar" is the default: the screen name, timezone and currency live in the
   * top bar, so no card in the body repeats what the sidebar already shows.
   * "card" is the old titled block, kept for any screen that still wants a
   * heading and a description in the body.
   */
  headerVariant?: "card" | "bar";
  /** Pin the whole screen to the viewport and let the page scroll its own
   *  regions. Use on table screens where the figures and filters should stay
   *  put while only the rows move. */
  fitViewport?: boolean;
  children: ReactNode;
};

export function AdminShell({
  session,
  activeShop,
  activeRoute,
  title,
  subtitle,
  headerVariant = "bar",
  fitViewport = false,
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

  // Split, and feature-gated. This list was 17 items long and shown in full to
  // every shop regardless of plan — including Stock transfers for a
  // single-branch kirana and Purchase orders for a shop with no suppliers.
  // A single-branch grocer needs about six of these; the rest are real
  // features that are simply not part of their day, and a wall of them makes
  // the product feel like it was built for somebody else.
  //
  // `feature` names a flag the SERVER already resolves. Showing a link the
  // backend then 403s is worse than hiding it: the shopkeeper clicks, gets an
  // error, and learns the app is unreliable rather than that the feature costs
  // money.
  const everydayNav = [
    { key: "day-book", label: "Day book (Roj Mel)", href: "/day-book", icon: BookOpen },
    { key: "insights", label: "Report", href: "/insights", icon: TrendingUp },
    { key: "expenses", label: t("settingsExpenses"), href: "/expenses", icon: TrendingDown, feature: "expenses" as const },
    { key: "attendance", label: t("settingsAttendance"), href: "/attendance", icon: Clock, feature: "attendance" as const },
    { key: "team", label: t("settingsStaff"), href: "/team", icon: Users },
    { key: "settings", label: t("settingsBusiness"), href: "/settings", icon: Settings },
  ];

  // Real work, just not daily. Collapsed rather than removed — a wholesaler
  // lives in Purchase orders, and hiding it outright would break their day.
  const occasionalNav = [
    { key: "stocktake", label: "Stocktake", href: "/stocktake", icon: ClipboardCheck },
    { key: "suppliers", label: t("settingsPurchases"), href: "/suppliers", icon: Truck, feature: "supplier_directory" as const },
    { key: "purchase-orders", label: "Purchase orders", href: "/purchase-orders", icon: ClipboardList, feature: "purchase_workflow" as const },
    { key: "price-history", label: "Supplier prices", href: "/price-history", icon: LineChart, feature: "supplier_directory" as const },
    { key: "transfers", label: "Stock transfers", href: "/transfers", icon: ArrowLeftRight, feature: "multi_branch" as const },
    { key: "labels", label: "Barcode labels", href: "/labels", icon: Tags },
    { key: "import", label: t("settingsImport"), href: "/import", icon: Upload },
    { key: "data-health", label: t("healthTitle"), href: "/data-health", icon: Stethoscope },
    { key: "tally", label: "Accountant export", href: "/tally", icon: FileSpreadsheet },
  ];

  // Account-level, always reachable. Billing especially: burying the thing a
  // shopkeeper uses to pay you was how a trial could lapse unnoticed.
  const accountNav = [
    { key: "billing", label: t("settingsPlanBilling"), href: "/billing", icon: CreditCard },
    { key: "security", label: t("settingsSecurity"), href: "/security", icon: ShieldCheck },
  ];

  const allowed = <T extends { feature?: ShopFeatureKey }>(items: T[]) =>
    items.filter((item) => !item.feature || hasShopFeature(activeShop, item.feature));

  const adminNav = [...allowed(everydayNav), ...accountNav];
  const moreNav = allowed(occasionalNav);

  /** The label of the nav item you are on. Taken from the nav config rather
   *  than a per-page string, so the word you clicked is the word you land on. */
  const currentScreenLabel =
    [...mainNav, ...adminNav, ...moreNav].find((item) => item.key === activeRoute)?.label ??
    title;

  const [moreOpen, setMoreOpen] = useState(false);
  /** The tools menu, for closing it on a click elsewhere. */
  const moreRef = useRef<HTMLDivElement>(null);

  // Close on a click anywhere else, or on Escape. A menu that stays open
  // over the page is worse than one that never opened.
  useEffect(() => {
    if (!moreOpen) return;
    const onPointerDown = (event: MouseEvent) => {
      if (!moreRef.current?.contains(event.target as Node)) setMoreOpen(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMoreOpen(false);
    };
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [moreOpen]);
  // A menu opens when it is asked for and not before. Remembering it open
  // made sense while it was a section of the nav; as an overlay it would mean
  // a panel covering the page on every single load. The button carries the
  // active highlight instead, so a page inside the menu is still findable
  // without the menu being open.

  const advancedNav = [
    ...(isPlatformAdmin
      ? [
          { key: "migration", label: "Import & migration", href: "/migration", icon: Layers },
          { key: "platform", label: "Admin tools", href: "/platform/shops", icon: Shield },
        ]
      : []),
  ];

  return (
    <div
      className="bg-bg-app text-text-primary flex min-h-screen flex-col transition-colors duration-200 lg:h-screen lg:overflow-hidden"
    >
      {/* Above the header on purpose: this is the one message that has to
          reach a shopkeeper who never opens the billing page. */}
      <TrialBanner />

      {/* Top Bar matching APK Header */}
      <header className="z-40 shrink-0 border-b border-border-soft bg-surface/90 px-4 py-3 backdrop-blur-md transition-colors duration-200 lg:px-8">
        <div className="max-w-[1600px] mx-auto flex items-center justify-between gap-4">
          
          {/* Logo, current screen, and store selector */}
          <div className="flex items-center gap-3">
            <Link href="/" className="flex items-center gap-2.5">
              <div className="w-10 h-10 rounded-2xl bg-gradient-to-br from-[var(--primary-light)] to-[var(--primary-hover)] flex items-center justify-center shadow-[0_4px_12px_rgba(14,165,233,0.3)]">
                <Store className="w-5 h-5 text-[var(--text-primary)]" />
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

            {/* Where you are. This used to be a full card in the page body
                restating what the sidebar already highlighted, plus the
                timezone and currency, which cost the top quarter of every
                screen. */}
            <div className="hidden md:flex items-center gap-3 ml-3 pl-3 border-l border-border-soft">
              <span className="text-sm font-extrabold tracking-tight text-text-primary">
                {currentScreenLabel}
              </span>
              {activeShop && (
                <span className="font-mono text-[10.5px] font-medium text-text-tertiary">
                  {activeShop.shop.timezone || "Asia/Kolkata"} &middot;{" "}
                  {activeShop.shop.currency_code || "INR"}
                </span>
              )}
            </div>

            {activeShop && (
              <div className="hidden xl:flex items-center gap-2 ml-1 pl-3 border-l border-border-soft">
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
              className="px-4 py-2 bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20 rounded-xl text-xs font-extrabold shadow-[0_4px_14px_rgba(14,165,233,0.3)] flex items-center gap-1.5 transition-all"
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
      <div
        className="grid w-full max-w-[1600px] flex-1 grid-cols-1 gap-6 p-4 sm:p-6 lg:grid-cols-[250px_minmax(0,1fr)] lg:overflow-hidden lg:p-8 mx-auto lg:min-h-0"
      >
        
        {/* Left Sidebar Navigation matching APK tabs */}
        <aside className="hidden h-full lg:flex lg:min-h-0 lg:flex-col lg:gap-3">
          {/* The panels. They fit on a normal screen and scroll only on a
              short one - which is better than the alternative, which is what
              just happened: a fixed sidebar taller than its box silently
              clipped More tools off the bottom where nobody could reach it. */}
          <div className="slim-scrollbar flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto pr-0.5">
          
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
                      ? "relative bg-[var(--primary)]/12 text-[var(--primary-hover)] before:absolute before:left-0 before:top-1.5 before:bottom-1.5 before:w-[3px] before:rounded-full before:bg-[var(--primary)]"
                      : item.highlight
                      ? "bg-[var(--primary)]/10 text-primary hover:bg-[var(--primary)]/20"
                      : "text-text-secondary hover:bg-bg-soft hover:text-text-primary"
                  }`}
                >
                  <Icon className={`w-4 h-4 ${isActive ? "text-[var(--text-primary)]" : ""}`} />
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
                      ? "relative bg-[var(--primary)]/12 text-[var(--primary-hover)] before:absolute before:left-0 before:top-1.5 before:bottom-1.5 before:w-[3px] before:rounded-full before:bg-[var(--primary)]"
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
                        ? "relative bg-[var(--primary)]/12 text-[var(--primary-hover)] before:absolute before:left-0 before:top-1.5 before:bottom-1.5 before:w-[3px] before:rounded-full before:bg-[var(--primary)]"
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
          </div>

          {/* Everything else. Not removed: a wholesaler lives in Purchase
              orders. Pinned to the bottom so it is reachable whatever the
              panels above it are doing. */}
          {/* An overlay, not an expansion.

              Anything that grows INSIDE the sidebar changes the document
              height, and the browser then re-resolves where the viewport
              belongs - which is what threw the page to the top. A menu that is
              absolutely positioned is out of the flow entirely, so the page it
              sits over cannot move. That removes the bug rather than
              compensating for it. */}
          {moreNav.length > 0 && (
            <div ref={moreRef} className="relative shrink-0">
              <button
                type="button"
                onClick={() => setMoreOpen((open) => !open)}
                aria-expanded={moreOpen}
                aria-haspopup="menu"
                className={`focus-ring flex w-full cursor-pointer items-center justify-between gap-2 rounded-[16px] border px-3.5 py-3 text-xs font-bold shadow-sm transition-colors ${
                  moreOpen || moreNav.some((item) => item.key === activeRoute)
                    ? "border-[var(--primary)]/25 bg-[var(--primary)]/10 text-[var(--primary-dark)]"
                    : "border-border-soft bg-surface text-text-secondary hover:text-text-primary"
                }`}
              >
                <span className="flex items-center gap-3">
                  <LayoutGrid className="h-4 w-4" />
                  More tools
                </span>
                <ChevronDown
                  className={`h-3.5 w-3.5 transition-transform duration-200 ${
                    moreOpen ? "rotate-180" : ""
                  }`}
                />
              </button>

              {moreOpen && (
                <div
                  role="menu"
                  className="animate-fade-in-up absolute bottom-full left-0 z-40 mb-2 max-h-[60vh] w-full min-w-[220px] overflow-y-auto rounded-[16px] border border-border-soft bg-surface p-2 shadow-lg"
                >
                  {moreNav.map((item) => {
                    const Icon = item.icon;
                    const isActive = activeRoute === item.key;
                    return (
                      <Link
                        key={item.key}
                        href={item.href}
                        onClick={() => setMoreOpen(false)}
                        className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-xs font-bold transition-colors ${
                          isActive
                            ? "bg-[var(--primary)]/12 text-[var(--primary-hover)]"
                            : "text-text-secondary hover:bg-bg-soft hover:text-text-primary"
                        }`}
                      >
                        <Icon className="h-4 w-4 shrink-0" />
                        <span>{item.label}</span>
                      </Link>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </aside>

        {/* Content Area */}
        <main
          className={`flex min-w-0 flex-1 flex-col lg:min-h-0 ${
            fitViewport ? "lg:overflow-hidden" : "slim-scrollbar lg:overflow-y-auto"
          }`}
        >
          
          {/* The screen name, timezone and currency now live in the top bar,
              so nothing in the body repeats them. Kept for assistive tech,
              which still needs the page announced. */}
          {headerVariant === "bar" && (
            <span className="sr-only">
              {title}. {subtitle}
            </span>
          )}

          {/* Header Card */}
          {headerVariant === "card" && (
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
          )}

          {/* Child Page Rendering */}
          <div className={`flex-1 ${fitViewport ? "min-h-0 flex flex-col" : ""}`}>
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}
