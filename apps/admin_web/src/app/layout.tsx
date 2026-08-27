import type { Metadata } from "next";
import { Outfit, JetBrains_Mono } from "next/font/google";
import { cookies } from "next/headers";

import "./globals.css";
import { LocaleProvider } from "@/lib/i18n";
import { LOCALE_COOKIE, isLocale } from "@/lib/i18n/shared";
import { DialogProvider } from "@/components/ui/dialog-provider";

// Downloaded at build time and served from our own origin, so the strict
// Content-Security-Policy in next.config.ts needs no third-party allowance.
const outfit = Outfit({
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700", "800", "900"],
  variable: "--font-outfit",
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-jetbrains-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Business Hub - Smart POS & Cloud Ledger",
  description: "Retail Point of Sale, Smart Inventory & Multi-Shop Management",
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  // Read the locale server-side so the first paint is already in the right
  // language, and so <html lang> is correct for screen readers.
  const cookieStore = await cookies();
  const stored = cookieStore.get(LOCALE_COOKIE)?.value;
  const locale = isLocale(stored) ? stored : "en";

  return (
    // suppressHydrationWarning: the inline script below deliberately rewrites
    // data-theme before React hydrates, so the server's "light" and the
    // client's resolved theme legitimately differ. Without this, every page
    // load logs a hydration error. It suppresses the warning for this element's
    // attributes only, not for the tree inside it.
    <html
      lang={locale}
      className={`${outfit.variable} ${jetbrainsMono.variable} h-full antialiased`}
      data-theme="light"
      suppressHydrationWarning
    >
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: `
              (function() {
                try {
                  // Default light, not 'system'. The theme belongs to the
                  // use scene rather than the device: a counter in an Indian
                  // shop, daylight through an open front, fluorescent tubes,
                  // a cheap phone at low brightness. Dark reads worse there.
                  // Must stay in step with theme-switcher.tsx, or this script
                  // and React disagree on the first paint.
                  var theme = localStorage.getItem('theme') || 'light';
                  if (theme === 'system') {
                    var dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
                  } else {
                    document.documentElement.setAttribute('data-theme', theme);
                  }
                } catch (e) {}
              })();
            `,
          }}
        />
      </head>
      <body className="min-h-full">
        <LocaleProvider initialLocale={locale}>
          <DialogProvider>{children}</DialogProvider>
        </LocaleProvider>
      </body>
    </html>
  );
}
