// The honest brief (pi doc §2b). A pure function: the server's get_dossier JSON in, the
// prompt text a fresh session wakes to out. It is pure so it is testable, and so the
// wiring (extension.ts) can stay a thin transport around it.
//
// Two anti-laundering rules live here, because this is the one place a re-brief could
// launder a guess into ground truth:
//   1. Every claim shows its provenance. A `derived` fact with no check_cmd renders AS
//      a hunch — never as flat truth — so generation N's guess cannot become generation
//      N+1's received truth with no one lying at any step.
//   2. The brief states its own staleness and its cuts. "Last banked 40m ago; work
//      since is unrecorded" (§6: unrecorded time is named), and every capped section
//      carries its +N more (a cut without a count is the empty-world lie in miniature).

// The get_dossier shape — the server's Server.MCP.Brief.scope/1 (one source, two protocol
// doors). Timestamps are ISO8601 strings or null; certainty is the read-time §4a rank.
export type Certainty = "stated" | "checked" | "opinion";

export interface Fact {
  id: number;
  kind: string;
  text: string;
  provenance: string;
  check_cmd: string | null;
  certainty: Certainty;
  at: string | null;
}

export interface Todo {
  id: number;
  text: string;
  done_at: string | null;
  at: string | null;
}

// One entry of the merged DONE view — a completed todo or a work_landed event, each at
// its own timestamp. Tagged by `source` so the render tells a finished step from a
// shipped outcome.
export type DoneEntry =
  | { source: "todo"; id: number; text: string; at: string | null }
  | {
      source: "event";
      id: number;
      kind: string;
      summary: string | null;
      evidence: string | null;
      at: string | null;
    };

export interface Blocker {
  id: number;
  summary: string;
  evidence: string | null;
  found_by: string | null;
  state: string;
  at: string | null;
}

export interface ChatterMessage {
  id: number;
  author: string;
  body: string;
  reply_to: number | null;
  at: string | null;
  // A consult ASK (consult_id set, not a mirror) — render it as a request for an answer.
  consult?: boolean;
}

export interface Question {
  id: number;
  text: string;
  state: string;
  resolution: string | null;
  at: string | null;
}

// A measured check — a command's real exit code, recorded as passed/failed. Not a
// self-report: the number is the truth.
export interface Check {
  passed: boolean;
  cmd: string | null;
  exit: number | null;
  tail: string | null;
  at: string | null;
}

export interface Capped<T> {
  shown: T[];
  more: number;
}

export interface Dossier {
  thread_id: number;
  north_star: string | null;
  lead: string | null;
  todos: Capped<Todo>;
  next: Todo | null;
  learnings: Capped<Fact>;
  unknowns: Capped<Question>;
  done: Capped<DoneEntry>;
  blockers: Capped<Blocker>;
  checks: Capped<Check>;
  // The thread's commits, joined by the `Tlon-Thread` trailer. Optional: a server from before
  // the join still renders.
  commits?: Capped<Commit>;
  chatter: ChatterMessage[];
}

export interface Commit {
  sha: string;
  subject: string;
  author: string;
  at: string;
}

// The operator's handle, so a stated fact reads as HIS words. The server trusts only this
// author for `stated` provenance; the render names him for the reader.
const OPERATOR = "andrew";

const CHATTER_TAIL = 5;

export function renderBrief(d: Dossier, now: Date = new Date(), model?: string): string {
  const lines: string[] = [];

  const goal = d.north_star ?? "(untitled thread)";
  lines.push(`# Brief: ${goal}`);
  lines.push(`Lead: ${d.lead ?? "unstaffed"}  ·  thread ${d.thread_id}`);
  // The session states who it is, so a model signs its commits with its OWN name and can't
  // copy a wrong one from an example. AGENTS.md "commit as who you are" reads from here.
  if (model) lines.push(`You are ${model} (pi).`);
  lines.push(staleness(d, now));

  if (d.todos.shown.length > 0) {
    lines.push("", "## Plan  (→ is NEXT, the first open step)");
    for (const t of d.todos.shown) {
      const isNext = d.next != null && t.id === d.next.id;
      lines.push(`${isNext ? "→" : " "} [ ] ${t.text}`);
    }
    pushMore(lines, d.todos.more, "todos");
  }

  if (d.learnings.shown.length > 0) {
    lines.push("", "## What's known");
    for (const f of d.learnings.shown) lines.push(renderFact(f));
    pushMore(lines, d.learnings.more, "learnings");
  }

  if (d.unknowns.shown.length > 0) {
    lines.push("", "## Unknowns  (open questions — resolve or you inherit the doubt)");
    for (const q of d.unknowns.shown) lines.push(`- ? ${q.text}`);
    pushMore(lines, d.unknowns.more, "unknowns");
  }

  if (d.blockers.shown.length > 0) {
    lines.push("", "## Blockers");
    for (const b of d.blockers.shown) lines.push(renderBlocker(b));
    pushMore(lines, d.blockers.more, "blockers");
  }

  if (d.checks.shown.length > 0) {
    lines.push("", "## Checks  (measured — ✓ passed, ✗ failed at that exit)");
    for (const c of d.checks.shown) lines.push(renderCheck(c));
    pushMore(lines, d.checks.more, "checks");
  }

  if (d.commits && d.commits.shown.length > 0) {
    lines.push("", "## Commits  (this thread's, in its repo)");
    for (const c of d.commits.shown) lines.push(`- ${c.sha} ${c.subject} — ${c.author}`);
    pushMore(lines, d.commits.more, "commits");
  }

  if (d.done.shown.length > 0) {
    lines.push("", "## Done");
    for (const e of d.done.shown) lines.push(renderDone(e));
    pushMore(lines, d.done.more, "done");
  }

  if (d.chatter.length > 0) {
    lines.push("", "## Recent chatter");
    for (const m of d.chatter.slice(-CHATTER_TAIL)) lines.push(renderChatter(m));
  }

  // A standing nudge, not state — the one behavior that keeps a thread from going cold. The
  // `coordinate-via-funes` skill teaches it, but a flash model reads a skill once and forgets;
  // the brief is injected every turn, so the reminder rides here too. Without it a rich session
  // banks nothing and its successor is briefed cold (§4c: the channel is the continuity
  // mechanism, not politeness).
  lines.push(
    "",
    "— Post as you work with `post_message` — the thread, not this session, is the memory a successor inherits; judgment you keep in your own context dies with the session.",
  );

  return lines.join("\n");
}

