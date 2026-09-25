// Auto-track's pure core: did a turn land a git commit? (The heartbeat that shared this file was
// removed 2026-09-25 — progress lives in the coworker's terminal and presence, not the thread.)

import type { Entry } from "./capture.ts";

export type { Entry };

// --- auto-track (reshape slice B): the ticket condenses out of the work -------------------

// A real `git … commit` invocation at the start of a command (or after && / ; / || / newline),
// tolerating git's own pre-subcommand flags (-C path, --no-pager, …). `commit` must be a whole
// token (lookahead, not \b) so `git -c commit.gpgsign=false push` can't sneak through on the dot.
// A "commit" that is merely a word in some other command (grep, log) never matches. Deliberately
// not quote-aware — an echoed "git commit" is vanishingly rare, and the promote is idempotent.
const COMMIT_RE = /(^|&&|\|\||;|\n)\s*git\s+(?:-{1,2}\S+(?:\s+\S+)?\s+)*commit(?=\s|$)/;

export function isCommitCommand(command: string): boolean {
  return COMMIT_RE.test(command);
}

// Did this session land a commit? pi's NATIVE shapes (pi-ai types.d.ts, verified — not the
// Anthropic wire format a first cut matched, which made this dead code): an assistant message
// carries `{type: "toolCall", id, name, arguments}` blocks, and the result is a WHOLE message
// `{role: "toolResult", toolCallId, isError}`. A bash toolCall whose arguments.command is a
// commit invocation, answered by a non-error toolResult, flips this true — mechanically, no
// LLM — and the extension promotes the thread via track_thread. INTENTIONALLY pi-native only
// (unlike lastToolActivity's dual-shape): only pi's extension calls this, and accepting the
// Anthropic shape too would let a wrongly-fabricated test go green again.
export function sawSuccessfulCommit(entries: Entry[]): boolean {
  const commitIds = new Set<string>();
  for (const e of entries) {
    const message = e.message as
      | { role?: string; content?: unknown; toolCallId?: string; isError?: boolean }
      | undefined;
    if (!message) continue;

    if (message.role === "toolResult") {
      if (message.isError !== true && typeof message.toolCallId === "string" && commitIds.has(message.toolCallId)) {
        return true;
      }
      continue;
    }

    const content = message.content;
    if (!Array.isArray(content)) continue;
    for (const raw of content) {
      const b = raw as { type?: string; id?: string; name?: string; arguments?: unknown } | null;
      if (!b || b.type !== "toolCall" || typeof b.name !== "string" || b.name.toLowerCase() !== "bash") continue;
      const cmd = (b.arguments as Record<string, unknown> | null)?.["command"];
      if (typeof cmd === "string" && isCommitCommand(cmd) && typeof b.id === "string") commitIds.add(b.id);
    }
  }
  return false;
}
