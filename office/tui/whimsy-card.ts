// The wackiness dial's card, as data: rows over kit/whimsy.ts. Pure, so it needs no terminal to test.
import { EVENT_KINDS } from "../kit/events"
import { PRESET_IDS, isCustom, resolve, setDial, setPreset, type Dials, type State } from "../kit/whimsy"

export type WhimsyRow = { label: string; value: string; note?: string; next: (s: State) => State }

const cycle = <T,>(vals: readonly T[], v: T): T => vals[(vals.indexOf(v) + 1) % vals.length]!
const onOff = (b: boolean) => (b ? "on" : "off")

export const whimsyTitle = (s: State) => `WACKINESS · ${s.preset}${isCustom(s) ? " (custom)" : ""}`
export const resetToPreset = (s: State): State => setPreset(s, s.preset)

export function whimsyRows(s: State): WhimsyRow[] {
  const d = resolve(s)
  const flip = (k: "banter" | "chain" | "pets" | "souls" | "moods", label = k as string): WhimsyRow =>
    ({ label, value: onOff(d[k]), next: (x) => setDial(x, k, !resolve(x)[k]) })
  const pick = <K extends "frequency" | "severity" | "weirdness" | "doorbell">(k: K, vals: readonly Dials[K][], note?: string): WhimsyRow =>
    ({ label: k, value: String(d[k]), note, next: (x) => setDial(x, k, cycle(vals, resolve(x)[k])) })
  return [
    { label: "preset", value: s.preset, next: (x) => setPreset(x, cycle(PRESET_IDS, x.preset)) },
    flip("banter"),
    pick("frequency", ["never", "rare", "some", "lots"]),
    pick("severity", [1, 2, 3]),
    flip("chain"),
    flip("pets"),
    pick("doorbell", ["off", "normal", "busy"]),
    flip("moods"),
    { ...flip("souls"), note: "off ignores the souls (no friends or rivals) and uses canned voices" },
    { ...pick("weirdness", ["curated", "procedural", "invented"]), note: "past curated: the server's generated visitors, puns and reactions" },
    ...EVENT_KINDS.map((k): WhimsyRow => ({
      label: `event: ${k}`, value: onOff(d.events[k]),
      next: (x) => setDial(x, "events", { ...resolve(x).events, [k]: !resolve(x).events[k] }),
    })),
  ]
}
