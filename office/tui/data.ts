// The TUI's line to the server: the operator API over loopback HTTP (Server.MCP.OperatorAPI) — the
// always-up service at 127.0.0.1:4040 unless TLON_URL says otherwise. No checkout, no release
// beside it: a compiled TUI runs anywhere the server answers.
import { AsyncLocalStorage } from "node:async_hooks"
import { EMPTY, type Agents, type CorkNote, type LifeStatus, type Thread, type ThreadView } from "../kit/types"
import { toysOf, type Toys } from "../kit/door"
import type { Note } from "../kit/margin"
import type { Target } from "./terminal"
import type { Toy } from "./sandbox"

// read per call, not at load: a test (or a relaunch) that points TLON_URL elsewhere is believed
const base = () => (process.env.TLON_URL ?? "http://127.0.0.1:4040").replace(/\/$/, "")

let fake: Toy | null = null
/** the sandbox's world instead of the server (`office --sandbox`) */
/** a new source: what was held belongs to the old one */
export const useFake = (t: Toy | null) => { fake = t; lastGood = null; lastNeeds = noNeeds; down = null }

async function call(method: "GET" | "POST" | "PUT" | "PATCH" | "DELETE", path: string, body?: unknown): Promise<{ status: number; json: any }> {
  if (fake) {
    if (method !== "GET") return { status: 409, json: { error: "it's a toy — nothing here to change" } }
    if (path === "/office") return { status: 200, json: fake.snapshot() }
    const json = fake.read(path)
    return json === undefined ? { status: 404, json: null } : { status: 200, json }
  }
  const r = await fetch(`${base()}/api${path}`, {
    method,
    headers: body === undefined ? {} : { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  })
  return { status: r.status, json: await r.json().catch(() => null) }
}

/** the last snapshot that answered, and when: a down channel returns it marked down, never an empty office */
let lastGood: { a: Agents; at: number } | null = null
/** the last status's down note, for the server it asked: a write there refuses up front rather than wait out the timeout */
let down: { url: string; note: string } | null = null
export async function status(): Promise<Agents> {
  try {
    const { status, json: j } = await call("GET", "/office")
    if (status !== 200 || !j) throw new Error(`office ${status}`)
    const a: Agents = {
      ok: true, roster: j.roster ?? [], threads: (j.threads ?? []).map((t: Thread) => (t.standing && t.title === "lobby" ? { ...t, title: "the front desk" } : t)), counts: j.counts ?? {}, awaiting: j.awaiting ?? 0,
      bench: j.bench ?? [], projects: j.projects ?? [], tickets: j.tickets ?? [], workspaces: j.workspaces ?? [], shifts: j.shifts ?? [], archetypes: j.archetypes ?? [], models: j.models ?? [], notes: j.notes ?? [], visits: j.visits ?? [], triage: j.triage ?? {}, health: j.health ?? null, calendar: j.calendar ?? {}, revs: j.revs, release: j.release, usage: j.usage, pause: j.pause, flags: j.flags ?? {}, life: j.life ?? {},
    }
    lastGood = { a, at: Date.now() }
    down = null
    return a
  } catch {
    const note = `channel down (${base()})`
    down = { url: base(), note }
    return lastGood ? { ...lastGood.a, ok: false, note, heldAt: lastGood.at } : { ...EMPTY, note }
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
/** the newest "show thread N" request from another surface (the desktop's alerts), or null */
export async function focus(): Promise<{ thread_id: number; at: number } | null> {
  try { const r = await call("GET", "/office/focus"); return r.status === 200 ? r.json : null } catch { return null }
}
/** a workline branch's change, for the operator's review: files, hunks, numbered lines */
export type ReviewLine = { kind: "+" | "-" | " "; old: number | null; new: number | null; text: string }
export type Review = { head: string | null; files: { path: string; status: string; added: number; deleted: number; binary: boolean; hunks: { header: string; lines: ReviewLine[] }[] }[] }
/** a note on a line (`line` and its `side`) or on a whole file */
export type ReviewNote = { path: string; line?: number; side?: "+" | "-" | " "; text: string }
export const review = (id: number) => read<Review>(`/threads/${id}/review`)
export const reviewSubmit = (id: number, verdict: string, summary: string, notes: ReviewNote[]) =>
  write(`reviewing #${id}`, `/threads/${id}/review`, { verdict, summary, notes }, (j) => `#${id} reviewed (${verdict}) · at ${j.stage ?? "?"}`)

/** a workline's docs (work/<slug>/*.md), by name */
export async function docs(id: number): Promise<string[]> {
  try { const r = await call("GET", `/threads/${id}/docs`); return r.status === 200 ? r.json : [] } catch { return [] }
}
/** one doc's text ("current": the doc the stage is about), or null */
export async function doc(id: number, name: string): Promise<string | null> {
  try { const r = await call("GET", `/threads/${id}/docs/${encodeURIComponent(name)}`); return r.status === 200 ? r.json.text : null } catch { return null }
}
export type Archive = { tickets: { id: number; title: string; closed_at: string | null }[]; threads: { id: number; title: string; stage: string | null; at: string }[] }
/** a workspace's finished work: done tickets and closed threads, newest first */
export const archive = (ws: number) => read<Archive>(`/office/archive/${ws}`)
/** the workspace's recent small talk (empty where the server's banter is off) */
export async function banter(ws: number): Promise<{ agent: string; line: string; at: number }[]> {
  try { const r = await call("GET", `/office/banter/${ws}`); return r.status === 200 ? r.json : [] } catch { return [] }
}
/** the toy pool the server generated for a workspace (`Server.ToyPool`): null on a server without the route or with nothing readable */
export const toys = async (ws: number): Promise<Toys | null> => toysOf(await read<unknown>(`/office/toys/${ws}`))
/** the office corkboard: the coworkers' notes to each other, newest first (empty where banter is off) */
export async function corkboard(ws: number): Promise<CorkNote[]> {
  try { const r = await call("GET", `/office/corkboard/${ws}`); return r.status === 200 ? r.json : [] } catch { return [] }
}
/** an item waiting on the operator (`Server.Office.Needs`): blocking ones stop work until acted on */
export type Need = {
  key: string; kind: "gate" | "question" | "dialog" | "ask" | "verify_failed" | "stalled" | "mention" | "rollout" | "seats" | "job_failed" | "stranded" | "issue" | "publish_failed" | "release_failed" | "pr_blocked" | "quota" | "no_seat" | "tool_denied"
  level: "blocking" | "decide"; thread_id: number | null; workspace_id: number | null; title: string; text: string; at: string
  options: { key: string; label: string }[] | null; ref: number | null
  /** a pr_blocked item's PR */
  url?: string
  /** no_seat: the kind of seat the workline's stage needs */
  archetype?: string
  /** ask: who asked; Uqbar's own ask is never handed back to it */
  ask?: string
  /** tool_denied: the Claude Code allow rule the refused command needs, yours to add to your own settings */
  rule?: string
  /** who acts on it (`Needs.surface/1`): phone, an answer is owed; machine, information; clipboard, the crew owns it */
  surface?: Surface
  /** clipboard: the thread's lead, and the workline or ticket tracking it */
  owner?: string | null
  tracking?: string | null
  /** tool_denied: a hook refused it, so no allow rule lifts it */
  hook?: boolean
  /** `Needs.grouped/1`'s routing: uqbar (awaiting Uqbar), settled, pass_up or info */
  route?: "uqbar" | "settled" | "pass_up" | "info"
  /** passed up: what Uqbar would do (null for a kind that always passes up) */
  recommendation?: string | null
  /** settled: how Uqbar handled it; passed up: why it needs you */
  why?: string | null
}
export type Surface = "phone" | "machine" | "clipboard"
/** the inbox by who acts: `items` is every one that reaches you, phone first; `uqbar` waits on Uqbar and `settled` is what it handled today — neither reaches you */
export type Needs = { items: Need[]; phone: Need[]; machine: Need[]; clipboard: Need[]; uqbar: Need[]; settled: Need[]; counts: Record<Surface | "uqbar" | "settled", number> }
const SURFACES: Surface[] = ["phone", "machine", "clipboard"]
type Groups = Record<Surface, Need[]> & { uqbar?: Need[]; settled?: Need[] }
const inboxOf = ({ uqbar = [], settled = [], ...g }: Groups): Needs => ({
  ...g, uqbar, settled, items: SURFACES.flatMap((s) => g[s]),
  counts: { phone: g.phone.length, machine: g.machine.length, clipboard: g.clipboard.length, uqbar: uqbar.length, settled: settled.length },
})
const noNeeds = inboxOf({ phone: [], machine: [], clipboard: [] })
let lastNeeds: Needs = noNeeds
/** everything waiting on the operator, by surface; a server that can't answer keeps the last inbox, so the phone never goes quiet mid-outage. A server with only the flat list is grouped by each item's surface, none on the phone */
export async function needs(): Promise<Needs> {
  try {
    const r = await call("GET", "/office/needs?by=surface")
    if (r.status !== 200) return lastNeeds
    if (Array.isArray(r.json)) {
      const on = (s: Surface) => (r.json as Need[]).filter((n) => (n.surface ?? "phone") === s)
      lastNeeds = inboxOf({ phone: on("phone"), machine: on("machine"), clipboard: on("clipboard") })
    } else { const g = inboxOf(r.json); lastNeeds = { ...g, counts: { ...g.counts, ...r.json.counts } } }
    return lastNeeds
  } catch { return lastNeeds }
}
/** the machine opened: these items are heard and leave it */
export const hear = (keys: string[]) => write("marking heard", "/office/needs/heard", { keys }, () => "heard")
/** a need Uqbar settled goes back to Uqbar's queue — not to you */
export const overrule = (key: string) => write("overruling", "/office/needs/overrule", { key }, () => "back with Uqbar")
/** a landing GitHub isn't merging: back in the merge queue — rebased, gated, merged at that head */
export const rebaseLanding = (tid: number) => write(`requeuing #${tid}'s PR`, `/threads/${tid}/rebase`, {}, () => `#${tid}'s PR back in the merge queue`)
/** a landing GitHub isn't merging: its PR closed, the workline back to build on its branch */
export const relandLanding = (tid: number) => write(`relanding #${tid}`, `/threads/${tid}/reland`, {}, () => `#${tid}'s PR closed; back to build`)
export const reverify = (tid: number) => write(`re-running verify on #${tid}`, `/threads/${tid}/verify`, {}, () => `verify on #${tid} queued`)
/** answer one prompt — a pane's dialog, an ask, the release gate — by its id, so a key can't land in another prompt on its thread */
export const answer = (id: number, key: string) => write("answering", `/office/prompts/${id}`, { key }, () => "answered")
/** an ask handed to Uqbar, the operator's delegate, to decide and act on as the operator */
export const handToUqbar = (id: number) => write("handing it to Uqbar", `/office/prompts/${id}/uqbar`, {}, () => "handed to Uqbar")
export const retryJob = (id: number) => write("retrying the job", `/office/jobs/${id}/retry`, {}, () => "running it again")
export const dismissJob = (id: number) => send("DELETE", "clearing the job", `/office/jobs/${id}`, () => "dismissed")
/** a landed workline whose publish failed, pushed and its PR opened again */
export const republish = (tid: number) => write(`republishing #${tid}`, `/threads/${tid}/republish`, {}, (j) => (j.published ? `published as ${j.published}` : "nothing to publish to"))
/** a failed publish whose PR the operator opened by hand: its url, waited on until GitHub merges it */
export const publishedByHand = (tid: number, url: string) => write(`waiting on ${url}`, `/threads/${tid}/published`, { url }, () => "waiting on GitHub")
/** a failed release cut, by its event, queued to cut again */
export const retryRelease = (id: number) => write("retrying the cut", `/release/retry/${id}`, {}, (j) => `cut of ${String(j.queued).slice(0, 7)} queued`)
export const dismissRollout = (id: number) => send("DELETE", "clearing the note", `/office/rollout/${id}`, () => "done")
/** put an inbox item away without acting on it; one that work waits on is refused */
export const dismissNeed = (key: string) => write("dismissing it", "/office/needs/dismiss", { key }, () => "dismissed")
/** a stranded checkout taken down, its branch kept */
export const retireStranded = (key: string) => write("taking the checkout down", "/office/needs/retire", { key }, () => "checkout removed; branch kept")
/** file a ticket from an issue that owns it, routed to the manager; its landing resolves the issue */
export const fixIssue = (id: number) => write("getting the issue fixed", `/issues/${id}/fix`, {}, (j) => `issue #${id} is ticket #${j.ticket_id} now, ${j.owner}`)
export const resolveIssue = (id: number, resolution: string) => write("resolving the issue", `/issues/${id}/resolve`, { resolution }, () => "resolved")
/** Uqbar's margin notes in a workspace, newest first (empty when there are none or the server is down) */
export async function margin(ws: number): Promise<Note[]> {
  try { const r = await call("GET", `/office/margin/${ws}`); return r.status === 200 ? r.json : [] } catch { return [] }
}
/** the suggestion box: the crew's suggestions not yet filed or thrown out */
export async function suggestions(ws: number): Promise<CorkNote[]> {
  try { const r = await call("GET", `/office/suggestions/${ws}`); return r.status === 200 ? r.json : [] } catch { return [] }
}
/** take a suggestion out of the box (it was filed, or thrown out) */
export const dropSuggestion = (ws: number, id: number) => send("DELETE", "clearing the suggestion", `/office/suggestions/${ws}/${id}`, () => "out of the box")
/** each pet's lines by occasion, written by the server's model (empty where it is off) */
export async function pets(ws: number, cat?: { name: string; species: string; warmth: number; wits: number; energy: number }): Promise<Record<string, Record<string, string[] | string[][]>>> {
  const q = cat ? `?${new URLSearchParams({ cat: cat.name, species: cat.species, warmth: String(cat.warmth), wits: String(cat.wits), energy: String(cat.energy) })}` : ""
  try { const r = await call("GET", `/office/pets/${ws}${q}`); return r.status === 200 ? r.json : {} } catch { return {} }
}
/** two coworkers together in the room: what they say, written now by the server's model; [] when they talked a moment ago */
export async function talk(ws: number, situation: string, a: string, b: string): Promise<{ who: string; line: string }[]> {
  try { const r = await call("POST", `/office/talk/${ws}`, { situation, a, b }); return r.status === 200 ? r.json.turns ?? [] : [] } catch { return [] }
}
export async function thread(id: number): Promise<ThreadView | null> {
  try { const r = await call("GET", `/office/threads/${id}`); return r.status === 200 ? r.json : null } catch { return null }
}

/** a write: a line for the status bar saying what happened, or why it didn't */
const write = (what: string, path: string, body: unknown, ok: (j: any) => string) => send("POST", what, path, ok, body)
async function send(method: "POST" | "PUT" | "PATCH" | "DELETE", what: string, path: string, ok: (j: any) => string, body: unknown = {}): Promise<string> {
  if (down?.url === base()) return `${what} not sent: ${down.note} · mise run server:restart`
  try {
    const r = await call(method, path, body)
    return r.status < 300 ? ok(r.json) : `${what} failed: ${r.json?.error ?? r.status}`
  } catch (e) {
    return `${what} failed: ${(e as Error).message}`
  }
}
/** whether a post's status line says it went (`sent to #9`, `said to …`, `handed …`); anything else is the reason it did not */
export const landed = (line: string) => /^(sent|said|handed)\b/.test(line)
/** post to a thread as the operator: a plain post, never an answer to a prompt (that is `answer`) */
export const post = (id: number, body: string) => write(`reply to #${id}`, `/threads/${id}/messages`, { body }, () => `sent to #${id}`)
export const ticketFile = (ws: number, title: string) => write("filing a ticket", "/tickets", { workspace_id: ws, title }, (j) => `filed ticket #${j.id}`)
/** send a ticket to the workspace's manager to staff (no manager: its lead starts it) */
export const ticketRoute = (id: number) =>
  write(`sending #${id} to the manager`, `/tickets/${id}/route`, {}, (j) => (j.routed_to ? `ticket #${id} sent to ${j.routed_to}` : `no manager: #${id} started as thread #${j.thread}`))
/** start a ticket's thread with the workspace's lead */
export const ticketStart = (id: number) => write(`starting #${id}`, `/tickets/${id}/start`, {}, (j) => `ticket #${id} started as thread #${j.thread}`)
/** close a thread as done: its sessions end, its ticket is done, a child reports up */
export const closeThread = (id: number, abandoned?: string) => write(`closing #${id}`, `/threads/${id}/close`, abandoned ? { abandoned } : {}, (j) => `closed #${id} — ${j.title}`)

/** a page of a thread's messages: the newest, or with `before` the ones older than that message id */
export async function page(id: number, before: number): Promise<ThreadView | null> {
  try { const r = await call("GET", `/office/threads/${id}?before=${before}`); return r.status === 200 ? r.json : null } catch { return null }
}
/** why a `read` gave nothing: kept per `reading` scope, so one card's poll never rewrites another card's reason */
const readScope = new AsyncLocalStorage<{ why: string | null }>()
/** run a card's reads together and say why the last one that came back empty did, or null when it answered: a card with nothing to show says so instead of "reading…" for ever */
export async function reading(fn: () => Promise<unknown>): Promise<string | null> {
  const scope = { why: null as string | null }
  await readScope.run(scope, fn)
  return scope.why
}
async function read<T>(path: string): Promise<T | null> {
  const scope = readScope.getStore()
  try {
    const r = await call("GET", path)
    if (r.status === 200 && r.json !== null) { if (scope) scope.why = null; return r.json }
    if (scope) scope.why = r.status === 200 ? "the server sent nothing" : r.status === 404 ? "the server has no such page" : `the server answered ${r.status}`
  } catch (e) { if (scope) scope.why = (e as Error).name === "TimeoutError" ? "the server isn't answering" : (e as Error).message }
  return null
}
/** a home workspace's life card body */
export const life = (ws: number) => read<LifeStatus>(`/life/${ws}`)
/** stamp a routine done; says so, and shouts a level-up */
export const routineDone = (id: number, title: string) =>
  write(`stamping ${title}`, `/life/routines/${id}/done`, {}, (j) => `${title} done${j.level_up ? " — level up!" : ""}`)
export const questDone = (id: number, title: string) =>
  write(`finishing ${title}`, `/life/quests/${id}/done`, {}, (j) => `${title} done${j.level_up ? " — level up!" : ""}`)
export const routineNew = (ws: number, title: string, every: string) =>
  write("adding the routine", `/life/${ws}/routines`, { title, every }, (j) => `added ${j.title}`)
export const questNew = (ws: number, title: string) =>
  write("adding the quest", `/life/${ws}/quests`, { title }, (j) => `added ${j.title}`)
/** the home's dump: the one page everything gets poured into (body "" before the first write) */
export const dump = (ws: number) => read<{ id: number | null; body: string; updated_at: string | null }>(`/life/${ws}/dump`)
/** "1 line", "4 lines" */
export const lines = (n: number) => `${n} line${n === 1 ? "" : "s"}`
export type DumpPage = { id: number; at: string; lines: number; first: string }
/** the dump's earlier pages, newest first: every page a save replaced */
export const dumpPages = (ws: number) => read<DumpPage[]>(`/life/${ws}/dump/revisions`)
export const dumpPage = (ws: number, id: number) => read<{ id: number; at: string; body: string }>(`/life/${ws}/dump/revisions/${id}`)
/** `ok` only when the server took it: a page not taken stays unsent, and the next write, leave or open sends it */
export async function dumpPut(ws: number, body: string): Promise<{ ok: boolean; line: string }> {
  let ok = false
  const line = await send("PUT", "saving the dump", `/life/${ws}/dump`, () => ((ok = true), `dump saved · ${lines(body.trimEnd().split("\n").length)}`), { body })
  return { ok, line }
}
export type Activity = { kind: string; at: string; thread_id: number | null; who: string | null; text: string }[]
export type Capped<T> = { shown: T[]; more: number }
/** a triage item; `issue_id` onward are a blocker's, `check_id` onward a failed check's (`stage`: only a thread at `verify` can re-run it) */
export type Stuck = { thread_id: number; title: string; text: string; issue_id?: number; /** the ticket fixing it, once someone pressed get-it-fixed */ ticket_id?: number | null; ticket_status?: string | null; found_by?: string | null; created_at?: string; summary?: string; evidence?: string | null; check_id?: number; slug?: string; stage?: string | null }
export type Triage = { blockers: Capped<Stuck>; failed_checks: Capped<Stuck>; /** every red thread, not only the capped `shown` */ failed_thread_ids?: number[]; unled: Capped<Stuck>; count: number }
export type Health = { state: "ok" | "warn"; problems: string[]; version: string; up_s: number; db: boolean; jobs: boolean; failed_jobs: number; tmux: boolean; disk_pct: number | null; mem_pct: number | null; load: number | null
  /** one full check at a time (scripts/checks-queue.sh): who has it, who waits */
  checks?: { running: string | null; waiting: string[] }
  /** approved worklines landing one at a time: the one being gated first */
  merge_queue?: { thread_id: number; title: string; state: "landing" | "queued" }[] }
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
/** the running system's knobs, machine-wide, from the server's settings file; `boot` ones take on a restart */
export type Knob = { key: string; type: "int" | "bool" | "string"; value: number | boolean | string | null; default: number | boolean | string | null; min?: number; max?: number; nullable?: boolean; boot: boolean; doc: string }
export type Settings = { knobs: Knob[]; restart_pending: boolean }
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
/** a workline back to an earlier stage on its own branch, the build kept; `why` reaches the stage's lead */
export const sendBack = (id: number, stage: "spec" | "plan" | "build", why: string) => write(`sending #${id} back to ${stage}`, `/threads/${id}/send_back`, { stage, why }, () => `#${id} back to ${stage}`)
/** the refused command's allow rule is in your own settings now: said on the thread, which wakes the lead to run it again */
/** a tool refusal's decision handed to Uqbar: a post to it on the thread, its lead untouched */
export const refusalToUqbar = (id: number, text: string) => write(`asking Uqbar about #${id}`, `/threads/${id}/messages`, { body: `@uqbar decide this tool refusal for me: ${text}` }, () => `#${id}: Uqbar asked to decide`)
export const allowed = (id: number, rule: string) => write(`telling #${id} it is allowed`, `/threads/${id}/messages`, { body: `Allowed: \`${rule}\` is in my Claude Code settings now; run it again.` }, () => `#${id} told: allowed`)
export const move = (id: number, project: number) => write(`moving #${id}`, `/threads/${id}/move`, { project_id: project }, () => `#${id} moved`)
export const deleteThread = (id: number) => send("DELETE", `deleting #${id}`, `/threads/${id}`, (j) => `deleted #${id}${j.worktree ? ` — worktree ${j.worktree}` : ""}`)

export const ticketPatch = (id: number, patch: { status?: string; title?: string; body?: string }) => send("PATCH", `changing #${id}`, `/tickets/${id}`, (j) => `#${id} ${j.status}`, patch)
export const ticketDelete = (id: number) => send("DELETE", `deleting #${id}`, `/tickets/${id}`, () => `ticket #${id} deleted`)
export const ticketReorder = (id: number, direction: "up" | "down") => write(`moving #${id}`, `/tickets/${id}/reorder`, { direction }, () => `#${id} moved ${direction}`)
export const ticketBlock = (id: number, by: number) => write(`blocking #${id}`, `/tickets/${id}/blockers`, { by }, () => `#${id} blocked by #${by}`)
export const ticketUnblock = (id: number, by: number) => send("DELETE", `unblocking #${id}`, `/tickets/${id}/blockers/${by}`, () => `#${id} no longer blocked by #${by}`)

export const hire = (ws: number, name: string, archetype: string) => write(`hiring ${name}`, `/workspaces/${ws}/coworkers`, { name, archetype }, () => `hired ${name}, a ${archetype}`)
/** a coworker's model or ask policy; "inherit" puts it back to the archetype's */
export const seatShift = (seat: number, name: string, crew: string) => send("PATCH", `putting ${name} on ${crew === "all" ? "every crew" : `the ${crew} crew`}`, `/seats/${seat}`, () => `${name} is on ${crew === "all" ? "every crew" : `the ${crew} crew`}`, { crew })
export const pause = (mode: "pencils_down" | "lights_out" | "back_to_work") => write(mode.replace(/_/g, " "), "/office/pause", { mode }, (j) => `the office: ${String(j.pause).replace(/_/g, " ")}`)
export const shiftSwitch = (ws: number, shift: string) => write(`putting the ${shift} crew on`, "/office/shift", { workspace_id: ws, shift }, (j) => `the ${shift} crew is on · ${j.restaffed?.length ?? 0} worklines restaffed, ${j.waiting?.length ?? 0} threads waiting`)
export const retarget = (ws: number, agent: number, knobs: { model?: string; ask?: string }) => send("PATCH", "changing a coworker", `/workspaces/${ws}/coworkers/${agent}`, (j) => `now ${j.model ? `${j.model.provider}/${j.model.model}` : "the archetype's model"} · ${j.ask ?? "the archetype's ask"}`, knobs)
/** a seat's persona: made if none, or `reroll` for a new seed */
export const persona = (ws: number, agent: number, reroll = false) => send("POST", "making a persona", `/workspaces/${ws}/coworkers/${agent}/persona`, (j) => `persona: seed ${j.seed}`, { reroll })
/** change what a person wrote into a persona: `voice`, `backstory` or `quirks` */
export const personaEdit = (ws: number, agent: number, fields: { voice?: string; backstory?: string; quirks?: Record<string, string> }) => send("PATCH", "editing a persona", `/workspaces/${ws}/coworkers/${agent}/persona`, () => "persona changed", fields)
export const unseat = (seat: number, name: string) => send("DELETE", `letting ${name} go`, `/seats/${seat}`, () => `${name} is off the bench`)

export const workspaceNew = (name: string, template: string) => write(`opening ${name}`, "/workspaces", { name, template }, (j) => `opened ${j.name}`)
export const workspaceEdit = (ws: number, patch: { type?: string; scope?: string; icon?: string }) => send("PATCH", "changing the workspace", `/workspaces/${ws}`, () => "workspace changed", patch)
export const settingsEdit = (key: string, value: unknown) => send("PATCH", `changing ${key}`, "/settings", () => `${key} → ${value ?? "off"}`, { [key]: value })
/** restart the server now if nothing is mid-turn, else at the first quiet moment; `force` now regardless */
export const restart = (force = false) =>
  write("restarting the server", "/restart", { force }, (j) => (j.scheduled ? `restart scheduled — waiting on ${j.waiting_on.length}: ${j.waiting_on.join("; ")}` : "the server is restarting"))
export const restartCancel = () => send("DELETE", "cancelling the restart", "/restart", () => "the scheduled restart is cancelled")
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
