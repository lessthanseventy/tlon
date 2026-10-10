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

// Each simple command in a shell line, as words: split at ; & | ( ) ` $( and newlines, single
// quotes kept as one word, double quotes dropped (a $( inside them still runs).
function commands(line: string): string[][] {
  const out: string[][] = [[]];
  let word: string | null = null;
  const end = () => {
    if (word !== null) out[out.length - 1]!.push(word);
    word = null;
  };
  for (let i = 0; i < line.length; i++) {
    const c = line[i]!;
    if (c === "'") {
      const close = line.indexOf("'", i + 1);
      const quoted = close < 0 ? line.slice(i + 1) : line.slice(i + 1, close);
      word = (word ?? "") + quoted;
      i = close < 0 ? line.length : close;
    } else if (c === "\\") {
      if (line[i + 1] !== "\n") word = (word ?? "") + (line[i + 1] ?? "");
      i++;
    } else if (c === '"') {
      word ??= "";
    } else if (/\s/.test(c) && c !== "\n") {
      end();
    } else if (";&|()`\n".includes(c) || (c === "$" && line[i + 1] === "(")) {
      end();
      out.push([]);
      if (c === "$") i++;
    } else {
      word = (word ?? "") + c;
    }
  }
  end();
  return out.filter((words) => words.length);
}

// Words that run the command after them: `env A=1 git push`, `command git push`, `{ git push; }`.
const PREFIXES = new Set(["env", "command", "exec", "nohup", "time", "sudo", "{", "!", "then", "do", "else"]);
// git's global options that take the next word as their value.
const GIT_VALUE_OPTS = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"]);

function resolvePath(base: string, path: string, home: string): string {
  const p = path === "~" || path.startsWith("~/") ? (home ? home + path.slice(1) : path) : path;
  const parts: string[] = [];
  for (const seg of (p.startsWith("/") ? p : `${base}/${p}`).split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") parts.pop();
    else parts.push(seg);
  }
  return `/${parts.join("/")}`;
}

/** A git invocation in `words` — its subcommand, the rest, and where it runs — or null. */
function gitOf(words: string[], cwd: string, home: string): { sub: string; args: string[]; dir: string; gitDir: string | null } | null {
  let i = 0;
  let afterEnv = false;
  while (i < words.length) {
    const w = words[i]!;
    if (afterEnv && ["-u", "-C", "-S", "--unset", "--chdir", "--split-string"].includes(w)) i += 2;
    else if (PREFIXES.has(w) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(w) || (afterEnv && w.startsWith("-"))) i++;
    else break;
    afterEnv ||= w === "env";
  }
  const bin = words[i];
  if (bin !== "git" && !bin?.endsWith("/git")) return null;
  i++;
  let dir = cwd;
  let gitDir: string | null = null;
  while (i < words.length && words[i]!.startsWith("-")) {
    const opt = words[i]!;
    const [name, inline] = opt.startsWith("--") && opt.includes("=") ? [opt.slice(0, opt.indexOf("=")), opt.slice(opt.indexOf("=") + 1)] : [opt, null];
    const value = inline ?? (GIT_VALUE_OPTS.has(name) ? words[++i] ?? "" : null);
    if (name === "-C" && value !== null) dir = resolvePath(dir, value, home);
    if (name === "--git-dir" && value !== null) gitDir = resolvePath(dir, value, home);
    if (name === "--work-tree" && value !== null) dir = resolvePath(dir, value, home);
    i++;
  }
  return { sub: words[i] ?? "", args: words.slice(i + 1), dir, gitDir };
}

/**
 * A shell command held before it runs, or null. A push goes through the server (it pushes the
 * thread's branch, force-with-lease, and the repo's pre-push hook refuses a pane's own); a branch
 * switch in the main checkout moves what the live service reads; a production write is the
 * operator's to press (`bin/server rpc`, `tlon-cli code`, a release cut) — asked, never allowed.
 * git is found after `env`, an assignment, `(`, `;`, `&&`, `|` or `$(`, past its global options
 * (`-C <dir>` sets where it runs). A best effort: the pre-push hook is the push's real fence.
 */
export function gateOf(command: string, cwd: string, mainCheckout: string, home = ""): Gate | null {
  const cmd = command.trim();
  const inMain = (p: string) => (p === mainCheckout || p.startsWith(`${mainCheckout}/`)) && !p.includes("/.worktrees/") && !p.includes("/.git/worktrees/");
  for (const words of commands(cmd)) {
    const git = gitOf(words, cwd, home);
    if (!git) continue;
    if (git.sub === "push")
      return { decision: "deny", reason: "Push through the server: call push_branch (it pushes this thread's branch). A pane's own git push is refused by the repo's pre-push hook." };
    if ((git.sub === "checkout" || git.sub === "switch") && git.args[0] !== "--" && (inMain(git.dir) || (git.gitDir !== null && inMain(git.gitDir))))
      return { decision: "deny", reason: `${mainCheckout} is the live service's checkout: switch branches in a worktree, never here.` };
  }
  if (/\bbin\/server\s+rpc\b|\btlon-cli(\.sh)?\s+code\b|\brelease:cut\b/.test(cmd))
    return { decision: "ask", reason: "A production write: the operator presses Enter on it." };
  return null;
}

/** The operator API at the server's origin (TLON_MCP_URL ends in /mcp); the default release's without one. */
export function operatorApi(mcpUrl: string | undefined): string {
  const origin = mcpUrl?.match(/^https?:\/\/[^/]+/)?.[0];
  return `${origin ?? "http://127.0.0.1:4040"}/api`;
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
