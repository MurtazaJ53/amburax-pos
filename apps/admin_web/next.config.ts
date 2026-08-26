import path from "node:path";

import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Emit .next/standalone: a self-contained server with only the modules
  // actually used. The Dockerfile copies it, and it keeps the runtime
  // image small enough to sit on a shared 2 GB droplet.
  output: "standalone",
  // Hosts the dev server will serve /_next/* to.
  //
  // Next blocks cross-origin access to dev resources by default, which is
  // right - but it means that over a tunnel the page loads while its
  // JavaScript does not, so every form silently does nothing when clicked.
  // Nothing in the browser explains it; the reason appears only in the dev
  // server log.
  //
  // Development only. A production build serves these to anyone and ignores
  // this list entirely, which is the better way to show somebody the app.
  allowedDevOrigins: [
    "*.ngrok-free.dev",
    "*.ngrok-free.app",
    "*.ngrok.io",
    "*.trycloudflare.com",
  ],
  turbopack: {
    root: path.resolve(__dirname),
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains; preload" },
          { key: "Content-Security-Policy", value: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;" },
        ],
      },
    ];
  },
};

export default nextConfig;
