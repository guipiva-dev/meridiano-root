#!/usr/bin/env node
// SessionStart hook: prints a one-line project banner into the session context.
// Fails open — any error just means no banner.
import { execFileSync } from "node:child_process";
import { readStdinRaw, parseHookEvent } from "./hook-io.mjs";

parseHookEvent(readStdinRaw()); // drain stdin; the payload isn't needed here

let branch = "no git";
try {
  branch = execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
} catch {
  // not a repo, or git missing — keep the default
}

console.log(`Meridiano | branch: ${branch} | command-proxy active (bypass: \`command <cmd>\`)`);
process.exit(0);
