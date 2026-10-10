// Uqbar's margin notes (docs/plans/2026-10-08-uqbar-design.md §4): one-line notes written on the
// workspace's root thread, drawn in the room's margin, newest nearest the room. Pure: callers pass
// the focused clock, so a golden or test is deterministic.
import { ROLE, tint } from "./palette"

export type Note = { id: number; author: string; body: string; at: number }
// FLOOR: the faintest ink still clears MIN_CONTRAST (4.5) on the ground; a note never fades past legible
export const HOLD_S = 60, FADE_S = 1200, FLOOR = 0.65
export const KEEP = 5, WIDTH = 44

/** the threads a note names (`#174`), once each, in order */
export function refsOf(body: string): number[] {
  const seen = new Set<number>()
  for (const m of body.matchAll(/#(\d+)/g)) seen.add(Number(m[1]))
  return [...seen]
}
/** ink strength for a note seen `age` focused seconds ago: full through the hold, then down to the floor */
export const inkAlpha = (age: number) =>
  age <= HOLD_S ? 1 : age >= HOLD_S + FADE_S ? FLOOR : 1 - ((age - HOLD_S) / FADE_S) * (1 - FLOOR)
export const tintInk = (alpha: number) => tint(ROLE.body, ROLE.ground, alpha)

/** what the operator has looked at: a clock of focused seconds and when each note was first seen on it */
export class Looks {
  focusedS = 0
  private focused = false
  private readonly seenAt = new Map<number, number>()
  /** `lookedAt`: the persisted epoch second of the last focused moment (0 on a first run) */
  constructor(public lookedAt: number) {}
  focus(on: boolean) { this.focused = on }
  /** advance the focused clock by `dt` seconds; unfocused time never counts */
  tick(dt: number) { if (this.focused) this.focusedS += dt }
  /** a frame drew these notes: while focused they are looked at; a note older than the last look is already seen */
  see(notes: Note[], focused: boolean) {
    this.focused = focused
    for (const n of notes) {
      if (this.seenAt.has(n.id)) continue
      if (focused) this.seenAt.set(n.id, this.focusedS)
      else if (n.at <= this.lookedAt) this.seenAt.set(n.id, this.focusedS - (this.lookedAt - n.at))
    }
  }
  alpha(n: Note): number {
    const s = this.seenAt.get(n.id)
    return s === undefined ? 1 : inkAlpha(this.focusedS - s)
  }
}

export type Line = { id: number; text: string; color: string; tid: number | null; lit: boolean }
/** the margin as lines: newest first, ≤ KEEP, cut to WIDTH; `lit` when it names the hovered thread `over` */
export function linesOf(notes: Note[], looks: Looks, over: number | null): Line[] {
  return [...notes].sort((a, b) => b.id - a.id).slice(0, KEEP).map((n) => {
    const refs = refsOf(n.body), t = [...n.body]
    const lit = over !== null && refs.includes(over)
    return {
      id: n.id, tid: refs[0] ?? null, lit,
      text: t.length > WIDTH ? `${t.slice(0, WIDTH - 1).join("")}…` : n.body,
      color: lit ? ROLE.key : tintInk(looks.alpha(n)),
    }
  })
}
