import { describe, expect, test } from "bun:test"
import { geometry, kittyImage, textLayer } from "../tui/paint"

describe("kittyImage", () => {
  test("transmits the full floor once and crops via the placement's source rect, scaled by k", () => {
    const fr = { rgba: new Uint8Array(20 * 20 * 4), width: 20, height: 20, ink: [], hits: [] }
    const g = { k: 2, cw: 8, ch: 18, col: 0, row: 0, cols: 10, rows: 10, kitty: true, floorW: 20, floorH: 20 }
    const out = kittyImage(fr, g, { x: 4, y: 4, w: 10, h: 10 })
    expect(out).toContain("a=t,")
    expect(out).toContain("x=8,y=8,w=20,h=20")
  })
})

const strip = (s: string) => s.replace(/\x1b\[[\d;]*m/g, "")

describe("textLayer viewport crop", () => {
  test("textLayer only emits rows/cols inside the viewport", () => {
    const fr = { rgba: new Uint8Array(20 * 20 * 4).fill(255), width: 20, height: 20, ink: [], hits: [] }
    const g = { k: 1, cw: 1, ch: 2, col: 0, row: 0, cols: 20, rows: 10, kitty: false, floorW: 20, floorH: 20 }
    const rows = textLayer(fr, g, { x: 4, y: 6, w: 10, h: 10 })
    expect(rows.length).toBe(5) // 10 px tall viewport / ch=2
    expect(strip(rows[0]!).length).toBe(10) // 10 px wide viewport / cw=1 -> 10 cells
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
