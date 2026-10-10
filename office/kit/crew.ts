// The office's data views: the snapshot narrowed to a workspace, who is on the crew and what they
// are doing, the whiteboard's columns. Every room and every card reads these, so they cannot
// disagree.
import type { Agents, Seat, Thread, Ticket } from "./types"

/** what a click on a room means: a thread to show, a ticket to hand out, a person, or a tool */
export type Act =
  | { kind: "thread"; tid: number }
  | { kind: "ticket"; id: number }
  | { kind: "epic"; id: number }
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
  | { kind: "stereo" }
  | { kind: "poster" }
  | { kind: "arcade" }
  | { kind: "weather" }
  | { kind: "ideas" }
  | { kind: "terminal"; tid: number }
  | { kind: "archive" }
  | { kind: "dog" }
  | { kind: "tray" }
  | { kind: "needs" }
  | { kind: "beacon" }
  | { kind: "rack" }

export const needsYou = (t?: Thread) => !!t && (!!t.awaiting || !!t.prompt)
/** `who` brings `t` to you: it needs you, and they lead it — everyone else on it gets on */
export const asksYou = (who: string, t?: Thread) => needsYou(t) && (!t!.lead || t!.lead === who)
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
  const sessions = a.roster.filter((r) => r.workspace_id === ws && r.agent !== "uqbar")
  const uqbar = a.roster.find((r) => r.agent === "uqbar") ?? null
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
    ...a, threads, roster: [...sessions, ...unregistered], bench, uqbar,
    tickets: a.tickets.filter((t) => t.workspace_id === ws), projects: a.projects.filter((p) => p.workspace_id === ws),
    notes: a.notes.filter((n) => n.workspace_id === ws || n.workspace_id === null), visits: a.visits.filter((v) => v.workspace_id === ws),
    awaiting: threads.filter(needsYou).length,
    triage: ws === null ? {} : { [ws]: a.triage[String(ws)] ?? 0 },
    calendar: ws === null ? {} : { [ws]: a.calendar[String(ws)] ?? [] },
  }
}

/**
 * The office's people, once each: the bench, then anyone on a thread who is not on it. Each is
 * shown on the thread they bring to you if one waits on you, else their first — and is warm, or mid-turn, if
 * any of theirs is (doing what one of those turns is doing).
 */
export function peopleOf(a: Agents): Seat[] {
  const byName = new Map<string, Seat>()
  for (const c of a.bench) byName.set(c.name, { agent: c.name, thread_id: -c.agent_id, title: "", warm: false, archetype: c.archetype, lead: c.lead })
  for (const r of a.roster) {
    const p = byName.get(r.agent) ?? { ...r, warm: false, thread_id: 0 }
    if (p.thread_id <= 0 || asksYou(r.agent, a.threads.find((t) => t.id === r.thread_id))) { p.thread_id = r.thread_id; p.title = r.title }
    p.warm = p.warm || r.warm
    if (r.warmth !== undefined) p.warmth = Math.max(p.warmth ?? 0, r.warmth)
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
    const status: CrewStatus = asksYou(p.agent, t) ? "waiting" : p.thinking ? "working" : "idle"
    return { name: p.agent, archetype: p.archetype ?? null, manager: isManager(a, p), lead: !!p.lead, status, thread: p.thread_id > 0 ? p.thread_id : null, title: p.title }
  })
}

/** a workline's stages, in order */
export const STAGES = ["intent", "spec", "plan", "build", "verify", "review"]
// TICKETS (unstarted) and DOING (a plain thread — no workline stage — someone is at a desk on) before the stages
const STAGE_COL: Record<string, number> = { intent: 2, spec: 2, plan: 3, build: 4, verify: 4, review: 5 }
export const COLS = ["TICKETS", "DOING", "SPEC", "PLAN", "BUILD", "REVIEW"]
/** one note on the whiteboard: what a click on it does, and what its sticky and its list row say */
export type BoardItem = { act: Act; title: string; who: string | null; stage: string; asks: boolean; archetype: string | null; high: boolean; routed?: boolean; state?: CardState | null }
/** where a workline stands, from the server's `seat`: its lead at a desk (▶), parked for a seat under the leaf cap (⏸), nobody at a desk (○), or waiting on you (⚑) */
export type CardState = { kind: "running" | "parked" | "idle" | "needs" | "checking" | "merging"; why: string; atCap?: boolean }
/** what a board knows beyond the snapshot: the leaf cap (`max_leaves` from the settings) and the threads on the needs list */
export type BoardCtx = { maxLeaves?: number | null; needs?: number[]; checking?: number | null; merging?: { thread_id: number; state: "landing" | "queued" }[] }
export const STATE_GLYPH: Record<CardState["kind"], string> = { running: "▶", parked: "⏸", idle: "○", needs: "⚑", checking: "✓", merging: "⤵" }

