import { describe, expect, test } from "bun:test"
import { geometry } from "../tui/paint"

describe("geometry", () => {
  test("kitty mode uses a flat legibility scale of 2, not fit, once the floor exceeds the terminal", () => {
    const g = geometry(2000, 1000, 80, 40, 3, { w: 8, h: 18 }, true)
    expect(g.k).toBe(2)
    expect(g.floorW).toBe(2000)
    expect(g.floorH).toBe(1000)
  })
  test("half-block mode is unchanged: still the largest fitting scale", () => {
    const g = geometry(100, 100, 80, 40, 3, { w: 8, h: 18 }, false)
    expect(g.kitty).toBe(false)
  })
})
