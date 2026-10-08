import { describe, expect, test } from "bun:test"
import { footLines, follow, offset } from "../tui/pane"
import { cells, line } from "../tui/term"

const strip = (s: string) => s.replace(/\x1b\[[\d;]*m/g, "")

describe("a pane's window on its rows", () => {
  test("rows that fit show whole, with nothing to say about more", () => {
    expect(follow(5, 4, 10)).toEqual({ first: 0, count: 5, above: 0, below: 0 })
    expect(offset(5, 10, 3)).toEqual({ first: 0, count: 5, above: 0, below: 0 })
  })
  test("the selection stays in view; each hidden side costs a row for its count", () => {
    for (let sel = 0; sel < 30; sel++) {
      const w = follow(30, sel, 10)
      expect(sel).toBeGreaterThanOrEqual(w.first)
      expect(sel).toBeLessThan(w.first + w.count)
      expect(w.count + (w.above ? 1 : 0) + (w.below ? 1 : 0)).toBeLessThanOrEqual(10)
      expect(w.above).toBe(w.first)
      expect(w.below).toBe(30 - w.first - w.count)
    }
    expect(follow(30, 0, 10)).toEqual({ first: 0, count: 9, above: 0, below: 21 })
    expect(follow(30, 29, 10)).toEqual({ first: 21, count: 9, above: 21, below: 0 })
  })
  test("scrolled by an offset, the last page ends on the last row", () => {
    expect(offset(30, 10, 0)).toEqual({ first: 0, count: 9, above: 0, below: 21 })
    expect(offset(30, 10, 5)).toEqual({ first: 5, count: 8, above: 5, below: 17 })
    expect(offset(30, 10, 99)).toEqual({ first: 21, count: 9, above: 21, below: 0 })
  })
})

describe("the foot's key hints", () => {
  const hints = [{ key: "a", label: "alpha" }, { key: "b", label: "beta" }, { key: "c", label: "gamma" }]
  test("wrap to the width, every hint whole on its line", () => {
    const lines = footLines(hints, 18, 3).map((l) => l.map((h) => `${h.key} ${h.label}`).join(" · "))
    expect(lines).toEqual(["a alpha · b beta", "c gamma"])
  })
  test("past the line cap, the last line says how many it could not fit", () => {
    expect(footLines(hints, 18, 1)).toEqual([[hints[0]!, { key: "+2", label: "more" }]])
  })
})

describe("cells", () => {
  test("wide and zero-width characters count as the terminal draws them", () => {
    expect(cells("abc")).toBe(3)
    expect(cells("日本")).toBe(4)
    expect(cells("🤖 ok")).toBe(5)
    expect(cells("é")).toBe(1)
  })
  test("a line with wide characters is cut and padded to its width in cells", () => {
    expect(cells(strip(line([{ s: "日本語の文" }], 5)))).toBe(5)
    expect(cells(strip(line([{ s: "a🤖b" }], 8)))).toBe(8)
  })
})
