import { describe, expect, test } from "bun:test"
import { contrast, ROLE } from "../kit/palette"
import { FADE_S, FLOOR, HOLD_S, Looks, inkAlpha, linesOf, refsOf, tintInk, type Note } from "../kit/margin"
import { MIN_CONTRAST } from "../tui/paint"

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
