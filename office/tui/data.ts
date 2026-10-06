// The TUI's line to the server: the operator API over loopback HTTP (Server.MCP.OperatorAPI) — the
// always-up service at 127.0.0.1:4040 unless TLON_URL says otherwise. No checkout, no release
// beside it: a compiled TUI runs anywhere the server answers.
import { EMPTY, type Agents, type CorkNote, type ThreadView } from "../kit/types"
import type { Target } from "./terminal"

const BASE = (process.env.TLON_URL ?? "http://127.0.0.1:4040").replace(/\/$/, "")

async function call(method: "GET" | "POST" | "PATCH" | "DELETE", path: string, body?: unknown): Promise<{ status: number; json: any }> {
  const r = await fetch(`${BASE}/api${path}`, {
    method,
    headers: body === undefined ? {} : { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  })
  return { status: r.status, json: await r.json().catch(() => null) }
}

export async function status(): Promise<Agents> {
  try {
    const { status, json: j } = await call("GET", "/office")
    if (status !== 200 || !j) throw new Error(`office ${status}`)
    return {
      ok: true, roster: j.roster ?? [], threads: j.threads ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0,
      bench: j.bench ?? [], projects: j.projects ?? [], tickets: j.tickets ?? [], workspaces: j.workspaces ?? [], archetypes: j.archetypes ?? [], models: j.models ?? [], notes: j.notes ?? [], visits: j.visits ?? [], triage: j.triage ?? {}, health: j.health ?? null, calendar: j.calendar ?? {},
    }
  } catch {
    return { ...EMPTY, note: `channel down (${BASE})` }
  }
}
/** where a thread's coworker runs (its tmux socket, session, window), or null when it has no window */
export async function terminal(id: number): Promise<Target | null> {
  try { const r = await call("GET", `/threads/${id}/terminal`); return r.status === 200 ? r.json : null } catch { return null }
}
/** where a thread's coworker works (its git worktree, created on first ask), or null with no repo */
export async function worktree(id: number): Promise<string | null> {
  try { const r = await call("GET", `/threads/${id}/worktree`); return r.status === 200 ? r.json.path : null } catch { return null }
}
export type Archive = { tickets: { id: number; title: string; closed_at: string | null }[]; threads: { id: number; title: string; stage: string | null; at: string }[] }
/** a workspace's finished work: done tickets and closed threads, newest first */
export async function archive(ws: number): Promise<Archive | null> {
  try { const r = await call("GET", `/office/archive/${ws}`); return r.status === 200 ? r.json : null } catch { return null }
}
/** the workspace's recent small talk (empty where the server's banter is off) */
export async function banter(ws: number): Promise<{ agent: string; line: string; at: number }[]> {
  try { const r = await call("GET", `/office/banter/${ws}`); return r.status === 200 ? r.json : [] } catch { return [] }
}
/** the office corkboard: the coworkers' notes to each other, newest first (empty where banter is off) */
export async function corkboard(ws: number): Promise<CorkNote[]> {
  try { const r = await call("GET", `/office/corkboard/${ws}`); return r.status === 200 ? r.json : [] } catch { return [] }
}
/** each pet's lines by occasion, written by the server's model (empty where it is off) */
export async function pets(ws: number): Promise<Record<string, Record<string, string[]>>> {
  try { const r = await call("GET", `/office/pets/${ws}`); return r.status === 200 ? r.json : {} } catch { return {} }
}
export async function thread(id: number): Promise<ThreadView | null> {
  try { const r = await call("GET", `/office/threads/${id}`); return r.status === 200 ? r.json : null } catch { return null }
}

/** a write: a line for the status bar saying what happened, or why it didn't */
const write = (what: string, path: string, body: unknown, ok: (j: any) => string) => send("POST", what, path, ok, body)
async function send(method: "POST" | "PATCH" | "DELETE", what: string, path: string, ok: (j: any) => string, body: unknown = {}): Promise<string> {
  try {
    const r = await call(method, path, body)
    return r.status < 300 ? ok(r.json) : `${what} failed: ${r.json?.error ?? r.status}`
  } catch (e) {
    return `${what} failed: ${(e as Error).message}`
  }
}
/** post to a thread as the operator; a body naming an open prompt's option answers it */
export const post = (id: number, body: string) => write(`reply to #${id}`, `/threads/${id}/messages`, { body }, () => `sent to #${id}`)
export const ticketFile = (ws: number, title: string) => write("filing a ticket", "/tickets", { workspace_id: ws, title }, (j) => `filed ticket #${j.id}`)
/** send a ticket to the workspace's manager to staff (no manager: its lead starts it) */
export const ticketRoute = (id: number) =>
  write(`sending #${id} to the manager`, `/tickets/${id}/route`, {}, (j) => (j.routed_to ? `ticket #${id} sent to ${j.routed_to}` : `no manager: #${id} started as thread #${j.thread}`))
/** start a ticket's thread with the workspace's lead */
export const ticketStart = (id: number) => write(`starting #${id}`, `/tickets/${id}/start`, {}, (j) => `ticket #${id} started as thread #${j.thread}`)
/** close a thread as done: its sessions end, its ticket is done, a child reports up */
export const closeThread = (id: number) => write(`closing #${id}`, `/threads/${id}/close`, {}, (j) => `closed #${id} — ${j.title}`)

/** a page of a thread's messages: the newest, or with `before` the ones older than that message id */
export async function page(id: number, before: number): Promise<ThreadView | null> {
  try { const r = await call("GET", `/office/threads/${id}?before=${before}`); return r.status === 200 ? r.json : null } catch { return null }
}
async function read<T>(path: string): Promise<T | null> {
  try { const r = await call("GET", path); return r.status === 200 ? r.json : null } catch { return null }
}
export type Activity = { kind: string; at: string; thread_id: number | null; who: string | null; text: string }[]
export type Capped<T> = { shown: T[]; more: number }
export type Stuck = { thread_id: number; title: string; text: string }
export type Triage = { blockers: Capped<Stuck>; failed_checks: Capped<Stuck>; unled: Capped<Stuck>; count: number }
export type Health = { state: "ok" | "warn"; problems: string[]; version: string; up_s: number; db: boolean; jobs: boolean; failed_jobs: number; tmux: boolean; disk_pct: number | null; mem_pct: number | null; load: number | null }
export type Memory = { pinned: { id: number; text: string }[]; habits: { id: number; text: string; rationale: string | null; by: string | null }[]; coverage: { facts: number; embedded: number; pinned_count: number; pinned_tokens: number; budget: number } }
export type BoardTicket = { id: number; title: string; body: string | null; status: "backlog" | "todo" | "doing" | "done"; priority: string; project_id: number | null; blocked_by: number[] }
export type WorkspaceCard = { id: number; name: string; type: string; scope: string; icon: string | null; repos: { id: number; path: string; remote: string | null }[] }
export type Closed = { id: number; title: string; workspace_id: number | null; at: string }

/** what just happened in a workspace, newest first (the in-tray) */
export const activity = (ws: number) => read<Activity>(`/office/activity/${ws}`)
/** what is stuck in a workspace (the beacon) */
export const triage = (ws: number) => read<Triage>(`/office/triage/${ws}`)
/** the service and its box (the rack) */
export const health = () => read<Health>("/office/health")
/** pinned facts and habits to review */
export const memory = (ws: number) => read<Memory>(`/office/memory/${ws}`)
/** every ticket in a workspace, every status, in board order */
export const board = (ws: number) => read<BoardTicket[]>(`/office/tickets/${ws}`)
/** a workspace's settings and repos */
export const workspaceCard = (ws: number) => read<WorkspaceCard>(`/office/workspace/${ws}`)
/** the office's switches, machine-wide, from the server's settings file */
export type Settings = { banter: boolean }
export const settings = () => read<Settings>("/settings")
/** every closed thread, for the finder */
export const history = () => read<Closed[]>("/office/history")

export type Kind = "thread" | "workline" | "spike"
/** a new thread from your first words (its first line the title); a workline or a spike instead with `kind` */
export const newThread = (ws: number, body: string, project: number | null, kind: Kind) =>
  write("starting a thread", "/threads", { workspace_id: ws, body, project_id: project, kind }, (j) => `started #${j.id} ${j.title}`)
export const note = (ws: number, body: string) => write("pinning a note", "/notes", { workspace_id: ws, body }, () => "note pinned")
export const approve = (id: number) => write(`approving #${id}`, `/threads/${id}/approve`, {}, (j) => `#${id} approved — now ${j.stage}`)
export const advance = (id: number) => write(`advancing #${id}`, `/threads/${id}/advance`, {}, (j) => (j.gated ? `#${id} is at a gate: ${j.stage}` : `#${id} now ${j.stage}`))
export const handOff = (id: number, agent: string) => write(`handing #${id} off`, `/threads/${id}/hand-off`, { agent }, () => `#${id} handed to ${agent}`)
export const move = (id: number, project: number) => write(`moving #${id}`, `/threads/${id}/move`, { project_id: project }, () => `#${id} moved`)
export const deleteThread = (id: number) => send("DELETE", `deleting #${id}`, `/threads/${id}`, (j) => `deleted #${id}${j.worktree ? ` — worktree ${j.worktree}` : ""}`)

export const ticketPatch = (id: number, patch: { status?: string; title?: string; body?: string }) => send("PATCH", `changing #${id}`, `/tickets/${id}`, (j) => `#${id} ${j.status}`, patch)
export const ticketDelete = (id: number) => send("DELETE", `deleting #${id}`, `/tickets/${id}`, () => `ticket #${id} deleted`)
export const ticketReorder = (id: number, direction: "up" | "down") => write(`moving #${id}`, `/tickets/${id}/reorder`, { direction }, () => `#${id} moved ${direction}`)
export const ticketBlock = (id: number, by: number) => write(`blocking #${id}`, `/tickets/${id}/blockers`, { by }, () => `#${id} blocked by #${by}`)
export const ticketUnblock = (id: number, by: number) => send("DELETE", `unblocking #${id}`, `/tickets/${id}/blockers/${by}`, () => `#${id} no longer blocked by #${by}`)

export const hire = (ws: number, name: string, archetype: string) => write(`hiring ${name}`, `/workspaces/${ws}/coworkers`, { name, archetype }, () => `hired ${name}, a ${archetype}`)
/** a coworker's model or ask policy; "inherit" puts it back to the archetype's */
export const retarget = (ws: number, agent: number, knobs: { model?: string; ask?: string }) => send("PATCH", "changing a coworker", `/workspaces/${ws}/coworkers/${agent}`, (j) => `now ${j.model ? `${j.model.provider}/${j.model.model}` : "the archetype's model"} · ${j.ask ?? "the archetype's ask"}`, knobs)
export const unseat = (seat: number, name: string) => send("DELETE", `letting ${name} go`, `/seats/${seat}`, () => `${name} is off the bench`)

export const workspaceNew = (name: string, template: string) => write(`opening ${name}`, "/workspaces", { name, template }, (j) => `opened ${j.name}`)
export const workspaceEdit = (ws: number, patch: { type?: string; scope?: string; icon?: string }) => send("PATCH", "changing the workspace", `/workspaces/${ws}`, () => "workspace changed", patch)
export const settingsEdit = (patch: Partial<Settings>) => send("PATCH", "changing the settings", "/settings", (j) => `banter ${j.banter ? "on" : "off"}`, patch)
export const workspaceDelete = (ws: number) => send("DELETE", "closing the workspace", `/workspaces/${ws}`, () => "workspace closed")
export const repoAdd = (ws: number, path: string) => write(`adding ${path}`, `/workspaces/${ws}/repos`, { path }, () => `added ${path}`)
export const repoRemove = (id: number) => send("DELETE", "removing the repo", `/repos/${id}`, () => "repo removed")

export const habit = (id: number, verdict: "approve" | "reject") => write(`reviewing habit ${id}`, `/habits/${id}/${verdict}`, {}, () => `habit ${verdict === "approve" ? "approved" : "rejected"}`)
export const forget = (id: number) => send("DELETE", `forgetting fact ${id}`, `/facts/${id}`, () => `fact ${id} forgotten`)

export type ScheduleKind = "agent" | "workline" | "script"
export type Schedule = {
  id: number; kind: ScheduleKind; title: string; body: string; cron: string | null; at: string | null; agent: string | null
  standing: boolean; thread_id: number | null; dir: string | null; enabled: boolean; next_at: string | null; days: number[]
  last: { status: "running" | "ok" | "failed"; exit: number | null; at: string; thread_id: number | null } | null
}
export type Run = { id: number; status: "running" | "ok" | "failed"; exit: number | null; output: string | null; thread_id: number | null; started_at: string; finished_at: string | null }
export type ScheduleAttrs = { kind?: ScheduleKind; body?: string; title?: string; cron?: string | null; at?: string | null; agent?: string | null; standing?: boolean; dir?: string | null; enabled?: boolean }

/** a workspace's schedules, with when each next fires and the days this month it does */
export const schedules = (ws: number) => read<Schedule[]>(`/office/schedules/${ws}`)
/** a schedule's recent runs, newest first (the automation board) */
export const runs = (id: number) => read<Run[]>(`/schedules/${id}/runs`)
export const scheduleNew = (ws: number, attrs: ScheduleAttrs) => write("scheduling", "/schedules", { workspace_id: ws, ...attrs }, (j) => `scheduled ${j.title}`)
export const schedulePatch = (id: number, attrs: ScheduleAttrs) => send("PATCH", "changing the schedule", `/schedules/${id}`, (j) => `${j.title}${j.enabled ? "" : " (paused)"}`, attrs)
export const scheduleDelete = (id: number) => send("DELETE", "removing the schedule", `/schedules/${id}`, () => "schedule removed")
export const scheduleRun = (id: number) => write("running it now", `/schedules/${id}/run`, {}, () => "running it now — its run shows on the board")
/** clear a coworker's context: its sessions end and its windows close; the next message spawns it fresh */
export const clearContext = (ws: number, agent: number, name: string) => write(`clearing ${name}`, `/workspaces/${ws}/coworkers/${agent}/clear`, {}, () => `${name} starts fresh next time they're needed`)
