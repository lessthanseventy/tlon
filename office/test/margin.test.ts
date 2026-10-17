import { describe, expect, test } from "bun:test"
import { contrast, ROLE } from "../kit/palette"
import { FADE_S, FLOOR, HOLD_S, Looks, inkAlpha, linesOf, marginInk, refsOf, tintInk, type Note } from "../kit/margin"
import type { Frame } from "../kit/canvas"
import { geometry, hitAt, MIN_CONTRAST, measureFor } from "../tui/paint"

const note = (id: number, at: number, body = `n${id}`): Note => ({ id, author: "uqbar", body, at })

describe("refs", () => {
  test("#N names a thread, once each, in order", () => {
    expect(refsOf("#174 back to build — see #188 and #174")).toEqual([174, 188])
    expect(refsOf("cut 650fa4a")).toEqual([])
  })
})
describe("fade", () => {
  test("full ink through the hold, linear to the floor, flat after", () => {
    expect(inkAlpha(0)).toBe(1)
    expect(inkAlpha(HOLD_S)).toBe(1)
    expect(inkAlpha(HOLD_S + FADE_S / 2)).toBeCloseTo((1 + FLOOR) / 2)
    expect(inkAlpha(HOLD_S + FADE_S)).toBe(FLOOR)
    expect(inkAlpha(1e9)).toBe(FLOOR)
  })
  test("the floor is still legible on the ground", () => {
    expect(contrast(tintInk(FLOOR), ROLE.ground)).toBeGreaterThanOrEqual(MIN_CONTRAST)
  })
})
describe("since you last looked", () => {
  test("a note that arrives while unfocused stays full ink, however long the wait", () => {
    const l = new Looks(0)
    l.see([note(1, 100)], false)
    l.tick(HOLD_S + FADE_S)
    expect(l.alpha(note(1, 100))).toBe(1)
  })
  test("focus starts the fade; it fades by focused time only", () => {
    const l = new Looks(0)
    l.see([note(1, 100)], false)
    l.focus(true)
    l.see([note(1, 100)], true)
    l.tick(HOLD_S + FADE_S)
    expect(l.alpha(note(1, 100))).toBe(FLOOR)
    l.focus(false)
    l.tick(500)
    expect(l.focusedS).toBe(HOLD_S + FADE_S)
  })
  test("a note older than the last-looked stamp is already seen, aged by the wall gap", () => {
    const l = new Looks(10_000)
    l.see([note(1, 10_000 - (HOLD_S + FADE_S) - 5), note(2, 10_500)], false)
    expect(l.alpha(note(1, 0))).toBe(FLOOR)
    expect(l.alpha(note(2, 10_500))).toBe(1)
  })
  // A fresh start begins focused (graceful degradation for terminals without DEC 1004), so the
  // last-looked stamp must age a stale note on the first frame regardless of focus — or a restart
  // brings already-faded notes back to full ink (plan §b "survives a restart").
  test("a restart starts focused: a note older than the last-looked stamp is already faded", () => {
    const l = new Looks(10_000)
    l.see([note(1, 10_000 - (HOLD_S + FADE_S) - 5)], true)
    expect(l.alpha(note(1, 0))).toBe(FLOOR)
  })
})
describe("lines", () => {
  test("newest first, at most 5, each cut to 44 chars, lit when hovered thread is named", () => {
    const notes = Array.from({ length: 8 }, (_, i) => note(i + 1, 1000 + i, `#${100 + i} ${"x".repeat(60)}`))
    const l = new Looks(0)
    const got = linesOf(notes, l, 107)
    expect(got.length).toBe(5)
    expect(got[0]!.id).toBe(8)
    expect(got.every((x) => [...x.text].length <= 44)).toBe(true)
    expect(got[0]!.lit).toBe(true)
    expect(got[1]!.lit).toBe(false)
    expect(got[0]!.tid).toBe(107)
  })
})

