// A uqbar post as a paper aeroplane (docs/plans/2026-10-08-uqbar-design.md §3): a page tears out of
// the book, folds, glides leg by leg to its recipient, unfolds. Pure: the room owns where legs are.
import type { Scene } from "./draw"
import { ROLE } from "./palette"
import type { Pt } from "./uqbar"

export type Phase = "tear" | "fold" | "glide" | "unfold"
export type Leg = Pt & { hold?: number }
/** `at`: where it is; `t`: ticks in this phase; `legs`: still to fly; `hold`: ticks left to wait at the leg it reached */
export type Plane = { phase: Phase; t: number; at: Pt; legs: Leg[]; hold: number }
export const TEAR = 6, FOLD = 8, UNFOLD = 10, SPEED = 3

export const launch = (from: Pt, via: Leg[], to: Pt): Plane => ({ phase: "tear", t: 0, at: from, legs: [...via, to], hold: 0 })

/** one tick; null once it has unfolded */
export function stepPlane(p: Plane): Plane | null {
  switch (p.phase) {
    case "tear": return p.t + 1 >= TEAR ? { ...p, phase: "fold", t: 0 } : { ...p, t: p.t + 1 }
    case "fold": return p.t + 1 >= FOLD ? { ...p, phase: "glide", t: 0 } : { ...p, t: p.t + 1 }
    case "unfold": return p.t + 1 >= UNFOLD ? null : { ...p, t: p.t + 1 }
    case "glide": {
      if (p.hold > 0) return { ...p, hold: p.hold - 1 }
      const [leg, ...rest] = p.legs
      if (!leg) return { ...p, phase: "unfold", t: 0 }
      const dx = leg.x - p.at.x, dy = leg.y - p.at.y, d = Math.hypot(dx, dy)
      if (d <= SPEED) return { ...p, at: { x: leg.x, y: leg.y }, legs: rest, hold: leg.hold ?? 0 }
      return { ...p, at: { x: p.at.x + (dx / d) * SPEED, y: p.at.y + (dy / d) * SPEED } }
    }
  }
}

/** Argos catches every 4th plane of the room's life: no dice, so a seeded test sees the same dog */
export const caughtNth = (n: number) => n % 4 === 3

export type FeedRow = { kind: string; at: string; thread_id: number | null; who: string | null; text: string }
/** the feed's uqbar posts not seen yet, oldest first; marks every row seen. `first`: history, not news */
export function freshPosts(feed: FeedRow[], seen: Set<string>, first: boolean): FeedRow[] {
  const out: FeedRow[] = []
  for (const x of feed) {
    const k = `${x.at}${x.kind}${x.text}`
    if (seen.has(k)) continue
    seen.add(k)
    if (!first && x.kind === "message" && x.who === "uqbar" && x.thread_id !== null) out.push(x)
  }
  return out.reverse()
}

/** one char per pixel: p page, k ink. Two colours, at least 6 px wide: legible at a glance */
export const FRAMES = {
  sheet: ["pppppp", "pkkkkp", "pppppp", "pkkkkp", "pppppp", "pkkkpp"],
  folded: ["..pppp..", ".pkkkkp.", "pppppppp", ".pkkkkp.", "..pppp.."],
  plane: ["pp......", "pppp....", "kkpppppp", "pppppppp", "pp......", ".p......"],
  planeUp: ["........", "pp......", "pppp....", "kkpppppp", "pppppppp", "pp......"],
  unfold: ["pp....pp", ".pp..pp.", "..pppp..", "..pkkp..", ".pppppp.", "pp....pp"],
} as const

/** the page in flight: sheet while tearing, folding squeezes it, two glide frames, then it opens flat */
export function drawPlane(sc: Scene, p: Plane) {
  const frame =
    p.phase === "tear" ? FRAMES.sheet
    : p.phase === "fold" ? (p.t < FOLD / 2 ? FRAMES.sheet : FRAMES.folded)
    : p.phase === "glide" ? ((sc.tick >> 1) % 2 ? FRAMES.planeUp : FRAMES.plane)
    : FRAMES.unfold
  const x = Math.round(p.at.x), y = Math.round(p.at.y)
  sc.overhead.push(() => sc.blit([...frame], x, y, { p: ROLE.prose, k: ROLE.fieldInk }))
}
