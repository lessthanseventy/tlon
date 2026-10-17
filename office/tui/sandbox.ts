// The sandbox: a made-up world for the TUI to run on with no server (`office --sandbox`) — the toy
// in docs/plans/2026-10-08-office-as-a-toy-design.md §1. Same sim, same rooms; only the snapshot's source differs.
import { hints } from "./keys"
import { EMPTY, type Agents, type Ticket, type Visit } from "../kit/types"

const NAMES = ["scharlach", "tertius", "hronir", "lonnrot", "yu", "beatriz", "nolan", "emma", "ireneo", "daneri", "sonny"]
const TITLES = ["the doorbell", "teach Nina to code", "a fire drill, but gentle", "the great sticky-note audit"]
const WEATHER = [
  { kind: "clear", desc: "Clear", temp_c: 21 }, { kind: "partly", desc: "Partly cloudy", temp_c: 18 },
  { kind: "cloudy", desc: "Overcast", temp_c: 14 }, { kind: "fog", desc: "Fog", temp_c: 9 },
  { kind: "rain", desc: "Rain", temp_c: 11 }, { kind: "snow", desc: "Snow", temp_c: -2 },
  { kind: "storm", desc: "Thunderstorm", temp_c: 16 },
] as const

/** two filed tickets, so the toy's board has something to click on */
const TICKETS: Ticket[] = [
  { id: 201, workspace_id: 1, project_id: null, title: "teach the doorbell to ring twice", priority: "normal" },
  { id: 202, workspace_id: 1, project_id: null, title: "a plant for the server closet", priority: "low" },
]
const ago = (min: number) => new Date(Date.now() - min * 60_000).toISOString()

const knob = (key: string, type: string, value: number | boolean, doc: string, boot: boolean, min?: number, max?: number) => ({ key, type, value, default: value, min, max, boot, doc })

/** what the toy answers a card's read with (GET `/api<path>`), or undefined for a path it has nothing for */
function answer(path: string): unknown {
  const p = path.split("?")[0]!
  if (/^\/office\/threads\/\d+$/.test(p)) return { messages: [], peek: null, window: null }
  if (/^\/office\/triage\/\d+$/.test(p)) return {
    blockers: { shown: [{ thread_id: 100, title: "the sheriff's beat", text: "the build is red on main", issue_id: 7, found_by: "scharlach", created_at: ago(95), summary: "the build is red on main", evidence: "mix test: 3 failures in Server.Office.RoomTest\nfirst red at 4:04" }], more: 0 },
    failed_checks: { shown: [{ thread_id: 101, title: "a ticket at verify", text: "mix test", check_id: 9, slug: "workline:t:verify", stage: "verify" }], more: 0 },
    unled: { shown: [{ thread_id: 102, title: "an orphan thread", text: "nobody leads it" }], more: 0 }, count: 3,
  }
  if (/^\/office\/toys\/\d+$/.test(p)) return {
    visitors: [{ name: "Mr. Plover", look_seed: "plover", line: "Is this the room with the ducks?" }, { name: "Dr. Ismene", look_seed: "ismene", line: "I am here about the aquarium. It is calling." }],
    puns: ["I would tell you a UDP joke, but you might not get it."],
    reactions: { tertius: { fire_drill: ["Calmly. Calmly. Run."], duck: ["That is not in the runbook."] } },
  }
  if (p === "/office/health") return { state: "ok", problems: [], version: "toy", up_s: 7200, db: true, jobs: true, failed_jobs: 0, tmux: true, disk_pct: 41, mem_pct: 37, load: 0.4, checks: { running: null, waiting: [] }, merge_queue: [] }
  if (/^\/office\/memory\/\d+$/.test(p)) return {
    pinned: [{ id: 1, text: "Nina is not allowed on the keyboard." }, { id: 2, text: "The doorbell rings at the worst moment, on purpose." }],
    habits: [{ id: 1, text: "Check the server closet before a fire drill.", rationale: null, by: "scharlach" }],
    coverage: { facts: 6, embedded: 6, pinned_count: 2, pinned_tokens: 24, budget: 2000 },
  }
  if (/^\/office\/tickets\/\d+$/.test(p)) return TICKETS.map((t) => ({ id: t.id, title: t.title, body: null, status: "todo", priority: t.priority, project_id: null, blocked_by: [] }))
  if (/^\/office\/workspace\/\d+$/.test(p)) return { id: 1, name: "Toy", type: "code", scope: "workspace", icon: null, repos: [{ id: 1, path: "~/projects/toy", remote: null }] }
  if (p === "/settings") return { restart_pending: false, knobs: [
    knob("warm_minutes", "int", 20, "how long a session stays warm", false, 1, 240),
    knob("banter", "bool", true, "small talk between coworkers", false),
    knob("port", "int", 4040, "where the server listens", true, 1024, 65535),
  ] }
  if (/^\/office\/schedules\/\d+$/.test(p)) return [
    { id: 1, kind: "agent", title: "water the plants", body: "", cron: "0 9 * * 1", at: null, agent: "tertius", standing: true, thread_id: null, dir: null, enabled: true, next_at: ago(-60 * 20), days: [], last: null },
    { id: 2, kind: "script", title: "tidy the sticky notes", body: "", cron: "0 17 * * 5", at: null, agent: null, standing: false, thread_id: null, dir: null, enabled: false, next_at: null, days: [], last: null },
  ]
  if (/^\/office\/archive\/\d+$/.test(p)) return {
    tickets: [{ id: 190, title: "paint the lounge", closed_at: ago(60 * 24 * 3) }],
    threads: [{ id: 99, title: "the first fire drill", stage: "done", at: ago(60 * 24 * 5) }],
  }
  if (/^\/threads\/\d+\/review$/.test(p)) return { head: "toy", files: [{ path: "doorbell.ts", status: "modified", added: 1, deleted: 1, binary: false, hunks: [{ header: "@@ -1,2 +1,2 @@", lines: [
    { kind: " ", old: 1, new: 1, text: "export const ring = () => {" }, { kind: "-", old: 2, new: null, text: "  ding()" }, { kind: "+", old: null, new: 2, text: "  ding(); dong()" }] }] }] }
  return undefined
}

