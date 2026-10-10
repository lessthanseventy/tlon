// The tlon-citizen mod's pure decisions: what the band says, which tool calls are held, how a commit
// is signed, which messages and landings are news, and how a coworker's figure becomes cells. The
// mod (../mod.ts) does the calling and drawing; everything here is data in, data out.

import type { ChatterMessage, Dossier } from "./brief.ts";

// The server's read of the office from this seat (`office_glance`).
export type Glance = {
  archetype: string | null;
  crew: { agent: string; thread_id: number; warm: boolean; thinking: boolean; doing: string | null }[];
  red: { text: string }[];
  persona: { voice: string | null; catchphrase: string | null } | null;
  line: string | null;
  landed: { thread_id: number; title: string }[];
};

/** The band's left half: the thread, its workline stage, its last check, its todos and blockers, what is red. */
export function bandParts(thread: string, d: Dossier | null, red = 0): string[] {
  const parts = [`#${thread} ${d?.goal ?? ""}`.trim()];
  if (!d) return parts;
  if (d.workline) parts.push(`${d.workline.stage}${d.workline.awaiting ? ` ⏳${d.workline.awaiting}` : ""}`);
  const check = d.checks.shown[0];
  if (check) parts.push(`${check.passed ? "✓" : "✗"} ${check.cmd ?? "check"}`);
  const todos = d.todos.shown.length + d.todos.more;
  if (todos) parts.push(`todos ${todos}${d.next ? ` → ${d.next.text}` : ""}`);
  const blockers = d.blockers.shown.length + d.blockers.more;
  if (blockers) parts.push(`blockers ${blockers}`);
  if (red) parts.push(`🔴 ${red}`);
  return parts;
}

export type Gate = { decision: "deny" | "ask"; reason: string };

/**
 * A shell command held before it runs, or null. A push goes through the server (it pushes the
 * thread's branch, force-with-lease, and the repo's pre-push hook refuses a pane's own); a branch
 * switch in the main checkout moves what the live service reads; a production write is the
 * operator's to press (`bin/server rpc`, `tlon-cli code`, a release cut) — asked, never allowed.
 */
export function gateOf(command: string, cwd: string, mainCheckout: string): Gate | null {
  const cmd = command.trim();
  if (/(^|[;&|]\s*)git\s+push\b/.test(cmd))
    return { decision: "deny", reason: "Push through the server: call push_branch (it pushes this thread's branch). A pane's own git push is refused by the repo's pre-push hook." };
  const inMain = cwd === mainCheckout || cwd.startsWith(`${mainCheckout}/`) && !cwd.includes("/.worktrees/");
  if (inMain && /(^|[;&|]\s*)git\s+(checkout|switch)\b/.test(cmd) && !/git\s+checkout\s+--\s/.test(cmd))
    return { decision: "deny", reason: `${mainCheckout} is the live service's checkout: switch branches in a worktree, never here.` };
  if (/\bbin\/server\s+rpc\b|\btlon-cli(\.sh)?\s+code\b|\brelease:cut\b/.test(cmd))
    return { decision: "ask", reason: "A production write: the operator presses Enter on it." };
  return null;
}

/** The commit trailer for the model that is actually running, on the address of its provider. */
export function attribution(model: string, onOllama: boolean): string {
  return `Co-Authored-By: ${model} <noreply@${onOllama ? "ollama.com" : "anthropic.com"}>`;
}

/** Messages newer than `seen` that @mention `me`, by anyone but `me`. */
export function mentionsOf(recent: ChatterMessage[], seen: number, me: string): ChatterMessage[] {
  const at = new RegExp(`(^|[^\\w-])@${me.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![\\w-])`, "i");
  return recent.filter((m) => m.id > seen && m.author !== me && at.test(m.body));
}

/** Done entries newer than `seen` that are a workline landing. */
export function landingsOf(d: Dossier, seen: number): number[] {
  return d.done.shown.filter((e) => e.source === "event" && e.kind === "work_landed" && e.id > seen).map((e) => e.id);
}

const VERBS = ["Catalogued", "Deciphered", "Dreamed", "Mapped", "Indexed", "Annotated", "Transcribed", "Unriddled", "Mirrored", "Labyrinthed"];

/** The word under a finished turn, the same for the same turn: a Borgesian verb. */
export function turnWord(turnId: string): string {
  let h = 2166136261;
  for (let i = 0; i < turnId.length; i++) h = Math.imul(h ^ turnId.charCodeAt(i), 16777619);
  return VERBS[(h >>> 0) % VERBS.length]!;
}

const DEFAULT_COLOR = 0x01000000;
const hex = (c: string | undefined) => (c ? Number.parseInt(c.replace("#", ""), 16) : DEFAULT_COLOR);

/**
 * A figure (rows of palette letters, `.` clear) as a Raster's cells: two pixel rows to a cell, the
 * upper as `▀`'s colour over the lower as its background, a lone lower pixel as `▄`.
 */
export function figureCells(rows: string[], paint: Record<string, string>): { columns: number; rows: number; cells: string } {
  const columns = Math.max(0, ...rows.map((r) => r.length));
  const height = Math.ceil(rows.length / 2);
  const numbers: number[] = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < columns; x++) {
      const top = rows[2 * y]?.[x] ?? ".";
      const bottom = rows[2 * y + 1]?.[x] ?? ".";
      if (top === "." && bottom === ".") numbers.push(32, DEFAULT_COLOR, DEFAULT_COLOR);
      else if (top === ".") numbers.push(0x2584, hex(paint[bottom]), DEFAULT_COLOR);
      else numbers.push(0x2580, hex(paint[top]), bottom === "." ? DEFAULT_COLOR : hex(paint[bottom]));
    }
  }
  const bytes = new Uint8Array(Uint32Array.from(numbers).buffer);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return { columns, rows: height, cells: btoa(binary) };
}
