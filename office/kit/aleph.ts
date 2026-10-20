// The Aleph (Server.Aleph): called in on a thread, never seated. Its own words for itself: a sphere,
// cyan core and violet rim, with one amber point inside that shows a different spot of the room
// every few frames. It rises out of the floor when called, hangs above the card it was called to
// while it works (the point slowing, then settling), and shrinks to a pixel and goes out when done.
import type { Scene } from "./draw"
import { ROLE } from "./palette"

export type Pt = { x: number; y: number }
/** one visit: the thread it was called to, when it came, when it began to leave (null while it works) */
export type Visit = { tid: number; since: number; leaving: number | null }

export const ARRIVE = "I have seen everything. Show me where it bends."
export const LEAVE = "It was all here. You were standing in the wrong place."
/** ticks per frame of its arrival and its leaving (three frames each) */
export const STEP = 3
/** ticks until the amber point settles on the card */
const SETTLE = 120

const SPHERE = ["..vvv..", ".vcccv.", "vcccccv", "vcccccv", "vcccccv", ".vcccv.", "..vvv.."]
const SMALL = [".v.", "vcv", ".v."]
const CORE: Pt[] = SPHERE.flatMap((row, y) => [...row].flatMap((ch, x) => (ch === "c" ? [{ x, y }] : [])))

/** where the amber point is at `tick`: hopping while it reads, slower as it settles, still at the bottom once settled */
export function pointAt(v: Visit, tick: number): Pt {
  const age = tick - v.since
  if (age >= SETTLE) return { x: 3, y: 4 }
  const every = age < SETTLE / 2 ? 4 : 12
  const k = Math.floor(tick / every)
  return CORE[((k * 2654435761) >>> 0) % CORE.length]!
}

/** whether a visit that began leaving at `leaving` is over by `tick` */
export const gone = (v: Visit, tick: number) => v.leaving !== null && tick - v.leaving >= STEP * 3

/** draw a visit hanging over `at` (the card's spot): rising out of the floor, working, or leaving */
export function drawAleph(sc: Scene, v: Visit, at: Pt) {
  const t = sc.tick, x = at.x - 3, y = at.y - 9
  const paint = { v: ROLE.assistant, c: ROLE.key }
  sc.overhead.push(() => {
    if (v.leaving !== null) {
      const f = Math.floor((t - v.leaving) / STEP)
      if (f === 0) sc.figure(SMALL, x + 2, y + 2, paint)
      else if (f === 1) sc.px(x + 3, y + 3, 1, 1, ROLE.key)
      return
    }
    const f = Math.floor((t - v.since) / STEP)
    if (f < 3) {
      // the floor opens under it, and it rises out of it
      sc.px(x + 2, y + 9, 3, 3, ROLE.ground)
      sc.figure(SPHERE.slice(0, (f + 1) * 2 + 1), x, y + 6 - f * 3, paint)
      return
    }
    sc.figure(SPHERE, x, y, paint)
    const p = pointAt(v, t)
    sc.px(x + p.x, y + p.y, 1, 1, ROLE.body)
  })
}