describe("marginInk", () => {
  test("text ink anchored bottom-left of the viewport, newest on top, one hit per linked note", () => {
    const notes = [note(2, 20, "#188 closed"), note(1, 10, "cut 650fa4a")]
    const { ink, hits } = marginInk(notes, new Looks(0), null, { x: 50, y: 10, w: 300, h: 100 })
    const texts = ink.flatMap((i) => (i.t === "text" ? [i] : []))
    expect(texts.map((i) => i.s)).toEqual(["#188 closed", "cut 650fa4a"])
    expect(texts[0]).toMatchObject({ x: 52, align: "left" })
    expect(texts[0]!.y).toBeLessThan(texts[1]!.y)
    expect(texts[1]!.y).toBeLessThanOrEqual(10 + 100)
    expect(hits).toHaveLength(1)
    expect(hits[0]!.act).toEqual({ kind: "thread", tid: 188 })
    expect(hits[0]!.note).toBe(188)
    expect(hits[0]!.y).toBeLessThanOrEqual(texts[0]!.y)
    expect(hits[0]!.y + hits[0]!.h).toBeGreaterThan(texts[0]!.y)
  })

  test("the hit starts at the viewport's left edge: the first terminal column of a note counts as on it", () => {
    const vp = { x: 50, y: 10, w: 300, h: 100 }
    const { ink, hits } = marginInk([note(1, 10, "see #5")], new Looks(0), null, vp, () => 40)
    const text = ink.flatMap((i) => (i.t === "text" ? [i] : []))[0]!
    expect(hits[0]!.x).toBe(vp.x)
    expect(hits[0]!.x + hits[0]!.w).toBeGreaterThanOrEqual(text.x + 40)
  })

  test("every terminal cell of a note's row hits it, wherever the baseline falls in the cell — half blocks and kitty alike", () => {
    const cell = (w: number, h: number) => ({ w, h })
    for (const [W, H, cols, rows, px] of [
      [400, 300, 150, 60, null], [320, 240, 150, 60, null], [400, 300, 120, 50, null], [288, 200, 100, 40, null],
      [400, 300, 150, 60, cell(10, 20)], [400, 280, 100, 40, cell(12, 24)], [300, 200, 150, 60, cell(8, 16)],
    ] as const) {
      const g = geometry(W, H, cols, rows, 4, px, px !== null)
      for (let h = 80; h < 120; h++) {
        const vp = { x: 0, y: 0, w: W, h }
        const { ink, hits } = marginInk([note(1, 10, "see #5"), note(2, 20, "and #6")], new Looks(0), null, vp, measureFor(g))
        const fr: Frame = { rgba: new Uint8Array(W * H * 4), width: W, height: H, ink, hits }
        for (const i of ink) {
          if (i.t !== "text") continue
          const r = Math.floor((i.y * g.k - 0.01) / g.ch), c = Math.floor((i.x * g.k) / g.cw)
          expect(hitAt(fr, g, g.col + c + 1, g.row + r + 1, vp)?.act).toEqual({ kind: "thread", tid: i.s.endsWith("#5") ? 5 : 6 })
        }
      }
    }
  })

  test("a cell row taller than the line pitch spaces the notes a row apart, so no two share one", () => {
    const measure = Object.assign((s: string) => s.length * 4, { rowHeight: 20 })
    const { ink, hits } = marginInk([note(1, 10, "see #5"), note(2, 20, "and #6")], new Looks(0), null, { x: 0, y: 0, w: 300, h: 100 }, measure)
    const ys = ink.flatMap((i) => (i.t === "text" ? [i.y] : []))
    expect(ys[1]! - ys[0]!).toBeGreaterThanOrEqual(20)
    expect(ys[1]!).toBeLessThanOrEqual(100)
    expect(hits[0]!.y + hits[0]!.h).toBeLessThanOrEqual(hits[1]!.y + 0.01)
  })
})
