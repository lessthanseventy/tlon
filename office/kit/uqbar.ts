// Uqbar, the volume (docs/plans/2026-10-08-uqbar-design.md §1–2): a small flying encyclopedia that is
// the operator's own Claude Code session. It has no desk and is not crew: asleep as one spine too
// many on the lounge shelf, and while a session is live, perched on its focus thread's whiteboard card.
// Sprites are one char per pixel: r cover, g gilt, p page, k ink, w ribbon.
import type { Scene } from "./draw"
import { ROLE, tint } from "./palette"
import type { Seat } from "./types"

export type Mood = "idle" | "working" | "shipped" | "failing"
export type Pt = { x: number; y: number }
/** x, y: top-left of the sprite's body in the room; `riffle`: ticks of page-fan left after takeoff */
export type Book = Pt & { flying: boolean; riffle: number }
export type Mode = "shelved" | "flying" | "perched"

export const FRAMES = {
  closed: ["rrrrrrrr", "rgrrggrr", "rgrrrrrr", "rgrrggrr", "rgrrrrrr", "rrrrrrrr", ".pppppp."],
  open: ["............", "............", "pppppppppppp", "pkpkpkkpkpkp", "pppppppppppp", "rrrrrrrrrrrr", "............", "............"],
  flapUp: ["pp........pp", "ppp......ppp", ".ppp.rr.ppp.", "..pp.rr.pp..", "....grrg....", "....grrg....", "....rrrr....", "............"],
  flapDown: ["............", "....rrrr....", "....grrg....", "..ppgrrgpp..", ".ppp.rr.ppp.", "ppp......ppp", "pp........pp", "............"],
  riffle: ["....pppp....", "..pppppppp..", ".pp.pppp.pp.", "pp..rrrr..pp", "....grrg....", "....grrg....", "....rrrr....", "............"],
} as const
/** the ribbon tail's colour is its state; read at draw time so a theme switch follows */
export const RIBBON: Record<Mood, () => string> = {
  idle: () => ROLE.assistant, working: () => ROLE.reviewer, shipped: () => ROLE.live, failing: () => ROLE.alarm,
}
const oxblood = () => tint(ROLE.alarm, ROLE.ground, 0.6)
const paint = (mood: Mood) => ({ r: oxblood(), g: ROLE.body, p: ROLE.prose, k: ROLE.fieldInk, w: RIBBON[mood]() })

const SPEED = 2, RIFFLE_TICKS = 6
export const moodOf = (s: Seat): Mood => (s.thinking ? "working" : "idle")

/** one tick toward `goal`: straight line, `SPEED` px; the first ticks after takeoff riffle */
export function stepBook(b: Book, goal: Pt): Book {
  const dx = goal.x - b.x, dy = goal.y - b.y, d = Math.hypot(dx, dy)
  if (d <= SPEED) return { x: goal.x, y: goal.y, flying: false, riffle: 0 }
  return { x: b.x + (dx / d) * SPEED, y: b.y + (dy / d) * SPEED, flying: true, riffle: b.flying ? Math.max(0, b.riffle - 1) : RIFFLE_TICKS }
}
export const modeOf = (b: Book, home: Pt): Mode => (b.flying ? "flying" : b.x === home.x && b.y === home.y ? "shelved" : "perched")
/** home asleep; else the focus card, else the whiteboard's edge (focus off the board or in another workspace) */
export function goalOf(session: Seat | null | undefined, cards: Map<number, Pt>, edge: Pt, home: Pt): Pt {
  return session ? cards.get(session.thread_id) ?? edge : home
}

/** 1 px nudge for 12 ticks every 180 s of room time (ticks are 100 ms) */
export function wiggle(tick: number): 0 | 1 {
  const t = tick % 1800
  return t < 12 && t % 4 >= 2 ? 1 : 0
}

/** the book's home: the 10th column of the shelf's top row */
export const spineHome = (shelf: { x: number; y: number }): Pt => ({ x: shelf.x + 20, y: shelf.y + 1 })

/**
 * The shelf with its one spine too many (faintly glowing, wiggling now and then) while the book is
 * shelved; the neighbouring spine lying flat while a session is live. Drawn just in front of the shelf.
 */
export function drawShelf(sc: Scene, shelf: { x: number; y: number; w: number; h: number }, shelved: boolean, live: boolean) {
  sc.item(shelf.y + shelf.h + 0.1, () => {
    if (live) {
      sc.px(shelf.x + 18, shelf.y + 2, 1, 5, ROLE.structure)
      sc.px(shelf.x + 14, shelf.y + 6, 5, 1, ROLE.live)
    }
    if (!shelved) return
    const h = spineHome(shelf), x = h.x + wiggle(sc.tick), glow = tint(ROLE.assistant, ROLE.structure, sc.f % 2 ? 0.35 : 0.22)
    sc.px(x - 1, h.y, 1, 6, glow); sc.px(x + 1, h.y, 1, 6, glow); sc.px(x, h.y - 1, 1, 1, glow)
    sc.px(x, h.y, 1, 6, oxblood()); sc.px(x, h.y + 2, 1, 1, ROLE.body)
  })
}

/** the book off the shelf: flying (riffle, then two flap frames) or perched (open at work, else closed), with its label and tip */
export function drawBook(sc: Scene, b: Book, mood: Mood, mode: Mode, tid: number | null) {
  if (mode === "shelved") return
  const frame = mode === "perched" ? (mood === "working" ? FRAMES.open : FRAMES.closed) : b.riffle > 0 ? FRAMES.riffle : (sc.tick >> 1) % 2 ? FRAMES.flapUp : FRAMES.flapDown
  const w = frame[0]!.length, x = Math.round(b.x), y = Math.round(b.y)
  sc.overhead.push(() => {
    sc.blit([...frame], x, y, paint(mood))
    sc.px(x + w, y + 1, 1, 6, RIBBON[mood]())
    sc.text("XLVI", x + w / 2, y - 1, ROLE.body, 9)
    if (tid !== null) sc.hits.push({ x, y, w: w + 1, h: 8, tip: `Uqbar · Vol. XLVI\n${mood} · #${tid}`, act: { kind: "thread", tid } })
  })
}
