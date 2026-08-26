"use client";

import React, { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import {
  Bell,
  Package,
  CreditCard,
  ShieldCheck,
  CheckCircle2,
  ExternalLink,
} from "lucide-react";
import { formatRelativeTime } from "@/lib/utils";
import { useServerRefresh } from "@/lib/use-server-refresh";

export type NotificationItem = {
  id: string;
  type: "low_stock" | "khata_due" | "security" | "system" | "sale";
  title: string;
  message: string;
  created_at: string;
  is_read: boolean;
  link_url?: string;
};

export function NotificationsPopover() {
  const refreshServerData = useServerRefresh();
  const [isOpen, setIsOpen] = useState(false);
  const [notifications, setNotifications] = useState<NotificationItem[]>([]);
  const [filter, setFilter] = useState<"all" | "unread">("all");
  const popoverRef = useRef<HTMLDivElement>(null);

  const unreadCount = notifications.filter((n) => !n.is_read).length;

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (popoverRef.current && !popoverRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    }
    if (isOpen) {
      document.addEventListener("mousedown", handleClickOutside);
    }
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [isOpen]);

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/notifications");
      if (!res.ok) return;
      const body = await res.json();
      // The API calls it action_url; this component reads link_url. Map it, or
      // every "view" link silently disappears.
      setNotifications(
        (Array.isArray(body) ? body : []).map((n: NotificationItem & { action_url?: string }) => ({
          ...n,
          link_url: n.link_url ?? n.action_url ?? undefined,
        }))
      );
    } catch {
      // The bell is ambient: a failure here must not interrupt the page. The
      // full list on /notifications reports errors properly.
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // Refresh when the popover opens so the count is not stale from page load.
  useEffect(() => {
    if (isOpen) void load();
  }, [isOpen, load]);

  const markAllAsRead = async () => {
    setNotifications((prev) => prev.map((n) => ({ ...n, is_read: true })));
    try {
      await fetch("/api/notifications/read-all", { method: "POST" });
    } finally {
      await load();
      refreshServerData();
    }
  };

  const markAsRead = async (id: string) => {
    const current = notifications.find((n) => n.id === id);
    if (!current || current.is_read) return;
    setNotifications((prev) =>
      prev.map((n) => (n.id === id ? { ...n, is_read: true } : n))
    );
    try {
      await fetch(`/api/notifications/${id}/read`, { method: "POST" });
    } catch {
      await load();
      refreshServerData();
    }
  };

  const filteredNotifications = notifications.filter((n) => {
    if (filter === "unread") return !n.is_read;
    return true;
  });

  const getIcon = (type: NotificationItem["type"]) => {
    switch (type) {
      case "low_stock":
        return <Package className="w-4 h-4 text-[var(--warning)]" />;
      case "khata_due":
        return <CreditCard className="w-4 h-4 text-[var(--error)]" />;
      case "security":
        return <ShieldCheck className="w-4 h-4 text-[var(--success)]" />;
      default:
        return <CheckCircle2 className="w-4 h-4 text-blue-400" />;
    }
  };

  return (
    <div className="relative" ref={popoverRef}>
      {/* Bell Trigger Button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="relative p-2.5 rounded-xl text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-strong)] transition-colors"
        aria-label="Notifications"
      >
        <Bell className="w-5 h-5" />
        {unreadCount > 0 && (
          <span className="absolute top-1.5 right-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-blue-500 text-[10px] font-bold text-white shadow-md shadow-blue-500/40">
            {unreadCount}
          </span>
        )}
      </button>

      {/* Popover Card */}
      {isOpen && (
        <div className="absolute right-0 mt-2 w-96 max-w-[90vw] bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden z-50 animate-in fade-in zoom-in-95 duration-150">
          {/* Header */}
          <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-[var(--bg-soft)]">
            <div className="flex items-center gap-2">
              <span className="font-semibold text-sm text-[var(--text-primary)]">
                Notifications
              </span>
              {unreadCount > 0 && (
                <span className="px-2 py-0.5 text-xs font-semibold bg-blue-500/20 text-blue-400 rounded-full">
                  {unreadCount} new
                </span>
              )}
            </div>
            {unreadCount > 0 && (
              <button
                onClick={markAllAsRead}
                className="text-xs text-[var(--primary-light)] hover:underline font-medium"
              >
                Mark all as read
              </button>
            )}
          </div>

          {/* Filter Tabs */}
          <div className="flex border-b border-[var(--border-soft)] bg-[var(--surface)] px-3 pt-2 gap-2 text-xs">
            <button
              onClick={() => setFilter("all")}
              className={`pb-2 px-2 font-medium transition-colors border-b-2 ${
                filter === "all"
                  ? "border-[var(--primary)] text-[var(--primary-light)]"
                  : "border-transparent text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
              }`}
            >
              All ({notifications.length})
            </button>
            <button
              onClick={() => setFilter("unread")}
              className={`pb-2 px-2 font-medium transition-colors border-b-2 ${
                filter === "unread"
                  ? "border-[var(--primary)] text-[var(--primary-light)]"
                  : "border-transparent text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
              }`}
            >
              Unread ({unreadCount})
            </button>
          </div>

          {/* Notification List */}
          <div className="max-h-80 overflow-y-auto divide-y divide-[var(--border-soft)]">
            {filteredNotifications.length === 0 ? (
              <div className="py-8 text-center text-xs text-[var(--text-tertiary)]">
                No notifications right now.
              </div>
            ) : (
              filteredNotifications.map((notif) => (
                <div
                  key={notif.id}
                  onClick={() => markAsRead(notif.id)}
                  className={`p-3.5 flex gap-3 transition-colors cursor-pointer hover:bg-[var(--surface-strong)] ${
                    !notif.is_read ? "bg-blue-500/5" : ""
                  }`}
                >
                  <div className="mt-0.5 p-2 rounded-lg bg-[var(--surface-strong)] shrink-0 h-8 w-8 flex items-center justify-center">
                    {getIcon(notif.type)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between gap-1">
                      <h4
                        className={`text-xs font-semibold truncate ${
                          !notif.is_read
                            ? "text-[var(--text-primary)]"
                            : "text-[var(--text-secondary)]"
                        }`}
                      >
                        {notif.title}
                      </h4>
                      {!notif.is_read && (
                        <span className="h-1.5 w-1.5 rounded-full bg-blue-500 shrink-0" />
                      )}
                    </div>
                    <p className="text-xs text-[var(--text-tertiary)] mt-0.5 line-clamp-2">
                      {notif.message}
                    </p>
                    <div className="flex items-center justify-between mt-2 text-[10px] text-[var(--text-tertiary)]">
                      <span>{formatRelativeTime(notif.created_at)}</span>
                      {notif.link_url && (
                        <Link
                          href={notif.link_url}
                          onClick={() => setIsOpen(false)}
                          className="flex items-center gap-1 text-[var(--primary-light)] hover:underline"
                        >
                          View <ExternalLink className="w-2.5 h-2.5" />
                        </Link>
                      )}
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>

          {/* Footer link to full notification center */}
          <div className="p-2.5 bg-[var(--bg-deep)] border-t border-[var(--border-soft)] text-center">
            <Link
              href="/notifications"
              onClick={() => setIsOpen(false)}
              className="text-xs font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors inline-block"
            >
              View all notifications →
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
