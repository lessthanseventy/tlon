// The heartbeat's pure core (thread #3, 2026-08-27): "here's what's happening" check-ins
// during a long single turn, instead of silence until Stop. Split the same way capture.ts is —
// this module is the mechanical, LLM-free signal (which tool, what target, how long); the sidecar
// phrasing call (llm.ts's completeText, same cheap out-of-band model capture.ts already uses) turns
// it into one personable line. `fallbackLine` is what ships verbatim if that call fails/unreachable
// — a heartbeat is never silently dropped over an LLM hiccup, unlike capture's best-effort nicety.

import { DEFAULT_CAPTURE_MODEL, type Entry } from "./capture.ts";

export type { Entry };

export interface ToolActivity {
  name: string;
  detail?: string;
}

// The one input field worth surfacing — a command or a path, never the full arg blob (could be
// long, noisy, or a secret-shaped string capture.ts's redaction never sees here).
const DETAIL_FIELDS = ["command", "file_path", "path", "pattern", "query", "url"];
const MAX_DETAIL_CHARS = 80;

function truncate(s: string, max: number): string {
  return s.length > max ? s.slice(0, max - 1) + "…" : s;
}

export function activityFrom(name: string, input: unknown): ToolActivity {
  if (!input || typeof input !== "object") return { name };
  const record = input as Record<string, unknown>;
  for (const key of DETAIL_FIELDS) {
    const v = record[key];
    if (typeof v === "string" && v.trim()) return { name, detail: truncate(v.trim(), MAX_DETAIL_CHARS) };
  }
  return { name };
}

// The most recent tool-call block across entries, scanning from the end — the tool the agent is
// (or just was) mid-call on. `undefined` before any tool has run yet. pi stores its OWN message
// shape (pi-ai's `ToolCall {type: "toolCall", name, arguments}`), NOT the Anthropic wire format
// (`tool_use`/`input`) — a review caught the detector matching only the latter, which made it
// dead code against a live session. Both shapes match here so a fabricated Anthropic-style test
// entry and a real pi entry read the same.
export function lastToolActivity(entries: Entry[]): ToolActivity | undefined {
  for (let i = entries.length - 1; i >= 0; i--) {
    const content = entries[i]?.message?.content;
    if (!Array.isArray(content)) continue;
    for (let j = content.length - 1; j >= 0; j--) {
      const block = content[j] as { type?: string; name?: string; input?: unknown; arguments?: unknown } | null;
      if (!block || typeof block.name !== "string") continue;
      if (block.type === "toolCall") return activityFrom(block.name, block.arguments);
      if (block.type === "tool_use") return activityFrom(block.name, block.input);
    }
  }
  return undefined;
}

// A ticking elapsed-time label — mirrors the console's Console.Text.duration/1 exactly (same reasoning:
// sub-minute precision so the number visibly moves, unlike a coarser "N minutes ago" bucket).
export function formatDuration(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  if (s < 60) return `${s}s`;
  if (s < 3_600) return `${Math.floor(s / 60)}m${s % 60}s`;
  return `${Math.floor(s / 3_600)}h${Math.floor((s % 3_600) / 60)}m`;
}

// The never-silent mechanical line — used verbatim when the sidecar phrasing call fails.
export function fallbackLine(activity: ToolActivity | undefined, elapsedSeconds: number): string {
  const elapsed = formatDuration(elapsedSeconds);
  if (!activity) return `still on it (${elapsed})`;
  return activity.detail
    ? `still on it (${elapsed}) — ${activity.name}: ${activity.detail}`
    : `still on it (${elapsed}) — ${activity.name}`;
}

// The sidecar phrasing prompt: one short, personable check-in — a quick human aside, not a status
// report. Deliberately constrained (length, plain text, no questions) so a cheap flash-tier
// completion can't wander into a mini-essay or invite a reply mid-tool-call.
export function buildHeartbeatPrompt(activity: ToolActivity | undefined, elapsedSeconds: number): string {
  const elapsed = formatDuration(elapsedSeconds);
  const doing = activity ? (activity.detail ? `${activity.name} (${activity.detail})` : activity.name) : "getting started";

  return [
    "You are a coworker who's been heads-down on a task for a bit and wants to give a quick,",
    "casual one-line check-in so the person waiting on you doesn't think you've stalled out.",
    "",
    `You've been at it for ${elapsed}. Right now you're running: ${doing}.`,
    "",
    "Write ONE short, natural sentence (under 20 words) checking in. Plain text, no markdown, no",
    "quotes, no questions, no emoji. Just a quick human aside, not a status report.",
  ].join("\n");
}

// The sidecar call, `complete` injected (llm.ts's completeText in production, a fake in tests —
// same seam mcp.ts's tests use for fetch). Any hiccup — unreachable, no key, empty content, a
// multi-line ramble past the prompt's constraint — degrades to `fallbackLine`, never silence: the
// heartbeat message itself is the deliverable here, unlike capture's best-effort nicety.
export async function phraseHeartbeat(
  activity: ToolActivity | undefined,
  elapsedSeconds: number,
  complete: (model: string, prompt: string) => Promise<string>,
): Promise<string> {
  try {
    const text = await complete(DEFAULT_CAPTURE_MODEL, buildHeartbeatPrompt(activity, elapsedSeconds));
    const line = text.trim().split("\n")[0]?.trim();
    return line || fallbackLine(activity, elapsedSeconds);
  } catch {
    return fallbackLine(activity, elapsedSeconds);
  }
}

// Claude Code's PostToolUse fires a fresh process every tool call — no long-lived closure like
// pi's extension.ts, so the cadence gate lives in a state file instead of an interval timer.
// `anchor` collapses two questions into one number: "how long since the turn started" (for a
// turn's very first heartbeat) and "how long since the last post" (for every one after) — both
// answered by `now - anchor >= minIntervalMs`.
export interface HeartbeatState {
  turnStartedAt: number;
  lastPostAt: number;
}

// A gap past `turnResetMs` since the last post reads as a NEW turn (or a long-idle session),
// not a continuation — otherwise a session left open overnight would report elapsed time in
// hours on its very next heartbeat.
export function nextHeartbeatState(
  prior: HeartbeatState | null,
  now: number,
  turnResetMs: number,
): { turnStartedAt: number; anchor: number } {
  const freshTurn = !prior || now - prior.lastPostAt > turnResetMs;
  return {
    turnStartedAt: freshTurn ? now : prior.turnStartedAt,
    anchor: freshTurn ? now : prior.lastPostAt,
  };
}

export function heartbeatDue(anchor: number, now: number, minIntervalMs: number): boolean {
  return now - anchor >= minIntervalMs;
}

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
