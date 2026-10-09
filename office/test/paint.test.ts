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

import { inkInto } from "../tui/paint"
import { balloonLines } from "../kit/canvas"

describe("inkInto balloons (kitty)", () => {
  const W = 200, H = 120, view = { x: 20, y: 10, w: 100, h: 80 }
  const render = (cxs: number[], text = "x".repeat(80) + " and then some more words to wrap around") => {
    const big = new Uint8Array(W * H * 4)
    inkInto(big, W, H, cxs.map((cx) => ({ t: "balloon" as const, lines: balloonLines(text), cx: cx / 2, top: 60 })), 2, 1, undefined, view)
    return big
  }
  const bounds = (big: Uint8Array) => {
    let x0 = W, y0 = H, x1 = -1, y1 = -1
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (big[(y * W + x) * 4 + 3]) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y) }
    return { x0, y0, x1, y1 }
  }
  test("a long balloon at the viewport's edges and middle stays inside it", () => {
    for (const cx of [view.x, 70, view.x + view.w]) {
      const b = bounds(render([cx]))
      expect(b.x1).toBeGreaterThan(-1)
      expect(b.x0).toBeGreaterThanOrEqual(view.x)
      expect(b.y0).toBeGreaterThanOrEqual(view.y)
      expect(b.x1).toBeLessThan(view.x + view.w)
      expect(b.y1).toBeLessThan(view.y + view.h)
    }
  })
  test("two balloons side by side do not overlap", () => {
    const t = "hello there", a = bounds(render([60], t)), c = bounds(render([66], t)), both = bounds(render([60, 66], t))
    const area = (b: ReturnType<typeof bounds>) => (b.x1 - b.x0 + 1) * (b.y1 - b.y0 + 1)
    expect(both.y0).toBeLessThan(Math.min(a.y0, c.y0)) // the second was nudged up
    expect(area(both)).toBeGreaterThan(area(a))
  })
})

describe("textLayer balloons (blocks)", () => {
  const floorW = 80, floorH = 60
  const g = { k: 1, cw: 1, ch: 2, col: 0, row: 0, cols: 80, rows: 30, kitty: false, floorW, floorH }
  const frame = (ink: any[]) => ({ rgba: new Uint8Array(floorW * floorH * 4).fill(255), width: floorW, height: floorH, ink, hits: [] })
  const balloon = (text: string, cx: number) => ({ t: "balloon" as const, lines: balloonLines(text), cx, top: 40 })
  test("an 80-char word at each edge stays inside the room, rows keep their width", () => {
    for (const cx of [0, 40, floorW]) {
      const rows = textLayer(frame([balloon("x".repeat(80), cx)]), g).map(strip)
      for (const r of rows) expect(r.length).toBe(80)
      expect(rows.join("").split("x").length - 1).toBe(80)
    }
  })
  test("a panned viewport puts the balloon on the speaker's column", () => {
    const rows = textLayer(frame([balloon("hi", 60)]), g, { x: 50, y: 0, w: 30, h: 60 }).map(strip)
    const at = rows.map((r) => r.indexOf("hi")).find((i) => i >= 0)!
    expect(at).toBeGreaterThanOrEqual(8)
    expect(at).toBeLessThanOrEqual(12)
  })
  test("two speakers 3 cells apart: both balloons show, on different rows", () => {
    const rows = textLayer(frame([balloon("alpha", 40), balloon("bravo", 43)]), g).map(strip)
    const a = rows.findIndex((r) => r.includes("alpha")), b = rows.findIndex((r) => r.includes("bravo"))
    expect(a).toBeGreaterThanOrEqual(0)
    expect(b).toBeGreaterThanOrEqual(0)
    expect(a).not.toBe(b)
  })
})
