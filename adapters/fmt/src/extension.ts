// adapters/fmt — the agent's format-on-save. Watches `edit`/`write` tool results and, when the
// touched file is `.ex`/`.exs` inside a mix project, runs `mix format <file>` so
// `mix format --check-formatted` can never fail for an agent-written file. See
// modules/adapters/fmt/AGENTS.md.
//
// Best-effort and invisible: a format failure never fails the edit. One race: if mix format
// reformats a file the model just wrote, its next edit's oldText (pre-format memory) can
// mismatch disk — self-recovers on the model's next re-read.
//
// Only Elixir is formatted — it's the only language whose gate runs a formatter check
// (server:check / console:check). TypeScript's gate has no formatter, so nothing to do here.

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI, ToolResultEvent, ToolResultPatch } from "./pi.ts";

export default function fmt(pi: ExtensionAPI): void {
  pi.on("tool_result", (event) => mixFormatTouched(event));
}

// The pure decision — which files to format and where — extracted so it's testable without
// spawning mix. Returns the {root, rel} to format, or null when the tool isn't edit/write,
// the path isn't .ex/.exs, or no mix.exs is found above the file.
export function formatTarget(event: ToolResultEvent): { root: string; rel: string } | null {
  if (event.toolName !== "edit" && event.toolName !== "write") return null;
  const file = (event.input as { path?: string } | null | undefined)?.path;
  if (!file || !/\.(ex|exs)$/i.test(file)) return null;
  const root = findMixRoot(file);
  if (!root) return null;
  return { root, rel: path.relative(root, file) };
}

async function mixFormatTouched(event: ToolResultEvent): Promise<ToolResultPatch | undefined> {
  const target = formatTarget(event);
  if (!target) return;
  await runQuiet("mix", ["format", target.rel], target.root);
  // Never modify the result — the edit stands; formatting is a silent side-effect.
  return undefined;
}

// Walk up from the file to the nearest mix.exs (capped — a project root is never deep).
export function findMixRoot(file: string): string | null {
  let dir = path.dirname(file);
  for (let i = 0; i < 12; i++) {
    if (fs.existsSync(path.join(dir, "mix.exs"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

// Fire-and-forget shell — resolve on close/error so the hook never hangs. stdio ignored:
// mix format is quiet on success and its output would be noise in the agent's view.
function runQuiet(cmd: string, args: string[], cwd: string): Promise<void> {
  return new Promise((resolve) => {
    const proc = spawn(cmd, args, { cwd, stdio: "ignore" });
    proc.on("close", () => resolve());
    proc.on("error", () => resolve());
  });
}