const NOTES = ["doorbell: the bell rattles", "nina: no more keyboard", "tv: a channel for releases", "uqbar: footnotes get numbers", "crew: one word for a seat", "door: a pool of guests"]

export function toy() {
  let w = 0, night = false, visits: Visit[] = [], who = 0, cuts = 0
  const hired = new Set<string>()
  const front = { id: 100, title: "lobby", stage: null, awaiting: null, workspace_id: 1, lead: null, live: false, standing: true }
  const threads = TITLES.map((title, i) => ({ id: 101 + i, title, stage: i % 2 ? "build" : "plan", awaiting: null, workspace_id: 1, lead: NAMES[1 + i]!, live: true, seat: "desk" as const }))
  const bench: Agents["bench"] = NAMES.map((name, i) => ({ workspace_id: 1, seat_id: i + 1, agent_id: i + 1, name, archetype: name === "scharlach" ? "sheriff" : "builder", lead: i === 1, model: null, ask: null }))
  const roster = threads.map((t) => ({ agent: t.lead, thread_id: t.id, title: t.title, warm: true, thinking: t.id % 2 === 0, workspace_id: 1 }))
  return {
    /** a card's read: the toy's small plausible data, or undefined (a 404) */
    read: (path: string) => answer(path),
    snapshot(): Agents {
      const shifts = bench.map((b, i) => ({ workspace_id: 1, seat_id: b.seat_id, name: b.name, archetype: b.archetype, crew: (hired.has(b.name) ? "all" : i < 6 ? "day" : "night") as "day" | "night" | "all" }))
      return { ...EMPTY, ok: true, tickets: TICKETS, workspaces: [{ id: 1, name: "Toy", shift: "day" as const }], shifts, archetypes: [{ name: "builder", meta: false, read_only: false, model: "anthropic/claude-sonnet" }, { name: "sheriff", meta: false, read_only: true, model: "anthropic/claude-haiku" }], bench, threads: [front, ...threads], roster, weather: { ...WEATHER[w]! }, visits, release: cuts ? { sha: `${(0x650fa4a + cuts * 0x1111).toString(16).padStart(7, "0")}beef`, cut_at: new Date().toISOString(), notes: NOTES.slice(0, 2 + cuts % 5) } : null }
    },
    /** the hall's hire: a pretend seat on the bench, on shift for everyone */
    hire(c: { name: string; archetype: string }) {
      if (bench.some((b) => b.name === c.name)) return
      const id = Math.max(...bench.map((b) => b.seat_id)) + 1
      hired.add(c.name)
      bench.push({ workspace_id: 1, seat_id: id, agent_id: id, name: c.name, archetype: c.archetype, lead: false, model: null, ask: null })
    },
    nextWeather() { w = (w + 1) % WEATHER.length },
    /** a pretend release: the next snapshot carries a new sha and its notes */
    cut() { cuts++ },
    /** someone else walks over to `to` (the sim reads a visit younger than a minute) */
    callOver(to: string) {
      const from = NAMES.filter((n) => n !== to)[who++ % (NAMES.length - 1)]!
      visits = [{ from, to, workspace_id: 1, at: new Date().toISOString() }]
    },
    toggleNight() { night = !night },
    now(): Date { const d = new Date(); if (night) d.setHours(23, 0, 0, 0); return d },
  }
}
export type Toy = ReturnType<typeof toy>

/** the sandbox's play keys, as the help line lists them; `toyKey()` in main.ts handles each */
export const PLAY = hints("sandbox-play")
/** off the sandbox, `E` alone fires an event (OFFICE_TOY_KEYS=1), and only where the card has no `E` of its own */
export const toyEventKey = (k: string, cardClaimsE: boolean, env: Record<string, string | undefined> = process.env): boolean =>
  k === "E" && !cardClaimsE && env.OFFICE_TOY_KEYS === "1"
