// The toy's scripted happenings (design §3): a table of scripts and the pure props each draws. Sim runs
// one at a time (`Sim.event`); nothing here reads a snapshot, a thread or the db — an event is the room's own.
import type { Pt } from "./sim"

export type EventKind = "drill" | "zoo" | "meteor" | "power" | "duck"
export const EVENT_KINDS: EventKind[] = ["drill", "zoo", "meteor", "power", "duck"]

/** a line or a glyph at tick `at` of the event, for `who`: the sheriff, the first idle coworker, or everyone idle */
export type Beat = { at: number; who: "sheriff" | "first" | "idle"; say?: string; emote?: string }
export type Script = { ticks: number; beats: Beat[] }

export const EVENTS: Record<EventKind, Script> = {
  drill: { ticks: 600, beats: [{ at: 0, who: "sheriff", say: "Fire drill! Everyone out!" }] },
  zoo: { ticks: 1200, beats: [] },
  meteor: {
    ticks: 700,
    beats: [{ at: 60, who: "idle", emote: "!" }, { at: 150, who: "first", say: "…was that the deploy?" }],
  },
  power: {
    ticks: 700,
    beats: [{ at: 100, who: "first", say: "Was that the breaker?" }, { at: 640, who: "idle", emote: "♪" }],
  },
  duck: { ticks: 500, beats: [{ at: 200, who: "idle", emote: "?" }] },
}

/** where the scenes happen, in room pixels; a room that has no door has no geometry and no events */
export type Geo = { doorX: number; hallY: number; ceilY: number; leftX: number; windowX: number; cork?: Pt }

export type PropKind = "van" | "monkey" | "penguin" | "goat" | "duck" | "streak" | "puff" | "crater" | "candle" | "net"
export type Prop = { kind: PropKind; x: number; y: number; flip?: boolean; step?: number }

/** a roll in [0, 1) → a kind that is not `last` */
export function pickEvent(roll: number, last: EventKind | null): EventKind {
  const from = EVENT_KINDS.filter((k) => k !== last)
  return from[Math.min(from.length - 1, Math.floor(roll * from.length))]!
}

const lerp = (a: number, b: number, t: number) => Math.round(a + (b - a) * Math.max(0, Math.min(1, t)))

/** what is on the stage at tick `t` of `kind` — pure; `[]` outside the event */
export function propsAt(kind: EventKind, t: number, g: Geo): Prop[] {
  if (t < 0 || t >= EVENTS[kind].ticks) return []
  switch (kind) {
    case "duck": {
      // in at the door (0-120), across the hall (120-300), a look round (300-380), back out (380-500)
      const x =
        t < 120
          ? lerp(g.doorX, g.doorX - 30, t / 120)
          : t < 300
            ? lerp(g.doorX - 30, g.leftX + 80, (t - 120) / 180)
            : t < 380
              ? g.leftX + 80
              : lerp(g.leftX + 80, g.doorX, (t - 380) / 120)
      const flip = t >= 380 || (t >= 300 && Math.floor((t - 300) / 20) % 2 === 1)
      return [{ kind: "duck", x, y: g.hallY, flip, step: Math.floor(t / 6) % 2 }]
    }
    case "meteor": {
      if (t >= 60 && t < 140) return [{ kind: "streak", x: lerp(g.windowX + 28, g.windowX + 4, (t - 60) / 80), y: lerp(8, 34, (t - 60) / 80) }]
      if (t < 140 || t >= EVENTS.meteor.ticks - 60) return []
      return [{ kind: t < 160 ? "puff" : "crater", x: g.doorX - 60, y: g.hallY }]
    }
    default:
      return []
  }
}

/** the power cut: lamps out from its 100th tick until the last 60 */
export const blackoutAt = (kind: EventKind, t: number): boolean =>
  kind === "power" && t >= 100 && t < EVENTS.power.ticks - 60

/** the meteor's flicker: null when it isn't one; else alternately lit / unlit every 8 ticks between 60 and 140 */
export const flickerAt = (kind: EventKind, t: number): boolean | null =>
  kind === "meteor" && t >= 60 && t < 140 ? Math.floor((t - 60) / 8) % 2 === 0 : null
