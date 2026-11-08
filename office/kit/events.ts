// The toy's scripted happenings (design §3): a table of scripts and the pure props each draws. Sim runs
// one at a time (`Sim.event`); nothing here reads a snapshot, a thread or the db — an event is the room's own.
import type { Pt } from "./sim"

export type EventKind = "drill" | "zoo" | "meteor" | "power" | "duck" | "gary" | "planes" | "pizza" | "nap"
export const EVENT_KINDS: EventKind[] = ["drill", "zoo", "meteor", "power", "duck", "gary", "planes", "pizza", "nap"]

/** a line or a glyph at tick `at` of the event, for `who`: the sheriff, the first idle coworker, or everyone idle; `react` asks each seat for its own line, staggered */
export type Beat = { at: number; who: "sheriff" | "first" | "idle"; say?: string; emote?: string; react?: true }
export type Script = { ticks: number; beats: Beat[] }

export const EVENTS: Record<EventKind, Script> = {
  drill: { ticks: 600, beats: [{ at: 0, who: "sheriff", say: "Fire drill! Everyone out!" }, { at: 60, who: "idle", react: true }] },
  zoo: {
    ticks: 1200,
    beats: [
      { at: 0, who: "idle", emote: "!" },
      { at: 300, who: "sheriff", say: "Order! ORDER!" },
      { at: 600, who: "first", say: "Who let them in?" },
      { at: 120, who: "idle", react: true },
    ],
  },
  meteor: {
    ticks: 700,
    beats: [{ at: 60, who: "idle", emote: "!" }, { at: 150, who: "first", say: "…was that the deploy?" }, { at: 100, who: "idle", react: true }],
  },
  power: {
    ticks: 700,
    beats: [{ at: 100, who: "first", say: "Was that the breaker?" }, { at: 640, who: "idle", emote: "♪" }, { at: 120, who: "idle", react: true }],
  },
  duck: { ticks: 500, beats: [{ at: 200, who: "idle", emote: "?" }, { at: 60, who: "idle", react: true }] },
  gary: { ticks: 540, beats: [{ at: 120, who: "idle", emote: "!" }, { at: 200, who: "first", say: "…did that dumpster just growl?" }, { at: 60, who: "idle", react: true }] },
  planes: { ticks: 600, beats: [{ at: 40, who: "idle", emote: "!" }, { at: 220, who: "first", say: "Who is folding all of these?" }, { at: 80, who: "idle", react: true }] },
  pizza: { ticks: 700, beats: [{ at: 20, who: "idle", emote: "♥" }, { at: 320, who: "first", say: "Whose hand is that on the whiteboard?" }, { at: 60, who: "idle", react: true }] },
  nap: { ticks: 700, beats: [{ at: 40, who: "first", say: "Ten minutes. Nobody tell the thread." }, { at: 300, who: "idle", emote: "z" }, { at: 100, who: "idle", react: true }] },
}

/** what a visit of Gary's comes to, rolled once per visit: a third each */
export type GaryRoll = "sandwich" | "sock" | "slap"
export const garyRoll = (roll: number): GaryRoll => (roll < 1 / 3 ? "sandwich" : roll < 2 / 3 ? "sock" : "slap")
/** the tick he acts on the roll (the SLAP lands, the sandwich goes, the sock drops); before it he growls, after it he is going back in */
export const GARY_ACT = 300
/** how long the SLAP spins its victim */
export const GARY_SPIN = 60

/** what an event can start when it ends under `chain` (rimworld), or in a chain reaction: Gary's dumpster brings the zoo van, the zoo starts the drill, which cuts the power, which panics the penguin */
export const CHAINS: Record<EventKind, EventKind[]> = { zoo: ["drill"], drill: ["power"], power: ["duck"], meteor: ["power"], duck: [], gary: ["zoo"], planes: [], pizza: ["nap"], nap: [] }

/** where the scenes happen, in room pixels; a room that has no door has no geometry and no events */
export type Geo = { doorX: number; hallY: number; ceilY: number; leftX: number; windowX: number; cork?: Pt; kitchen?: Pt; board?: Pt }

export type PropKind = "van" | "monkey" | "penguin" | "goat" | "duck" | "streak" | "puff" | "crater" | "candle" | "net" | "dumpster" | "gary" | "bone" | "sandwich" | "sock" | "stars" | "shout" | "mutter" | "cackle" | "paper" | "pizzabox" | "grease" | "zzz"
export type Prop = { kind: PropKind; x: number; y: number; flip?: boolean; step?: number; text?: string }

/** a roll in [0, 1) → a kind of `from` that is not `last` (the only enabled kind may repeat) */
export function pickEvent(roll: number, last: EventKind | null, from: EventKind[] = EVENT_KINDS): EventKind {
  const fresh = from.filter((k) => k !== last)
  const pool = fresh.length ? fresh : from
  return pool[Math.min(pool.length - 1, Math.floor(roll * pool.length))]!
}

