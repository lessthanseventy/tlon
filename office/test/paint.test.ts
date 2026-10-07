import { describe, expect, test } from "bun:test"
import { geometry, kittyImage } from "../tui/paint"

describe("kittyImage", () => {
  test("transmits the full floor once and crops via the placement's source rect, scaled by k", () => {
    const fr = { rgba: new Uint8Array(20 * 20 * 4), width: 20, height: 20, ink: [], hits: [] }
    const g = { k: 2, cw: 8, ch: 18, col: 0, row: 0, cols: 10, rows: 10, kitty: true, floorW: 20, floorH: 20 }
    const out = kittyImage(fr, g, { x: 4, y: 4, w: 10, h: 10 })
    expect(out).toContain("a=t,")
    expect(out).toContain("x=8,y=8,w=20,h=20")
  })
})

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
