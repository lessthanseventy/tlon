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

import { placeBox, type Box } from "../kit/balloon"

const area: Box = { x: 0, y: 0, w: 100, h: 60 }
const inside = (b: Box, a: Box) => b.x >= a.x && b.y >= a.y && b.x + b.w <= a.x + a.w && b.y + b.h <= a.y + a.h
const hits = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

describe("placeBox", () => {
  test("centred on cx when roomy", () => {
    const b = placeBox({ w: 20, h: 10 }, 50, 40, area, [], 2)!
    expect(b.x).toBe(40)
    expect(b.y).toBe(30)
  })
  test("at each edge it stays inside, tail within the box", () => {
    for (const cx of [0, 100]) {
      const b = placeBox({ w: 20, h: 10 }, cx, 40, area, [], 2)!
      expect(inside(b, area)).toBe(true)
      expect(b.tail).toBeGreaterThanOrEqual(b.x + 2)
      expect(b.tail).toBeLessThanOrEqual(b.x + b.w - 2)
    }
  })
  test("a second box at the same cx nudges up off the first", () => {
    const first = placeBox({ w: 20, h: 10 }, 50, 40, area, [], 2)!
    const second = placeBox({ w: 20, h: 10 }, 50, 40, area, [first], 2)!
    expect(second.y + second.h).toBeLessThanOrEqual(first.y)
  })
  test("wider than the area, or no room above: null", () => {
    expect(placeBox({ w: 101, h: 10 }, 50, 40, area, [], 2)).toBeNull()
    const full = { x: 0, y: 0, w: 100, h: 60 }
    expect(placeBox({ w: 20, h: 10 }, 50, 40, area, [full], 2)).toBeNull()
  })
  test("fuzz: inside area and clear of taken, or null", () => {
    let s = 99
    const rnd = () => (s = (s * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff
    for (let n = 0; n < 200; n++) {
      const taken: Box[] = Array.from({ length: Math.floor(rnd() * 4) }, () => ({ x: rnd() * 80, y: rnd() * 50, w: 5 + rnd() * 30, h: 3 + rnd() * 15 }))
      const size = { w: 4 + rnd() * 40, h: 3 + rnd() * 15 }
      const b = placeBox(size, rnd() * 100, rnd() * 80, area, taken, 1 + Math.floor(rnd() * 3))
      if (b) { expect(inside(b, area)).toBe(true); for (const t of taken) expect(hits(b, t)).toBe(false) }
    }
  })
})
