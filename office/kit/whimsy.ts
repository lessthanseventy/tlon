// The wackiness dial (toy design §7): one preset over individual dials; an override beats the preset.
// State is {mode, preset, overrides}; "custom" is derived, so a held override can't be lost by bookkeeping.
import { EVENT_KINDS, type EventKind } from "./events"

export type Preset = "business" | "casual" | "party" | "rimworld"
export const PRESET_IDS: Preset[] = ["business", "casual", "party", "rimworld"]
export type Freq = "never" | "rare" | "some" | "lots"
export type Weird = "curated" | "procedural" | "invented"
export type Dials = {
  banter: boolean
  frequency: Freq
  severity: 1 | 2 | 3
  chain: boolean
  events: Record<EventKind, boolean>
  weirdness: Weird
  pets: boolean
  doorbell: "off" | "normal" | "busy"
  souls: boolean
  moods: boolean
}
export type State = { mode: "office" | "sandbox"; preset: Preset; overrides: Partial<Dials> }

const allOn = Object.fromEntries(EVENT_KINDS.map((k) => [k, true])) as Record<EventKind, boolean>
const allOff = Object.fromEntries(EVENT_KINDS.map((k) => [k, false])) as Record<EventKind, boolean>

export const PRESETS: Record<Preset, Dials> = {
  business: { banter: false, frequency: "never", severity: 1, chain: false, events: allOff, weirdness: "curated", pets: false, doorbell: "off", souls: false, moods: false },
  casual: { banter: true, frequency: "some", severity: 1, chain: false, events: allOn, weirdness: "curated", pets: true, doorbell: "normal", souls: true, moods: false },
  party: { banter: true, frequency: "lots", severity: 2, chain: false, events: allOn, weirdness: "invented", pets: true, doorbell: "busy", souls: true, moods: false },
  rimworld: { banter: true, frequency: "lots", severity: 3, chain: true, events: allOn, weirdness: "invented", pets: true, doorbell: "busy", souls: true, moods: true },
}
export const DEFAULT: State = { mode: "office", preset: "casual", overrides: {} }

export function resolve(s: State): Dials {
  const b = PRESETS[s.preset]
  const o = s.overrides
  return { ...b, ...o, events: { ...b.events, ...(o.events ?? {}) } }
}
export const isCustom = (s: State) => Object.keys(s.overrides).length > 0
export const setPreset = (s: State, preset: Preset): State => ({ ...s, preset, overrides: {} })
export function setDial<K extends keyof Dials>(s: State, k: K, v: Dials[K]): State {
  const same = JSON.stringify(PRESETS[s.preset][k]) === JSON.stringify(v)
  const { [k]: _gone, ...rest } = s.overrides
  return { ...s, overrides: same ? rest : { ...rest, [k]: v } }
}

/** mean ticks (100 ms) between spontaneous events; never = Infinity */
export const meanGap = (f: Freq): number => ({ never: Infinity, rare: 200_000, some: 72_000, lots: 12_000 })[f]

const isFreq = (x: unknown): x is Freq => x === "never" || x === "rare" || x === "some" || x === "lots"
const isWeird = (x: unknown): x is Weird => x === "curated" || x === "procedural" || x === "invented"

/** office.json text → state; every field falls back to its default on its own */
export function parse(text: string): State {
  let j: any
  try {
    j = JSON.parse(text)
  } catch {
    return DEFAULT
  }
  if (!j || typeof j !== "object") return DEFAULT
  const o: Partial<Dials> = {}
  const r = j.overrides && typeof j.overrides === "object" ? j.overrides : {}
  if (typeof r.banter === "boolean") o.banter = r.banter
  if (isFreq(r.frequency)) o.frequency = r.frequency
  if (r.severity === 1 || r.severity === 2 || r.severity === 3) o.severity = r.severity
  if (typeof r.chain === "boolean") o.chain = r.chain
  if (isWeird(r.weirdness)) o.weirdness = r.weirdness
  if (typeof r.pets === "boolean") o.pets = r.pets
  if (r.doorbell === "off" || r.doorbell === "normal" || r.doorbell === "busy") o.doorbell = r.doorbell
  if (typeof r.souls === "boolean") o.souls = r.souls
  if (typeof r.moods === "boolean") o.moods = r.moods
  if (r.events && typeof r.events === "object") {
    const e: Partial<Record<EventKind, boolean>> = {}
    for (const k of EVENT_KINDS) if (typeof r.events[k] === "boolean") e[k] = r.events[k]
    if (Object.keys(e).length) o.events = e as Record<EventKind, boolean>
  }
  return {
    mode: j.mode === "sandbox" ? "sandbox" : "office",
    preset: PRESET_IDS.includes(j.preset) ? j.preset : "casual",
    overrides: o,
  }
}
