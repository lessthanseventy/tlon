// The server's office snapshot as `Server.Office.status` returns it (`GET /api/office`, and
// `scripts/tlon-cli.sh shell-status` for the desktop) — what every office surface reads.

/** `prompt`: its coworker is sitting on a dialog (Server.Attention) — the ask, answered from the thread */
/** `lead`: who it is staffed with; `live`: a tmux window is running it; `standing`: its workspace's lobby; `thinking`: who is mid-turn on it */
export type Thread = { id: number; title: string; stage: string | null; awaiting: string | null; workspace_id?: number | null; lead?: string | null; live?: boolean; standing?: boolean; thinking?: string[]; prompt?: { summary: string; options?: { key: string; label: string }[] | null } | null }
/** `archetype`/`lead`: the agent's seat on its workspace bench (null/false off every bench); `warm`: its session is recent; `thinking`: it is mid-turn (its harness said so); `doing`: the kind of tool running in that turn (read, edit, bash, search, web, test, delegate), null between tools */
export type Seat = { agent: string; thread_id: number; title: string; warm: boolean; thinking?: boolean; doing?: string | null; archetype?: string | null; lead?: boolean; workspace_id?: number | null }
/** a model as the server names it; `thinking` is the effort level */
export type ModelSpec = { provider: string; model: string; thinking: string }
/** a coworker a workspace employs, on a thread or not; `model`/`ask` are its policy, null = the archetype's */
export type Coworker = { workspace_id: number; seat_id: number; agent_id: number; name: string; archetype: string | null; lead: boolean; model: ModelSpec | null; ask: string | null }
/** what an archetype is beyond its prompt: `meta` never works a thread, `read_only` cannot write */
export type Archetype = { name: string; meta: boolean; read_only: boolean; model: string }
/** a model a coworker may run, keyed `provider/model`, with the harness it resolves to here */
export type ModelChoice = ModelSpec & { key: string; harness: string }
/** a note someone left (the whiteboard's strip); `workspace_id` null = machine-wide */
export type Note = { id: number; author: string; body: string; workspace_id: number | null; at: string }
/** a consult in the last few minutes: `from` asked `to` something */
export type Visit = { from: string; to: string; workspace_id: number; at: string }
/** a filed ticket nobody has started yet */
export type Ticket = { id: number; workspace_id: number; project_id: number | null; title: string; priority: string; routed?: boolean }
export type Agents = {
  ok: boolean
  roster: Seat[]
  /** every open thread, newest first; a staffed one carries its roster entry */
  threads: Thread[]
  counts: Record<string, number>
  awaiting: number
  bench: Coworker[]
  projects: { id: number; workspace_id: number; name: string }[]
  tickets: Ticket[]
  workspaces: { id: number; name: string }[]
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
  note?: string
}
/** a thread for a close look: a page of its messages (`more`: older ones remain), and what its worker's pane shows now */
export type ThreadView = { messages: { id: number; author: string; body: string; at: string; kind: string }[]; more?: boolean; peek: string | null; window: string | null }

export const EMPTY: Agents = { ok: false, roster: [], threads: [], counts: {}, awaiting: 0, bench: [], projects: [], tickets: [], workspaces: [], archetypes: [], models: [], notes: [], visits: [], triage: {}, health: null, calendar: {} }
