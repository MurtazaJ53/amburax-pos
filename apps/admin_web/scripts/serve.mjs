// Serve the production build.
//
// `next start` cannot do it. This app builds with output: "standalone" so the
// Docker image stays small enough for a 2 GB droplet, and standalone emits its
// own server instead - `next start` refuses outright, which is how this was
// found: the server printed "Ready in 285ms" and then exited with code 1.
//
// Standalone has one sharp edge. Next copies the server and its modules into
// .next/standalone, but NOT the static assets, so running the server directly
// gives a page with no CSS and no JavaScript - it renders, and nothing on it
// works. Nothing says why. So this copies them first, every time, because a
// stale copy from an earlier build fails the same silent way.
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