const lerp = (a: number, b: number, t: number) => Math.round(a + (b - a) * Math.max(0, Math.min(1, t)))

/** what is on the stage at tick `t` of `kind` — pure; `[]` outside the event */
export function propsAt(kind: EventKind, t: number, g: Geo, severity: 1 | 2 | 3 = 1, gary: GaryOpts = {}): Prop[] {
  if (t < 0 || t >= EVENTS[kind].ticks) return []
  // a bigger event is more of it: later copies run 40 ticks behind and 14 px apart (the zoo adds only penguins; there is only one Gary and one counter of pizza)
  return Array.from({ length: kind === "gary" || kind === "pizza" ? 1 : severity }, (_, i) =>
    scene(kind, t - 40 * i, g, gary)
      .filter((p) => i === 0 || kind !== "zoo" || p.kind === "penguin")
      .map((p) => (i ? { ...p, x: p.x + 14 * i } : p)),
  ).flat()
}

/** a visit of Gary's: `peek` shows only the lid and the eyes; else `outcome` is what the roll came to */
export type GaryOpts = { outcome?: GaryRoll; peek?: boolean }

/** the dumpster's spot: just outside the door, in the hall */
const dumpsterAt = (g: Geo) => ({ x: g.doorX - 24, y: g.hallY })

/** Gary at tick `t` of his visit: lid up and eyes (60), out with the fish bone (60-120), the mutter, the outcome at GARY_ACT, back in by 500 */
function garyScene(t: number, g: Geo, { outcome = "slap", peek = false }: GaryOpts): Prop[] {
  const d = dumpsterAt(g), ticks = EVENTS.gary.ticks
  const out: Prop[] = [{ kind: "dumpster", x: d.x, y: d.y, step: t >= 40 && t < ticks - 40 ? 1 : 0 }]
  if (peek) return out
  const home = d.x - 14, gone = 500
  if (t >= 60 && t < gone) {
    const x = t < 120 ? lerp(d.x, home, (t - 60) / 60) : t < 440 ? home : lerp(home, d.x, (t - 440) / 60)
    out.push({ kind: "gary", x, y: d.y, flip: true, step: Math.floor(t / 8) % 2 })
    if (t >= 100 && t < 440) out.push({ kind: "bone", x: x - 6, y: d.y - 4, flip: true, step: Math.floor(t / 6) % 2 })
    if (t >= 120 && t < GARY_ACT - 5) out.push({ kind: "mutter", x, y: d.y - 24, text: "I WILL END YOU, and then I will eat your yogurt" })
    if (t >= GARY_ACT && outcome === "sandwich") out.push({ kind: "sandwich", x: x - 8, y: d.y - 6 })
    if (outcome === "slap" && t >= GARY_ACT && t < GARY_ACT + 80) out.push({ kind: "shout", x, y: d.y - 30, text: "SLAP!" })
    if (outcome === "slap" && t >= GARY_ACT + 80 && t < 440) out.push({ kind: "cackle", x, y: d.y - 24, text: "HEHEHE" })
  }
  if (outcome === "sock" && t >= GARY_ACT) out.push({ kind: "sock", x: home - 4, y: d.y })
  return out
}

/** the zoo's parade in rimworld has Gary at its head: a step ahead of the penguin, whichever way it walks */
export function garyLeads(kind: EventKind, t: number, g: Geo): Prop[] {
  const pen = kind === "zoo" ? propsAt("zoo", t, g).find((p) => p.kind === "penguin") : undefined
  return pen ? [{ kind: "gary", x: pen.x + (pen.flip ? 16 : -16), y: pen.y, flip: !pen.flip, step: pen.step }] : []
}

