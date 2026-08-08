/**
 * Locale values and helpers usable from BOTH the server and the client.
 *
 * Kept out of index.tsx because that file carries "use client", which marks
 * every one of its exports client-only — the root layout is a server component
 * and calling isLocale() from there fails at runtime (not at build time).
 */
import { MESSAGES, type Locale, type MessageKey } from "@/lib/i18n/messages.generated";
import { WEB_MESSAGES, type WebMessageKey } from "@/lib/i18n/web-messages";

export type { Locale, MessageKey, WebMessageKey };

/** Any key from either table: the app's reviewed strings or the web-only ones. */
export type AnyMessageKey = MessageKey | WebMessageKey;

/**
 * The lookup table, defined here rather than in index.tsx.
 *
 * index.tsx carries "use client", which marks every one of its exports
 * client-only. A server component importing the table from there compiles
 * cleanly and then fails at runtime — the same trap that once made every page
 * 500. Server components need this data too, so it lives on the shared side.
 *
 * The app's translations win on a key collision: they are the reviewed ones.
 */
export const TABLES: Record<Locale, Record<string, string>> = {
  en: { ...WEB_MESSAGES.en, ...MESSAGES.en },
  hi: { ...WEB_MESSAGES.hi, ...MESSAGES.hi },
  gu: { ...WEB_MESSAGES.gu, ...MESSAGES.gu },
};

export type Translate = (key: AnyMessageKey, fallback?: string) => string;

/** Build a translate function for a known locale. Safe on either side. */
export function translatorFor(locale: Locale): Translate {
  const table = TABLES[locale] ?? TABLES.en;
  return (key, fallback) => table[key] ?? fallback ?? TABLES.en[key] ?? String(key);
}

export const LOCALE_COOKIE = "bh_locale";

export const LOCALES: { code: Locale; label: string; english: string }[] = [
  { code: "en", label: "English", english: "English" },
  { code: "hi", label: "हिंदी", english: "Hindi" },
  { code: "gu", label: "ગુજરાતી", english: "Gujarati" },
];

export function isLocale(value: string | undefined): value is Locale {
  return value === "en" || value === "hi" || value === "gu";
}
