// The office's data views: the snapshot narrowed to a workspace, who is on the crew and what they
// are doing, the whiteboard's columns. Every room and every card reads these, so they cannot
// disagree.
import type { Agents, Seat, Thread, Ticket } from "./types"

/** what a click on a room means: a thread to show, a ticket to hand out, a person, or a tool */
export type Act =
  | { kind: "thread"; tid: number }
  | { kind: "ticket"; id: number }
  | { kind: "person"; agentId: number | null; name: string; tid: number | null }
  | { kind: "hire" }
  | { kind: "pen" }
  | { kind: "column"; col: number }
  | { kind: "notes" }
  | { kind: "boss" }
  | { kind: "crew" }
  | { kind: "cat" }
  | { kind: "calendar" }
  | { kind: "tv" }
  | { kind: "arcade" }
  | { kind: "weather" }
  | { kind: "ideas" }
  | { kind: "terminal"; tid: number }
  | { kind: "archive" }
  | { kind: "dog" }
  | { kind: "tray" }
  | { kind: "beacon" }
  | { kind: "rack" }

export const needsYou = (t?: Thread) => !!t && (!!t.awaiting || !!t.prompt)
/** a meta coworker — the one who routes the work and never works a thread */
export const isManager = (a: Agents, r: { archetype?: string | null }) => !!a.archetypes.find((x) => x.name === r.archetype)?.meta

/** the workspace a surface opens on when it has none chosen: the one that needs you most */
export function busiest(a: Agents): number | null {
  const by = (pred: (ws: number) => boolean) => a.workspaces.find((w) => pred(w.id))?.id
  return by((ws) => a.threads.some((t) => t.workspace_id === ws && needsYou(t))) ?? by((ws) => a.roster.some((r) => r.workspace_id === ws))
    ?? by((ws) => a.bench.some((c) => c.workspace_id === ws)) ?? a.workspaces[0]?.id ?? null
}

/** the snapshot narrowed to one workspace — what an office draws and acts on */
export function viewOf(a: Agents, ws: number | null): Agents {
  const threads = a.threads.filter((t) => t.workspace_id === ws)
  const bench = a.bench.filter((c) => c.workspace_id === ws)
  const sessions = a.roster.filter((r) => r.workspace_id === ws)
  // a desk for every staffed open thread, not only the ones with a session: a Claude Code worker
  // registers none until it calls register. Without one, a thread's own running window means
  // working — but not the lobby's, whose lead runs there all day
  const unregistered = threads
    .filter((t) => t.lead && !sessions.some((r) => r.thread_id === t.id))
    .map((t) => {
      const c = bench.find((b) => b.name === t.lead)
      return { agent: t.lead!, thread_id: t.id, title: t.title, warm: !!t.live && !t.standing, thinking: !!t.thinking?.includes(t.lead!), archetype: c?.archetype ?? null, lead: c?.lead ?? false, workspace_id: ws }
    })
  return {
    ...a, threads, roster: [...sessions, ...unregistered], bench,
    tickets: a.tickets.filter((t) => t.workspace_id === ws), projects: a.projects.filter((p) => p.workspace_id === ws),
    notes: a.notes.filter((n) => n.workspace_id === ws || n.workspace_id === null), visits: a.visits.filter((v) => v.workspace_id === ws),
    awaiting: threads.filter(needsYou).length,
    triage: ws === null ? {} : { [ws]: a.triage[String(ws)] ?? 0 },
    calendar: ws === null ? {} : { [ws]: a.calendar[String(ws)] ?? [] },
  }
}

/**
 * The office's people, once each: the bench, then anyone on a thread who is not on it. Each is
 * shown on the thread that needs you if one does, else their first — and is warm, or mid-turn, if
 * any of theirs is (doing what one of those turns is doing).
 */
