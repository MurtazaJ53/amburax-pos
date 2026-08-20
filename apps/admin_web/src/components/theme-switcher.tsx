"use client";

import React, { useEffect, useState } from "react";
import { Sun, Moon, Monitor, Check } from "lucide-react";

type Theme = "light" | "dark" | "system";

export function ThemeSwitcher() {
  const [theme, setTheme] = useState<Theme>("light");
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    // Default to light, not to the operating system.
    //
    // The theme should come from the use scene, not the device setting. This
    // runs on a counter in an Indian shop: daylight through an open front,
    // fluorescent tubes overhead, a cheap phone at low brightness. Dark UI is
    // harder to read in that light, not easier — dark suits dim rooms and long
    // focus sessions, and a shop counter is neither.
    //
    // An explicit choice still wins, including "system"; only the untouched
    // default changed.
    const savedTheme = localStorage.getItem("theme") as Theme | null;
    setTheme(savedTheme ?? "light");
  }, []);

  const updateTheme = (newTheme: Theme) => {
    setTheme(newTheme);
    localStorage.setItem("theme", newTheme);
    setIsOpen(false);

    const root = document.documentElement;
    if (newTheme === "system") {
      const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
      root.setAttribute("data-theme", isDark ? "dark" : "light");
    } else {
      root.setAttribute("data-theme", newTheme);
    }
  };

  useEffect(() => {
    if (theme !== "system") return;

    const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    const handleSystemThemeChange = (e: MediaQueryListEvent) => {
      document.documentElement.setAttribute("data-theme", e.matches ? "dark" : "light");
    };

    mediaQuery.addEventListener("change", handleSystemThemeChange);
    return () => mediaQuery.removeEventListener("change", handleSystemThemeChange);
  }, [theme]);

  const activeIcon = () => {
    if (theme === "light") return <Sun className="w-4 h-4 text-[var(--warning)]" />;
    if (theme === "dark") return <Moon className="w-4 h-4 text-[var(--primary-light)]" />;
    return <Monitor className="w-4 h-4 text-[var(--text-secondary)]" />;
  };

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="p-2 rounded-xl bg-[var(--surface)] border border-[var(--border-soft)] text-[var(--text-secondary)] hover:bg-[var(--bg-base)] transition-all flex items-center justify-center shadow-sm"
        title="Switch theme"
      >
        {activeIcon()}
      </button>

      {isOpen && (
        <>
          <div
            className="fixed inset-0 z-40"
            onClick={() => setIsOpen(false)}
          />
          <div className="absolute right-0 mt-2 w-40 rounded-2xl bg-[var(--surface)] border border-[var(--border-soft)] p-1.5 shadow-lg z-50 animate-in fade-in slide-in-from-top-2 duration-100">
            <button
              onClick={() => updateTheme("light")}
              className={`w-full flex items-center justify-between px-3 py-2 rounded-xl text-xs font-bold transition-all ${
                theme === "light"
                  ? "bg-[var(--primary)]/10 text-[var(--primary-hover)] dark:text-[var(--primary-light)]"
                  : "text-[var(--text-secondary)] hover:bg-[var(--bg-base)]"
              }`}
            >
              <div className="flex items-center gap-2">
                <Sun className="w-3.5 h-3.5" />
                <span>Light</span>
              </div>
              {theme === "light" && <Check className="w-3.5 h-3.5" />}
            </button>

            <button
              onClick={() => updateTheme("dark")}
              className={`w-full flex items-center justify-between px-3 py-2 rounded-xl text-xs font-bold transition-all ${
                theme === "dark"
                  ? "bg-[var(--primary)]/10 text-[var(--primary-hover)] dark:text-[var(--primary-light)]"
                  : "text-[var(--text-secondary)] hover:bg-[var(--bg-base)]"
              }`}
            >
              <div className="flex items-center gap-2">
                <Moon className="w-3.5 h-3.5" />
                <span>Dark</span>
              </div>
              {theme === "dark" && <Check className="w-3.5 h-3.5" />}
            </button>

            <button
              onClick={() => updateTheme("system")}
              className={`w-full flex items-center justify-between px-3 py-2 rounded-xl text-xs font-bold transition-all ${
                theme === "system"
                  ? "bg-[var(--primary)]/10 text-[var(--primary-hover)] dark:text-[var(--primary-light)]"
                  : "text-[var(--text-secondary)] hover:bg-[var(--bg-base)]"
              }`}
            >
              <div className="flex items-center gap-2">
                <Monitor className="w-3.5 h-3.5" />
                <span>System</span>
              </div>
              {theme === "system" && <Check className="w-3.5 h-3.5" />}
            </button>
          </div>
        </>
      )}
    </div>
  );
}
