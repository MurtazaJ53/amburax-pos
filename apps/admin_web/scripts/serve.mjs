// Serve the production build.
//
// `next start` cannot do it. This app builds with output: "standalone" so the
// Docker image stays small enough for a 2 GB droplet, and standalone emits its
// own server instead - `next start` refuses outright, which is how this was
// found: the server printed "Ready in 285ms" and then exited with code 1.
//
// Standalone has two sharp edges, and they fail the same way. Next copies the
// server and its modules into .next/standalone, but NOT the static assets and
// NOT the env file - and the standalone server chdirs into that folder, so a
// .env.local sitting in the project root is simply not there any more.
//
// Neither failure announces itself. Without the assets the page renders with
// no CSS and no JavaScript. Without the env, BUSINESS_HUB_API_BASE_URL is
// undefined and every API call fails while the pages still render - a site
// that looks deployed and answers 503 to everything it is asked.
//
// So both are copied here, every time, because a stale copy from an earlier
// build fails identically silently, and a copy made by hand is wiped by the
// next build.
import { cp, access } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const standalone = path.join(root, ".next", "standalone");

const exists = async (target) =>
  await access(target).then(() => true, () => false);

if (!(await exists(path.join(standalone, "server.js")))) {
  console.error(
    "No production build found. Run `pnpm build` first.\n" +
      "If a dev server is running in this folder, stop it before building: " +
      "both write .next and the build fails on a half-written types file.",
  );
  process.exit(1);
}

// recursive + force, so a rebuild overwrites rather than merging two builds.
await cp(path.join(root, ".next", "static"), path.join(standalone, ".next", "static"), {
  recursive: true,
  force: true,
});
if (await exists(path.join(root, "public"))) {
  await cp(path.join(root, "public"), path.join(standalone, "public"), {
    recursive: true,
    force: true,
  });
}

// Env files, in the order Next itself loads them - later wins, so .env.local
// is copied last. Only what exists; none of these are required to be present.
let carriedEnv = false;
for (const name of [".env", ".env.production", ".env.local"]) {
  const source = path.join(root, name);
  if (await exists(source)) {
    await cp(source, path.join(standalone, name), { force: true });
    carriedEnv = true;
  }
}

// Said out loud rather than left to be discovered through a 503. If the API
// base URL reaches the server some other way - a real deployment sets it in
// the environment - this is noise; if it does not, this is the only warning
// there will be.
if (!carriedEnv && !process.env.BUSINESS_HUB_API_BASE_URL) {
  console.warn(
    "No env file found and BUSINESS_HUB_API_BASE_URL is not set.\n" +
      "Pages will render and every API call will fail with 503.",
  );
}

// Bound to every interface, not just localhost: this is the build a tunnel or
// another device on the network is meant to reach.
const child = spawn(process.execPath, [path.join(standalone, "server.js")], {
  stdio: "inherit",
  env: {
    ...process.env,
    PORT: process.env.PORT ?? "3000",
    HOSTNAME: process.env.HOSTNAME ?? "0.0.0.0",
  },
});
child.on("exit", (code) => process.exit(code ?? 0));
