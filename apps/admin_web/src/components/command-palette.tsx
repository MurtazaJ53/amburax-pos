"use client";

import React, { useEffect, useState, useMemo } from "react";
import { useRouter } from "next/navigation";
import {
  Search,
  ShoppingCart,
  Package,
  Users,
  Receipt,
  Clock,
  Truck,
  DollarSign,
  UserCheck,
  BarChart3,
  ShieldCheck,
  Building2,
  PlusCircle,
  X,
  FileSpreadsheet,
} from "lucide-react";

type CommandItem = {
  id: string;
  title: string;
  category: "Navigation" | "Quick Action" | "Governance";
  icon: React.ComponentType<{ className?: string }>;
  shortcut?: string;
  url: string;
  keywords: string;
};

const COMMANDS: CommandItem[] = [
  {
    id: "pos-sale",
    title: "New POS Sale / Checkout",
    category: "Quick Action",
    icon: ShoppingCart,
    shortcut: "F2",
    url: "/pos",
    keywords: "pos checkout cart billing cash card upi scanner invoice",
  },
  {
    id: "inventory-new",
    title: "Add New Product",
    category: "Quick Action",
    icon: PlusCircle,
    shortcut: "Ctrl+N",
    url: "/inventory?action=new",
    keywords: "product item stock barcode sku add create",
  },
  {
    id: "customer-new",
    title: "Register New Customer",
    category: "Quick Action",
    icon: Users,
    url: "/customers?action=new",
    keywords: "customer khata client credit phone debtor",
  },
  {
    id: "expense-new",
    title: "Record Expense",
    category: "Quick Action",
    icon: DollarSign,
    url: "/expenses?action=new",
    keywords: "expense spend payment cash rent bill salary",
  },
  {
    id: "day-book",
    title: "Day Book (Roj Mel)",
    category: "Quick Action",
    icon: Clock,
    // Was /day-close, which has never existed and answered 404. The day book
    // is the screen that reconciles the drawer, so it is what the entry was
    // reaching for.
    url: "/day-book",
    keywords: "day book roj mel close cash drawer jama udhaar float register",
  },
  {
    id: "nav-dashboard",
    title: "Command Center Dashboard",
    category: "Navigation",
    icon: Building2,
    url: "/",
    keywords: "home dashboard metrics stats sales revenue",
  },
  {
    id: "nav-inventory",
    title: "Inventory & Category Catalog",
    category: "Navigation",
    icon: Package,
    url: "/inventory",
    keywords: "inventory products stock items categories catalog",
  },
  {
    id: "nav-customers",
    title: "Customers & Khata Credit Ledger",
    category: "Navigation",
    icon: Users,
    url: "/customers",
    keywords: "customers khata balance dues credit ledger",
  },
  {
    id: "nav-sales",
    title: "Sales History & Receipts",
    category: "Navigation",
    icon: Receipt,
    url: "/sales",
    keywords: "sales history transactions orders receipts refund void",
  },
  {
    id: "nav-purchases",
    title: "Purchases & Supplier Inwards",
    category: "Navigation",
    icon: Truck,
    url: "/purchases",
    keywords: "purchases suppliers vendor orders inwards stock goods",
  },
  {
    id: "nav-attendance",
    title: "Staff Directory & Attendance",
    category: "Navigation",
    icon: UserCheck,
    url: "/attendance",
    keywords: "staff employee clock in out attendance shifts roster",
  },
  {
    id: "nav-reports",
    title: "Reports & Profit & Loss Statement",
    category: "Navigation",
    icon: BarChart3,
    url: "/reports",
    keywords: "reports profit loss pnl analytics revenue taxes gst",
  },
  {
    id: "nav-security",
    title: "Security, Passkeys & Active Sessions",
    category: "Governance",
    icon: ShieldCheck,
    url: "/security",
    keywords: "security passkeys mfa totp 2fa sessions revoke audit",
  },
  {
    id: "nav-platform",
    title: "Platform Admin & Shop Governance",
    category: "Governance",
    icon: Building2,
    url: "/platform",
    keywords: "platform admin shops suspend activate plan audit metrics",
  },
  {
    id: "nav-gst-export",
    title: "GST Export Center (GSTR-1 / GSTR-3B)",
    category: "Governance",
    icon: FileSpreadsheet,
    url: "/sales?tab=gst",
    keywords: "gst gstr1 gstr3b export tax filing returns json csv",
  },
];

type CommandPaletteProps = {
  isOpen: boolean;
  onClose: () => void;
};