/** a thread's card state, or null when nobody leads it */
export function cardState(a: Agents, th: Thread, ctx: BoardCtx = {}): CardState | null {
  // the machine's queues first: its full check running on this workline, or the merge queue landing it
  const merge = ctx.merging?.find((m) => m.thread_id === th.id)
  if (merge) return { kind: "merging", why: merge.state === "landing" ? "landing now: gated on main" : "in the merge queue" }
  if (ctx.checking === th.id) return { kind: "checking", why: "its full check is running" }
  if (needsYou(th) || ctx.needs?.includes(th.id)) return { kind: "needs", why: th.prompt ? `asks: ${th.prompt.summary}` : th.awaiting ? `awaits ${th.awaiting}` : "waiting on you" }
  if (!th.lead) return null
  if (th.seat === "desk") return { kind: "running", why: th.thinking?.includes(th.lead) ? `${th.lead} is on it` : `${th.lead} is at a desk` }
  if (th.seat === "parked") {
    // the cap counts a workspace's seated leaf windows: its lobby and its standing duties take none
    const seated = a.threads.filter((t) => t.workspace_id === th.workspace_id && t.live && !t.standing && !t.duty).length
    return { kind: "parked", why: ctx.maxLeaves != null ? `waiting for a seat (${seated}/${ctx.maxLeaves})` : "waiting for a seat", atCap: true }
  }
  return { kind: "idle", why: `${th.lead} is not at a desk` }
}

/** an epic's unstarted children, in the snapshot's order */
export const epicChildren = (a: Agents, id: number): Ticket[] => (a.tickets as Ticket[]).filter((t) => t.epic_id === id)

/** the whiteboard's columns — a board draws them as stickies, a column card as rows */
export function boardColumns(a: Agents, ctx: BoardCtx = {}): { name: string; items: BoardItem[] }[] {
  const cols: BoardItem[][] = COLS.map(() => [])
  for (const tk of a.tickets as Ticket[]) {
    if (tk.epic_id != null) continue
    if (tk.kind === "epic") {
      const next = tk.next ? ` → #${tk.next.id} ${tk.next.title}` : ""
      cols[0]!.push({ act: { kind: "epic", id: tk.id }, title: `${tk.title} ${tk.done ?? 0}/${tk.total ?? 0}${next}`, who: null, stage: "epic", asks: false, archetype: null, high: tk.priority === "high" })
      continue
    }
    cols[0]!.push({ act: { kind: "ticket", id: tk.id }, title: tk.title, who: null, stage: tk.routed ? "with the manager" : "ticket", asks: false, archetype: null, high: tk.priority === "high", routed: !!tk.routed })
  }
  for (const th of a.threads) {
    if (th.duty) continue
    const c = th.stage ? STAGE_COL[th.stage] : th.lead && !th.standing && th.seat === "desk" ? 1 : undefined
    if (c === undefined) continue
    const r = a.roster.find((x) => x.thread_id === th.id)
    cols[c]!.push({ act: { kind: "thread", tid: th.id }, title: th.title, who: r?.agent ?? th.lead ?? null, stage: th.stage ?? "doing", asks: needsYou(th), archetype: r?.archetype ?? null, high: false, state: cardState(a, th, ctx) })
  }
  return COLS.map((name, i) => ({ name, items: cols[i]! }))
}

/** a person's one-line tip: who, in what role, on what, asking what, and where they are */
export function tipOf(r: Seat, th: Thread | undefined, where: string) {
  const ask = th?.prompt ? `\nasks: ${th.prompt.summary}` : th?.awaiting ? `\nawaits ${th.awaiting}` : ""
  const on = r.thread_id > 0 ? ` · #${r.thread_id} ${th?.title ?? r.title}` : " · on the bench"
  return `${r.agent}${r.archetype ? ` (${r.archetype}${r.lead ? ", lead" : ""})` : ""}${on}${ask}\n${where}`
}
