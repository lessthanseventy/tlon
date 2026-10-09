import { describe, expect, test } from "bun:test"
import { balloonLines } from "../kit/canvas"

describe("balloonLines", () => {
  test("hard-breaks a word longer than a line", () => {
    expect(balloonLines("x".repeat(80), 34, 4).every((l) => l.length <= 34)).toBe(true)
  })
  test("fuzz: never over the width, never over the rows, never empty for non-empty input", () => {
    let s = 12345
    const rnd = () => (s = (s * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff
    for (let n = 0; n < 500; n++) {
      const words = Array.from({ length: 1 + Math.floor(rnd() * 30) }, () => "a".repeat(1 + Math.floor(rnd() * 80)))
      const width = 4 + Math.floor(rnd() * 31), rows = 1 + Math.floor(rnd() * 4)
      const out = balloonLines(words.join(" "), width, rows)
      expect(out.length).toBeGreaterThan(0)
      expect(out.length).toBeLessThanOrEqual(rows)
      for (const l of out) expect(l.length).toBeLessThanOrEqual(width)
    }
  })
  test("default is 34 x 4; overflow ends in ...", () => {
    const out = balloonLines("word ".repeat(60))
    expect(out.length).toBe(4)
    expect(out[3]!.endsWith("...")).toBe(true)
    expect(balloonLines("done - merged the thing")).toEqual(["done - merged the thing"])
  })
})
