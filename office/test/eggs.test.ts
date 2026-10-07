import { describe, expect, test } from "bun:test"
import { BABEL_ALPHABET, babelPage, clockFace, isKonami, keyMash, nightOwl } from "../kit/eggs"

describe("easter eggs", () => {
  test("the clock: 404 at four minutes past four, π at 3:14, the time otherwise", () => {
    expect(clockFace(new Date(2026, 9, 7, 4, 4))).toBe("404")
    expect(clockFace(new Date(2026, 9, 7, 16, 4))).toBe("404")
    expect(clockFace(new Date(2026, 9, 7, 15, 14))).toBe("π")
    expect(clockFace(new Date(2026, 9, 7, 9, 5))).toBe("09:05")
  })

  test("the Konami code is the last ten keys, in order — nothing more, nothing less", () => {
    const code = ["up", "up", "down", "down", "left", "right", "left", "right", "b", "a"]
    expect(isKonami(code)).toBe(true)
    expect(isKonami(["x", ...code])).toBe(true)
    expect(isKonami(code.slice(1))).toBe(false)
    expect(isKonami([...code.slice(0, 9), "b"])).toBe(false)
  })

  test("a page of the Library of Babel: its lines, its width, its alphabet — and, very rarely, a line that means something", () => {
    const page = babelPage(10, 40, () => 0.5)
    expect(page).toHaveLength(10)
    for (const l of page) {
      expect(l).toHaveLength(40)
      for (const ch of l) expect(BABEL_ALPHABET).toContain(ch)
    }
    const found = babelPage(10, 40, () => 0)
    expect(found.some((l) => /[a-z]{4,} [a-z]{3,}/.test(l.trim()) && !l.includes(","))).toBe(true)
  })

  test("a cat on the keyboard types the keys she stands on", () => {
    const m = keyMash()
    expect(m.length).toBeGreaterThan(8)
    expect(m).toMatch(/^[a-z;',.\\/\[\]]+$/)
  })

  test("the small hours are the night owl's: midnight to five", () => {
    expect([0, 1, 2, 3, 4].every(nightOwl)).toBe(true)
    expect([5, 9, 12, 18, 23].some(nightOwl)).toBe(false)
  })
})
