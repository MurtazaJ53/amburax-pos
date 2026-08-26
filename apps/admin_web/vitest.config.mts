import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  test: {
    // node by default: the great majority of these tests are pure functions
    // and giving every file a DOM would cost seconds across the suite.
    // Component tests opt in with a `@vitest-environment happy-dom` docblock.
    environment: "node",
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
  },
});
