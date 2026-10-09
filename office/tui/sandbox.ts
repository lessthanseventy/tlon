// The sandbox: a made-up world for the TUI to run on with no server (`office --sandbox`) — the toy
// in docs/plans/2026-10-08-office-as-a-toy-design.md §1. Same sim, same rooms; only the snapshot's source differs.
import { EMPTY, type Agents, type Visit } from "../kit/types"

const NAMES = ["scharlach", "tertius", "hronir", "lonnrot", "yu", "beatriz", "nolan", "emma", "ireneo", "daneri", "sonny"]
const TITLES = ["the doorbell", "teach Nina to code", "a fire drill, but gentle", "the great sticky-note audit"]
const WEATHER = [
  { kind: "clear", desc: "Clear", temp_c: 21 }, { kind: "partly", desc: "Partly cloudy", temp_c: 18 },
  { kind: "cloudy", desc: "Overcast", temp_c: 14 }, { kind: "fog", desc: "Fog", temp_c: 9 },
  { kind: "rain", desc: "Rain", temp_c: 11 }, { kind: "snow", desc: "Snow", temp_c: -2 },
  { kind: "storm", desc: "Thunderstorm", temp_c: 16 },
] as const

export function toy() {
  let w = 0, night = false, visits: Visit[] = [], who = 0
  const threads = TITLES.map((title, i) => ({ id: 101 + i, title, stage: i % 2 ? "build" : "plan", awaiting: null, workspace_id: 1, lead: NAMES[1 + i]!, live: true, seat: "desk" as const }))
  const bench = NAMES.map((name, i) => ({ workspace_id: 1, seat_id: i + 1, agent_id: i + 1, name, archetype: name === "scharlach" ? "sheriff" : "builder", lead: i === 1, model: null, ask: null }))
  const roster = threads.map((t) => ({ agent: t.lead, thread_id: t.id, title: t.title, warm: true, thinking: t.id % 2 === 0, workspace_id: 1 }))
  return {
    snapshot(): Agents {
      return { ...EMPTY, ok: true, workspaces: [{ id: 1, name: "Toy" }], archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }, { name: "sheriff", meta: false, read_only: true, model: "" }], bench, threads, roster, weather: { ...WEATHER[w]! }, visits }
    },
    nextWeather() { w = (w + 1) % WEATHER.length },
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
export const PLAY: { key: string; label: string }[] = [
  { key: "d", label: "doorbell" }, { key: "e", label: "event" }, { key: "t", label: "treat" }, { key: "f", label: "fire drill" },
  { key: "n", label: "night" }, { key: "w", label: "weather" }, { key: "p", label: "pet" }, { key: "c", label: "call over" },
]
