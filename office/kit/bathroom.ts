// The bathroom: a room of its own in the bottom-left corner, walled off from your office, its door
// on the hallway. Its geometry, Nina's wet pawprints and how they fade, and when the door stands
// open. Pure — the sim lays and prunes prints, the tile draws them.
import type { Pt } from "./sim"

/** the room, walls included: from the floor's left edge to just short of your office's lane, down to the hall runner */
export const BATH = { x: 0, y: 152, w: 62, h: 33 }
/** the gap in the bottom wall, in line with the sink's spot: where the room meets the hall runner */
export const DOOR = { x: 34, y: BATH.y + BATH.h }
/** the tub's front rim, where she sits to drink, and the floor in front of it she hops up from */
export const RIM = { x: 18, y: 170 }
export const RIM_FLOOR = { x: 18, y: 177 }
/** where she curls up in the (dry) tub, hopped into from the same floor */
export const TUB_IN = { x: 11, y: 168 }
/** where a coworker stands at the sink */
export const SINK = { x: 34, y: 176 }
/** ticks (100 ms) a print lasts: a minute; she fell in, a good while longer */
export const LIFE = 600
export const FALL_LIFE = 1500
/** ticks the door stays open after someone was at it */
export const HOLD = 8
/** a pawprint every STRIDE pixels she walks while her paws are wet */
export const STRIDE = 6
/** ticks she drinks; ticks her paws stay wet after (more after a fall) */
export const DRINK = 60
export const WET = 240
export const FALL_WET = 700
/** the chance a drinking trip ends in the tub */
export const FALL_ODDS = 0.05

export type Print = { x: number; y: number; at: number; until: number }

export const layPrint = (x: number, y: number, at: number, fell: boolean): Print => ({ x, y, at, until: at + (fell ? FALL_LIFE : LIFE) })
/** 0 fresh … 2 nearly gone, 3 gone: thirds of the print's own life */
export function fadeStage(p: Print, tick: number): 0 | 1 | 2 | 3 {
  if (tick >= p.until) return 3
  return Math.floor(((tick - p.at) * 3) / (p.until - p.at)) as 0 | 1 | 2
}
export const prune = (ps: Print[], tick: number): Print[] => ps.filter((p) => tick < p.until)

/** the door is open while someone is within reach of it, and HOLD ticks after */
export function doorOpen(near: Pt[], tick: number, lastAt: number): boolean {
  if (near.some((p) => Math.abs(p.x - DOOR.x) <= 6 && Math.abs(p.y - DOOR.y) <= 6)) return true
  return tick - lastAt <= HOLD
}
