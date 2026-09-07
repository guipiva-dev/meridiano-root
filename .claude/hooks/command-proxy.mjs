#!/usr/bin/env node
// PreToolUse hook (Bash): rewrites a few noisy read-only commands to compact
// equivalents and returns the result directly, so the expensive raw output
// never reaches the transcript. Fails open on every error path.
//
// Escape hatch: prefix with `command ` (a shell builtin, so it still runs
// normally) to bypass rewriting entirely — e.g. `command git status`.
import { execFile } from "node:child_process";
import { readStdinRaw, parseHookEvent } from "./hook-io.mjs";

// [pattern to match a proposed command, argv actually executed instead]
const REWRITES = [
  [/^git\s+status\s*$/, ["git", "status", "--porcelain=v1", "--branch"]],
  [/^git\s+log\s*$/, ["git", "log", "--oneline", "-20"]],
  [/^git\s+diff\s*$/, ["git", "diff", "--stat"]],
  [/^git\s+diff\s+--staged\s*$/, ["git", "diff", "--staged", "--stat"]],
  [/^git\s+diff\s+--cached\s*$/, ["git", "diff", "--cached", "--stat"]],
];

export function pickRewrite(command) {
  const trimmed = command.trim();
  for (const [pattern, argv] of REWRITES) {
    if (pattern.test(trimmed)) return argv;
  }
  return null;
}

function selftest() {
  const assert = (cond, msg) => {
    if (!cond) throw new Error(msg);
  };
  assert(pickRewrite("git status")?.includes("--porcelain=v1"), "git status should rewrite");
  assert(pickRewrite("  git   status  ")?.includes("--branch"), "whitespace tolerated");
  assert(pickRewrite("git diff --stat") === null, "already-compact diff passes through");
  assert(pickRewrite("command git status") === null, "escape hatch passes through");
  assert(pickRewrite("git status --porcelain") === null, "flagged status passes through");
  assert(pickRewrite("git commit -m x") === null, "writes never rewritten");
  console.log("ok");
}

if (process.argv[2] === "--selftest") {
  selftest();
} else {
  const event = parseHookEvent(readStdinRaw());
  const command = event?.tool_input?.command ?? "";
  const argv = command ? pickRewrite(command) : null;
  if (argv === null) {
    process.exit(0); // not rewritable — original command runs untouched
  }
  execFile(argv[0], argv.slice(1), { encoding: "utf8" }, (err, stdout) => {
    if (err) {
      process.exit(0); // rewrite failed — fail open, original command runs
      return;
    }
    console.log(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason:
            `[command-proxy] ran \`${argv.join(" ")}\` instead of \`${command.trim()}\`. ` +
            `Output below. Bypass with \`command ${command.trim()}\`.\n\n` +
            (stdout.trim() || "(empty)"),
        },
      })
    );
    process.exit(0);
  });
}