// A consult ask is a request for an answer, not ambient chatter — make the reply affordance
// explicit so the round-trip the bridge exists for actually fires.
function renderChatter(m: ChatterMessage): string {
  if (m.consult) return `- 📨 ${m.author} is consulting you — reply to answer: ${m.body}`;
  return `- ${m.author}: ${m.body}`;
}

// The default case FAILS CLOSED: `opinion`, or any certainty the server emits that we don't
// model, degrades to the least-authoritative rendering — never an unmarked line, which
// would launder an unknown into apparent truth.
function renderFact(f: Fact): string {
  switch (f.certainty) {
    case "stated":
      return `- [stated] ${OPERATOR}: "${f.text}"`;
    case "checked":
      return `- [checked] ${f.text}  (verify: \`${f.check_cmd}\`)`;
    default:
      return `- [hunch] ${f.text}  — unverified; re-check before you rely on it`;
  }
}

function renderBlocker(b: Blocker): string {
  const who = b.found_by ? `, found by ${b.found_by}` : "";
  const ev = b.evidence ? ` — ${b.evidence}` : "";
  return `- ${b.summary} (${b.state}${who})${ev}`;
}

function renderDone(e: DoneEntry): string {
  if (e.source === "todo") return `- [x] ${e.text}`;
  const ev = e.evidence ? ` — ${e.evidence}` : "";
  return `- ${e.summary ?? "(work landed)"}${ev}`;
}

function renderCheck(c: Check): string {
  const cmd = c.cmd ?? "(check)";
  return c.passed ? `- ✓ ${cmd}` : `- ✗ ${cmd} (exit ${c.exit ?? "?"})`;
}

function pushMore(lines: string[], more: number, noun: string): void {
  if (more > 0) lines.push(`_… and ${more} more ${noun} not shown (get_facts to read past the cap)._`);
}

// The staleness line: how old is the newest thing banked, and the honest warning that
// anything since is unrecorded. A thread with nothing banked says exactly that rather
// than rendering a confident empty world (§6: a cache that reports an empty world lies).
function staleness(d: Dossier, now: Date): string {
  const newest = newestAt(d);
  if (newest === null) {
    return "_Nothing has been banked on this thread yet — you are starting cold._";
  }
  return `_Last banked activity ${ago(newest, now)}; any work since is unrecorded._`;
}

function newestAt(d: Dossier): Date | null {
  const stamps: number[] = [];
  const collect = (at: string | null) => {
    if (!at) return;
    const t = Date.parse(at);
    if (!Number.isNaN(t)) stamps.push(t);
  };
  for (const f of d.learnings.shown) collect(f.at);
  for (const q of d.unknowns.shown) collect(q.at);
  for (const b of d.blockers.shown) collect(b.at);
  for (const c of d.checks.shown) collect(c.at);
  for (const e of d.done.shown) collect(e.at);
  for (const t of d.todos.shown) collect(t.at);
  for (const m of d.chatter) collect(m.at);
  if (stamps.length === 0) return null;
  return new Date(Math.max(...stamps));
}

// A stamp, never a clock (§4). Minutes up to 90, then hours, then days — enough for a
// reader to feel how stale the brief is without inventing precision.
function ago(then: Date, now: Date): string {
  const mins = Math.max(0, Math.round((now.getTime() - then.getTime()) / 60_000));
  if (mins < 90) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 48) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}
