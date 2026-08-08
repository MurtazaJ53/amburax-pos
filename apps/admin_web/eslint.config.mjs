import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
  {
    rules: {
      // Downgraded from error to warning, deliberately, after auditing all 24
      // occurrences. They are two shapes, and neither is a defect:
      //
      //   1. Feature and preference detection after mount (theme-switcher
      //      reading localStorage, camera-scanner probing BarcodeDetector).
      //      The server has no `window`, so rendering the resolved value
      //      during SSR and correcting it on the client is precisely what
      //      causes a hydration mismatch. Detect-then-setState IS the fix.
      //
      //   2. Client-side fetching: `useEffect(() => void load(), [load])`
      //      where load() opens with setLoading(true). The rule objects to
      //      that synchronous state update, and it is right that the proper
      //      answer is to fetch on the server and pass data down as props.
      //      That is an architectural change across ~20 components which also
      //      removes the client-side refresh buttons, not a lint fix.
      //
      // Kept as a warning rather than switched off: it stays visible, and if
      // a genuine setState-render-loop is ever introduced it will still be
      // reported instead of hidden by a blanket disable.
      "react-hooks/set-state-in-effect": "warn",

      // A leading underscore is the conventional way to say "this exists to
      // reach the arguments after it" — a Next.js route handler must accept
      // the request to receive `params`, even when it ignores the request.
      // Genuinely dead variables are still reported.
      "@typescript-eslint/no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
          caughtErrorsIgnorePattern: "^_",
        },
      ],
    },
  },
]);

export default eslintConfig;
