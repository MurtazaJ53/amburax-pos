import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatCurrency(
  amount: number | string | null | undefined,
  currencyCode = "INR",
  locale = "en-IN"
): string {
  const num = typeof amount === "string" ? parseFloat(amount) : amount ?? 0;
  if (isNaN(num)) return "₹0.00";
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: currencyCode,
    maximumFractionDigits: 2,
    minimumFractionDigits: 2,
  }).format(num);
}

export function formatDate(
  dateStr: string | Date | null | undefined,
  includeTime = false
): string {
  if (!dateStr) return "—";
  const date = typeof dateStr === "string" ? new Date(dateStr) : dateStr;
  if (isNaN(date.getTime())) return "—";

  return new Intl.DateTimeFormat("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    ...(includeTime
      ? { hour: "2-digit", minute: "2-digit", hour12: true }
      : {}),
  }).format(date);
}

export function formatRelativeTime(dateStr: string | Date | null | undefined): string {
  if (!dateStr) return "—";
  const date = typeof dateStr === "string" ? new Date(dateStr) : dateStr;
  if (isNaN(date.getTime())) return "—";

  const diffMs = Date.now() - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHour = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHour / 24);

  if (diffSec < 60) return "Just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHour < 24) return `${diffHour}h ago`;
  if (diffDay < 7) return `${diffDay}d ago`;
  return formatDate(date);
}

export function formatPercentage(value: number | string | null | undefined): string {
  const num = typeof value === "string" ? parseFloat(value) : value ?? 0;
  if (isNaN(num)) return "0.0%";
  return `${num.toFixed(1)}%`;
}

/** A stock or line quantity as a person would write it.
 *
 *  Quantities are decimal on the wire ("1.000") because a shop can sell 1.5 kg
 *  of rice. Printing that raw put "1.000 left" on the dashboard, which reads
 *  as a machine talking to itself. Whole numbers lose the trailing zeros; a
 *  genuine fraction keeps them.
 */
export function formatQuantity(raw: string | number | null | undefined): string {
  const value = Number(raw);
  if (!Number.isFinite(value)) return "0";
  if (Number.isInteger(value)) return value.toLocaleString("en-IN");
  return parseFloat(value.toFixed(3)).toLocaleString("en-IN", {
    maximumFractionDigits: 3,
  });
}