export function peopleOf(a: Agents): Seat[] {
  const byName = new Map<string, Seat>()
  for (const c of a.bench) byName.set(c.name, { agent: c.name, thread_id: -c.agent_id, title: "", warm: false, archetype: c.archetype, lead: c.lead })
  for (const r of a.roster) {
    const p = byName.get(r.agent) ?? { ...r, warm: false, thread_id: 0 }
    if (p.thread_id <= 0 || needsYou(a.threads.find((t) => t.id === r.thread_id))) { p.thread_id = r.thread_id; p.title = r.title }
    p.warm = p.warm || r.warm
    p.thinking = !!(p.thinking || r.thinking)
    if (r.thinking && r.doing) p.doing = r.doing
    byName.set(r.agent, p)
  }
  return [...byName.values()]
}

export type CrewStatus = "working" | "waiting" | "idle"
/** one row of the crew: who, in what role, doing what — a crew board's light and a crew card's row */
export type Crew = { name: string; archetype: string | null; manager: boolean; lead: boolean; status: CrewStatus; thread: number | null; title: string }
/** the office's crew, in bench order */
export function crewOf(a: Agents): Crew[] {
  return peopleOf(a).map((p) => {
    const t = p.thread_id > 0 ? a.threads.find((x) => x.id === p.thread_id) : undefined
    const status: CrewStatus = needsYou(t) ? "waiting" : p.thinking ? "working" : "idle"
    return { name: p.agent, archetype: p.archetype ?? null, manager: isManager(a, p), lead: !!p.lead, status, thread: p.thread_id > 0 ? p.thread_id : null, title: p.title }
  })
}

/** a workline's stages, in order */
export const STAGES = ["intent", "spec", "plan", "build", "verify", "review"]
// TICKETS (unstarted) and DOING (a started plain thread — no workline stage) before the stages
const STAGE_COL: Record<string, number> = { intent: 2, spec: 2, plan: 3, build: 4, verify: 4, review: 5 }
export const COLS = ["TICKETS", "DOING", "SPEC", "PLAN", "BUILD", "REVIEW"]
/** one note on the whiteboard: what a click on it does, and what its sticky and its list row say */
export type BoardItem = { act: Act; title: string; who: string | null; stage: string; asks: boolean; archetype: string | null; high: boolean; routed?: boolean }
/** the whiteboard's columns — a board draws them as stickies, a column card as rows */
export function boardColumns(a: Agents): { name: string; items: BoardItem[] }[] {
  const cols: BoardItem[][] = COLS.map(() => [])
  for (const tk of a.tickets as Ticket[])
    cols[0]!.push({ act: { kind: "ticket", id: tk.id }, title: tk.title, who: null, stage: tk.routed ? "with the manager" : "ticket", asks: false, archetype: null, high: tk.priority === "high", routed: !!tk.routed })
  for (const th of a.threads) {
    const c = th.stage ? STAGE_COL[th.stage] : th.lead && !th.standing ? 1 : undefined
    if (c === undefined) continue
    const r = a.roster.find((x) => x.thread_id === th.id)
    cols[c]!.push({ act: { kind: "thread", tid: th.id }, title: th.title, who: r?.agent ?? th.lead ?? null, stage: th.stage ?? "doing", asks: needsYou(th), archetype: r?.archetype ?? null, high: false })
  }
  return COLS.map((name, i) => ({ name, items: cols[i]! }))
}

/** a person's one-line tip: who, in what role, on what, asking what, and where they are */
export function tipOf(r: Seat, th: Thread | undefined, where: string) {
  const ask = th?.prompt ? `\nasks: ${th.prompt.summary}` : th?.awaiting ? `\nawaits ${th.awaiting}` : ""
  const on = r.thread_id > 0 ? ` · #${r.thread_id} ${th?.title ?? r.title}` : " · on the bench"
  return `${r.agent}${r.archetype ? ` (${r.archetype}${r.lead ? ", lead" : ""})` : ""}${on}${ask}\n${where}`
}