export function CommandPalette({ isOpen, onClose }: CommandPaletteProps) {
  const [query, setQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const router = useRouter();

  // Keyboard shortcut listener for Ctrl+K / Cmd+K and Esc
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        if (isOpen) {
          onClose();
        } else {
          // Open triggered from parent or global hook
        }
      } else if (e.key === "Escape" && isOpen) {
        e.preventDefault();
        onClose();
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  const filteredCommands = useMemo(() => {
    if (!query.trim()) return COMMANDS;
    const lower = query.toLowerCase();
    return COMMANDS.filter(
      (cmd) =>
        cmd.title.toLowerCase().includes(lower) ||
        cmd.category.toLowerCase().includes(lower) ||
        cmd.keywords.toLowerCase().includes(lower)
    );
  }, [query]);

  useEffect(() => {
    setSelectedIndex(0);
  }, [query]);

  const handleSelect = (cmd: CommandItem) => {
    onClose();
    router.push(cmd.url);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIndex((prev) => (prev + 1) % (filteredCommands.length || 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIndex(
        (prev) => (prev - 1 + filteredCommands.length) % (filteredCommands.length || 1)
      );
    } else if (e.key === "Enter" && filteredCommands[selectedIndex]) {
      e.preventDefault();
      handleSelect(filteredCommands[selectedIndex]);
    }
  };

  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-start justify-center pt-20 px-4 bg-black/60 backdrop-blur-sm transition-opacity"
      onClick={onClose}
    >
      <div
        className="w-full max-w-2xl bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[75vh] animate-in fade-in zoom-in-95 duration-150"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Search Input Bar */}
        <div className="flex items-center gap-3 px-4 py-3.5 border-b border-[var(--border-soft)] bg-[var(--bg-soft)]">
          <Search className="w-5 h-5 text-[var(--text-tertiary)] shrink-0" />
          <input
            type="text"
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Type a command, feature, or page... (e.g. POS, Stock, Khata)"
            className="flex-1 bg-transparent text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none text-base"
          />
          {query && (
            <button
              onClick={() => setQuery("")}
              className="text-[var(--text-tertiary)] hover:text-[var(--text-primary)] p-1 rounded"
            >
              <X className="w-4 h-4" />
            </button>
          )}
          <kbd className="hidden sm:inline-flex items-center gap-1 px-2 py-0.5 text-xs font-mono text-[var(--text-tertiary)] bg-[var(--surface-strong)] rounded border border-[var(--border-soft)]">
            ESC
          </kbd>
        </div>

        {/* Command List Results */}
        <div className="flex-1 overflow-y-auto p-2 space-y-1">
          {filteredCommands.length === 0 ? (
            <div className="p-8 text-center text-[var(--text-tertiary)] text-sm">
              No matching commands or pages found for &quot;{query}&quot;.
            </div>
          ) : (
            filteredCommands.map((cmd, idx) => {
              const Icon = cmd.icon;
              const isSelected = idx === selectedIndex;
              return (
                <button
                  key={cmd.id}
                  onClick={() => handleSelect(cmd)}
                  onMouseEnter={() => setSelectedIndex(idx)}
                  className={`w-full flex items-center justify-between gap-3 px-3.5 py-2.5 rounded-xl text-left transition-all ${
                    isSelected
                      ? "bg-[var(--primary)] text-white shadow-md shadow-blue-500/20"
                      : "text-[var(--text-primary)] hover:bg-[var(--surface-strong)]"
                  }`}
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <div
                      className={`p-2 rounded-lg ${
                        isSelected
                          ? "bg-white/20 text-white"
                          : "bg-[var(--surface-strong)] text-[var(--primary-light)]"
                      }`}
                    >
                      <Icon className="w-4 h-4" />
                    </div>
                    <div className="truncate">
                      <div className="text-sm font-medium leading-snug truncate">
                        {cmd.title}
                      </div>
                      <div
                        className={`text-xs capitalize ${
                          isSelected ? "text-blue-100" : "text-[var(--text-tertiary)]"
                        }`}
                      >
                        {cmd.category}
                      </div>
                    </div>
                  </div>

                  {cmd.shortcut && (
                    <kbd
                      className={`px-2 py-0.5 text-xs font-mono rounded border ${
                        isSelected
                          ? "bg-white/20 text-white border-white/30"
                          : "bg-[var(--surface-strong)] text-[var(--text-tertiary)] border-[var(--border-soft)]"
                      }`}
                    >
                      {cmd.shortcut}
                    </kbd>
                  )}
                </button>
              );
            })
          )}
        </div>

        {/* Footer info bar */}
        <div className="px-4 py-2 border-t border-[var(--border-soft)] bg-[var(--bg-deep)] flex items-center justify-between text-xs text-[var(--text-tertiary)]">
          <div className="flex items-center gap-3">
            <span>
              Use <kbd className="font-mono bg-[var(--surface-strong)] px-1.5 py-0.5 rounded border border-[var(--border-soft)]">↑</kbd> <kbd className="font-mono bg-[var(--surface-strong)] px-1.5 py-0.5 rounded border border-[var(--border-soft)]">↓</kbd> to navigate
            </span>
            <span>
              <kbd className="font-mono bg-[var(--surface-strong)] px-1.5 py-0.5 rounded border border-[var(--border-soft)]">↵</kbd> to select
            </span>
          </div>
          <span className="hidden sm:inline">Business Hub Command Palette</span>
        </div>
      </div>
    </div>
  );
}
