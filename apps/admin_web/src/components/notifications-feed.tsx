"use client";

import React, { useCallback, useEffect, useState } from "react";
import {
  Bell,
  CheckCircle2,
  AlertTriangle,
  CheckCheck,
} from "lucide-react";
import { formatDate } from "@/lib/utils";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



export interface NotificationItem {
  id: string;
  title: string;
  message: string;
  type: "warning" | "success" | "info";
  is_read: boolean;
  created_at: string;
}

export function NotificationsFeed() {
  const [notifications, setNotifications] = useState<NotificationItem[]>([]);
  const [filter, setFilter] = useState<"all" | "unread">("all");
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const unreadCount = notifications.filter((n) => !n.is_read).length;

  const load = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/notifications");
      if (!res.ok) throw new Error(`Could not load notifications (${res.status})`);
      const body = await res.json();
      setNotifications(Array.isArray(body) ? body : []);
    } catch (err) {
      setError(errorMessage(err, "Something went wrong loading notifications."));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const handleMarkAllRead = async () => {
    // Optimistic: the list should feel instant. Reload afterwards so a failed
    // write cannot leave the badge showing zero unread when the server
    // disagrees.
    setNotifications((prev) => prev.map((n) => ({ ...n, is_read: true })));
    try {
      const res = await fetch("/api/notifications/read-all", { method: "POST" });
      if (!res.ok) throw new Error(`Could not mark all read (${res.status})`);
    } catch (err) {
      setError(errorMessage(err, "Could not mark all as read."));
    } finally {
      await load();
    }
  };

  const handleToggleRead = async (id: string) => {
    const current = notifications.find((n) => n.id === id);
    // The API can only mark as read; there is no "unread" endpoint, so don't
    // pretend the toggle works both ways.
    if (!current || current.is_read) return;

    setNotifications((prev) =>
      prev.map((n) => (n.id === id ? { ...n, is_read: true } : n))
    );
    try {
      const res = await fetch(`/api/notifications/${id}/read`, { method: "POST" });
      if (!res.ok) throw new Error(`Could not mark as read (${res.status})`);
    } catch (err) {
      setError(errorMessage(err, "Could not mark as read."));
      await load();
    }
  };

  const filtered = notifications.filter((n) => {
    if (filter === "unread") return !n.is_read;
    return true;
  });

  return (
    <div className="space-y-6 max-w-4xl">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-[var(--text-primary)] tracking-tight">Store Notifications & Alerts</h2>
          <p className="text-xs text-[var(--text-tertiary)]">
            Real-time stock alerts, khata receipts, shift check-ins, and system notices
          </p>
        </div>

        <div className="flex items-center gap-3">
          {unreadCount > 0 && (
            <button
              onClick={handleMarkAllRead}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-[var(--surface-strong)] hover:bg-[var(--surface)] border border-[var(--border-soft)] text-xs text-white rounded-xl transition-colors"
            >
              <CheckCheck className="w-3.5 h-3.5 text-blue-400" />
              <span>Mark all read</span>
            </button>
          )}
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-2 border-b border-[var(--border-soft)]">
        <button
          onClick={() => setFilter("all")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors ${
            filter === "all"
              ? "border-[var(--primary)] text-[var(--text-primary)]"
              : "border-transparent text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
          }`}
        >
          All Activity ({notifications.length})
        </button>
        <button
          onClick={() => setFilter("unread")}
          className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
            filter === "unread"
              ? "border-[var(--primary)] text-[var(--text-primary)]"
              : "border-transparent text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
          }`}
        >
          <span>Unread Alerts</span>
          {unreadCount > 0 && (
            <span className="px-1.5 py-0.2 text-[9px] font-bold rounded-full bg-blue-500 text-white">
              {unreadCount}
            </span>
          )}
        </button>
      </div>

      {error && (
        <div className="mb-3 rounded-2xl border border-[var(--error)]/30 bg-[var(--error)]/10 px-5 py-4 text-sm font-semibold text-[var(--error-strong)]">
          {error}
        </div>
      )}

      {/* Feed List */}
      <div className="space-y-3">
        {isLoading && notifications.length === 0 && (
          <div className="p-12 text-center bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl text-xs text-[var(--text-tertiary)]">
            Loading notifications&hellip;
          </div>
        )}
        {!isLoading && filtered.length === 0 ? (
          <div className="p-12 text-center bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl">
            <Bell className="w-8 h-8 text-[var(--text-disabled)] mx-auto mb-2" />
            <p className="text-xs text-[var(--text-tertiary)]">No unread notifications.</p>
          </div>
        ) : (
          filtered.map((item) => (
            <div
              key={item.id}
              onClick={() => handleToggleRead(item.id)}
              className={`p-4 rounded-2xl border transition-all cursor-pointer flex items-start gap-4 ${
                !item.is_read
                  ? "bg-[var(--surface-strong)] border-blue-500/30 shadow-md"
                  : "bg-[var(--surface)] border-[var(--border-soft)] opacity-80"
              }`}
            >
              <div
                className={`w-9 h-9 rounded-xl flex items-center justify-center shrink-0 ${
                  item.type === "warning"
                    ? "bg-[var(--warning)]/10 text-[var(--warning)]"
                    : item.type === "success"
                    ? "bg-[var(--success)]/10 text-[var(--success)]"
                    : "bg-blue-500/10 text-blue-400"
                }`}
              >
                {item.type === "warning" ? (
                  <AlertTriangle className="w-5 h-5" />
                ) : item.type === "success" ? (
                  <CheckCircle2 className="w-5 h-5" />
                ) : (
                  <Bell className="w-5 h-5" />
                )}
              </div>

              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2">
                  <h4 className="text-xs font-bold text-[var(--text-primary)]">{item.title}</h4>
                  <span className="text-[10px] text-[var(--text-tertiary)] font-mono">
                    {formatDate(item.created_at, true)}
                  </span>
                </div>
                <p className="text-xs text-[var(--text-secondary)] mt-1">{item.message}</p>
              </div>

              {!item.is_read && (
                <div className="w-2 h-2 rounded-full bg-blue-500 shrink-0 self-center" />
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
