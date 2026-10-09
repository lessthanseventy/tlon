// The server's office snapshot as `Server.Office.status` returns it (`GET /api/office`, and
// `scripts/tlon-cli.sh shell-status` for the desktop) — what every office surface reads.

/** a routine whose current due is unmet; `window_remaining` seconds, negative once past its window */
export type Due = { routine_id: number; title: string; due_at: string; window_remaining: number }
/** a workspace's life summary on the snapshot (`Server.Life.status`, trimmed); full detail is `GET /api/life/:ws` */
export type LifeSummary = { level: number; xp: number; due: Due[] }
export type LifeQuest = { id: number; title: string; due_at: string | null; xp: number }
/** `GET /api/life/:ws`: a home workspace's life card body */
export type LifeStatus = { xp: number; level: number; next_level_at: number; streaks: Record<string, number>; due: Due[]; quests: LifeQuest[]; today: { routine_id: number; title: string; due_at: string; done: boolean }[] }

/** `prompt`: its coworker is sitting on a dialog (Server.Attention) — the ask, answered from the thread */
/** `lead`: who it is staffed with; `live`: a tmux window is running it; `standing`: its workspace's lobby; `thinking`: who is mid-turn on it; `seat`: its lead at a desk (a window, a warm session), parked for a seat under the leaf cap, or idle; `duty`: a standing duty (a schedule's, the sheriff's beat), not work */
export type Thread = { id: number; title: string; stage: string | null; awaiting: string | null; workspace_id?: number | null; lead?: string | null; live?: boolean; standing?: boolean; thinking?: string[]; seat?: "desk" | "parked" | "idle"; duty?: boolean; prompt?: { summary: string; options?: { key: string; label: string }[] | null } | null }
/** `archetype`/`lead`: the agent's seat on its workspace bench (null/false off every bench); `warm`: its session is recent; `warmth`: how much of its warmth window is left, 1 fresh to 0 cold (the server's, per provider); `thinking`: it is mid-turn (its harness said so); `doing`: the kind of tool running in that turn (read, edit, bash, search, web, test, delegate), null between tools */
export type Seat = { agent: string; thread_id: number; title: string; warm: boolean; warmth?: number; thinking?: boolean; doing?: string | null; archetype?: string | null; lead?: boolean; workspace_id?: number | null }
/** a model as the server names it; `thinking` is the effort level */
export type ModelSpec = { provider: string; model: string; thinking: string }
import type { Persona } from "./persona"
/** a coworker a workspace employs, on a thread or not; `model`/`ask` are its policy, null = the archetype's */
export type Coworker = { workspace_id: number; seat_id: number; agent_id: number; name: string; archetype: string | null; lead: boolean; model: ModelSpec | null; ask: string | null; persona?: Persona | null }
/** what an archetype is beyond its prompt: `meta` never works a thread, `read_only` cannot write */
export type Archetype = { name: string; meta: boolean; read_only: boolean; model: string }
/** a model a coworker may run, keyed `provider/model`, with the harness it resolves to here */
export type ModelChoice = ModelSpec & { key: string; harness: string }
/** a note someone left (the whiteboard's strip); `workspace_id` null = machine-wide */
export type Note = { id: number; author: string; body: string; workspace_id: number | null; at: string }
/** a consult in the last few minutes: `from` asked `to` something */
export type Visit = { from: string; to: string; workspace_id: number; at: string }
/** a note on the office corkboard (`Server.Office.Corkboard`): chatter, not working notes; `re` the note it answers */
export type CorkNote = { id: number; author: string; kind: "encourage" | "tease" | "joke" | "comment" | "suggestion" | "reply"; body: string; re: number | null; at: number }
/** a filed ticket nobody has started yet */
export type Ticket = { id: number; workspace_id: number; project_id: number | null; title: string; priority: string; routed?: boolean
  /** "epic" rows group the tickets whose `epic_id` is theirs; `done`/`total`/`next` are the epic's progress and its next free child */
  kind?: "ticket" | "epic"; epic_id?: number | null; done?: number; total?: number; next?: { id: number; title: string } | null }
export type Agents = {
  ok: boolean
  roster: Seat[]
  /** uqbar's open session, if any (kit/uqbar.ts): lifted out of the roster by viewOf, so it never gets a desk */
  uqbar?: Seat | null
  /** every open thread, newest first; a staffed one carries its roster entry */
  threads: Thread[]
  counts: Record<string, number>
  awaiting: number
  bench: Coworker[]
  projects: { id: number; workspace_id: number; name: string }[]
  tickets: Ticket[]
  /** `shift` is the crew on now (`Server.Shifts`); absent from an older server */
  workspaces: { id: number; name: string; shift?: "day" | "night" }[]
  /** the shift board: every seat, both crews, each on `day`, `night` or `all` (both) */
  shifts?: { workspace_id: number; seat_id: number; name: string; archetype: string | null; crew: "all" | "day" | "night" }[]
  archetypes: Archetype[]
  models: ModelChoice[]
  notes: Note[]
  visits: Visit[]
  /** each workspace's count of stuck things (blockers, failed checks, unled threads), by id */
  triage: Record<string, number>
  /** the service's health: `warn` with the problems named */
  health: { state: "ok" | "warn"; problems: string[] } | null
  /** the days this month each workspace has something scheduled, by id (the wall calendar) */
  calendar: Record<string, number[]>
  /** the weather outside, as the room draws it (`Server.Office.Weather`); null when unknown */
  weather?: { kind: "clear" | "partly" | "cloudy" | "fog" | "rain" | "snow" | "storm"; temp_c: number | null; desc: string } | null
  /** today's birthdays and anniversaries from the calendar feeds (`Server.Calendar`): bunting, a cake, a crowd */
  celebrations?: { title: string; kind: "birthday" | "anniversary" }[]
  /** the office code's revision on main: a TUI started on another offers a reload (`Server.Rollout`) */
  revs?: { office: string | null }
  /** the server's feature flags by name (`Server.Flags`): what the office shows of work that lands dark */
  flags?: Record<string, boolean>
  /** the life side per `home` workspace id (`Server.Office.status`); absent for every other workspace */
  life?: Record<string, LifeSummary>
  note?: string
}
/** a flag from the snapshot, never from anywhere else; one it doesn't name is off */
export const flagOn = (a: Agents, name: string): boolean => a.flags?.[name] === true
/** one thing a coworker did on a thread (`Server.Presence.Thinking`'s feed): a tool call ("Bash · mise run check"), a post, or `thinking` as a turn starts */
export type Activity = { thread_id: number; agent: string; at: string; kind: string; summary: string }
/** a thread for a close look: a page of its messages (`more`: older ones remain), what its worker's pane shows now, and its activity feed, oldest first */
export type ThreadView = { messages: { id: number; author: string; body: string; at: string; kind: string; reply_to?: number | null }[]; more?: boolean; peek: string | null; window: string | null; activity?: Activity[] }

export const EMPTY: Agents = { ok: false, roster: [], threads: [], counts: {}, awaiting: 0, bench: [], projects: [], tickets: [], workspaces: [], archetypes: [], models: [], notes: [], visits: [], triage: {}, health: null, calendar: {} }