function scene(kind: EventKind, t: number, g: Geo, gary: GaryOpts): Prop[] {
  if (t < 0) return []
  switch (kind) {
    case "gary":
      return garyScene(t, g, gary)
    case "duck": {
      // in at the door (0-120), across the whole hall to its left wall (120-300), a look round (300-380), back out (380-500)
      const far = 12
      const x =
        t < 120
          ? lerp(g.doorX, g.doorX - 30, t / 120)
          : t < 300
            ? lerp(g.doorX - 30, far, (t - 120) / 180)
            : t < 380
              ? far
              : lerp(far, g.doorX, (t - 380) / 120)
      const flip = t >= 380 || (t >= 300 && Math.floor((t - 300) / 20) % 2 === 1)
      return [{ kind: "duck", x, y: g.hallY, flip, step: Math.floor(t / 6) % 2 }]
    }
    case "meteor": {
      if (t >= 60 && t < 140) return [{ kind: "streak", x: lerp(g.windowX + 28, g.windowX + 4, (t - 60) / 80), y: lerp(8, 34, (t - 60) / 80) }]
      if (t < 140 || t >= EVENTS.meteor.ticks - 60) return []
      // it lands in the street seen through the window, where the streak stopped — the room has no street of its own
      return [{ kind: t < 160 ? "puff" : "crater", x: g.windowX + 8, y: 35 }]
    }
    case "zoo": {
      const out: Prop[] = []
      const vanX = g.doorX - 8
      out.push({ kind: "van", x: t < 60 ? lerp(g.doorX + 80, vanX, t / 60) : t < 1100 ? vanX : lerp(vanX, g.doorX + 80, (t - 1100) / 100), y: g.hallY })
      if (t >= 60 && t < 1100) {
        const px = t < 600 ? lerp(g.doorX, g.leftX + 40, (t - 60) / 540) : lerp(g.leftX + 40, g.doorX, (t - 600) / 500)
        out.push({ kind: "penguin", x: px, y: g.hallY, flip: t >= 600, step: Math.floor(t / 8) % 2 })
      }
      if (t >= 60 && t < 1000) out.push({ kind: "monkey", x: g.leftX - ((Math.floor(t / 10) * 17) % 300), y: g.ceilY, step: Math.floor(t / 10) % 2 })
      if (t >= 60 && t < 1100 && g.cork) {
        const up = g.hallY - (g.cork.y + 22)
        const x = t < 300 ? lerp(g.doorX, g.cork.x, (t - 60) / 240) : t < 800 ? g.cork.x : lerp(g.cork.x, g.doorX, (t - 800) / 300)
        const y = t < 300 ? g.hallY : t < 400 ? g.hallY - lerp(0, up, (t - 300) / 100) : t < 700 ? g.hallY - up : t < 800 ? g.hallY - lerp(up, 0, (t - 700) / 100) : g.hallY
        out.push({ kind: "goat", x, y, flip: t >= 800, step: t >= 400 && t < 700 ? Math.floor(t / 6) % 2 : Math.floor(t / 8) % 2 })
      }
      return out
    }
    case "planes":
      return planesScene(t, g)
    case "pizza":
      return pizzaScene(t, g)
    default:
      return []
  }
}

/** the paper-plane storm: PLANE_COUNT sheets cross the hall right to left, one every PLANE_GAP ticks; the PLANE_CAUGHT-th hangs at `planeCatch` for a moment and is gone */
export const PLANE_COUNT = 6, PLANE_GAP = 70, PLANE_FLIGHT = 220, PLANE_CAUGHT = 2
/** where Argos jumps for his plane */
export const planeCatch = (g: Geo): Pt => ({ x: g.doorX - 90, y: g.hallY - 26 })
function planesScene(t: number, g: Geo): Prop[] {
  const out: Prop[] = []
  for (let i = 0; i < PLANE_COUNT; i++) {
    const age = t - 30 - i * PLANE_GAP
    if (age < 0 || age >= PLANE_FLIGHT) continue
    const row = g.hallY - 50 - 10 * (i % 3), bob = Math.round(4 * Math.sin(age / 9)), step = Math.floor(age / 6) % 2
    if (i === PLANE_CAUGHT) {
      const c = planeCatch(g)
      if (age >= 134) continue
      out.push(age < 110 ? { kind: "paper", x: lerp(g.doorX, c.x, age / 110), y: lerp(row, c.y, age / 110) + bob, flip: true, step } : { kind: "paper", x: c.x, y: c.y, flip: true, step })
      continue
    }
    out.push({ kind: "paper", x: lerp(g.doorX, g.leftX, age / PLANE_FLIGHT), y: row + bob, flip: true, step })
  }
  return out
}

/** the pizza party: boxes on the kitchen counter that thin out as the crew eats, and from tick 300 a greasy handprint on the whiteboard */
function pizzaScene(t: number, g: Geo): Prop[] {
  const out: Prop[] = []
  const boxes = t < 60 ? 0 : t < 300 ? 3 : t < 450 ? 2 : t < 600 ? 1 : 0
  if (g.kitchen) for (let i = 0; i < boxes; i++) out.push({ kind: "pizzabox", x: g.kitchen.x, y: g.kitchen.y - 3 * i })
  if (g.board && t >= 300) out.push({ kind: "grease", x: g.board.x, y: g.board.y })
  return out
}

/** the power nap: the floor dims from its 60th tick until the last 60 */
export const dimAt = (kind: EventKind, t: number): boolean => kind === "nap" && t >= 60 && t < EVENTS.nap.ticks - 60

/** the power cut: lamps out from its 100th tick until the last 60 */
export const blackoutAt = (kind: EventKind, t: number): boolean =>
  kind === "power" && t >= 100 && t < EVENTS.power.ticks - 60

/** the meteor's flicker: null when it isn't one; else alternately lit / unlit every 8 ticks between 60 and 140 */
export const flickerAt = (kind: EventKind, t: number): boolean | null =>
  kind === "meteor" && t >= 60 && t < 140 ? Math.floor((t - 60) / 8) % 2 === 0 : null

/** the goat has the corkboard's first note between 450 and 700, then spits it back out */
export const noteEatenAt = (kind: EventKind, t: number): boolean => kind === "zoo" && t >= 450 && t < 700
