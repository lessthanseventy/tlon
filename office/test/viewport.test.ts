import { describe, expect, test } from "bun:test"
import type { Frame } from "../kit/canvas"
import { clampViewport, clipFrame, panViewport, type Viewport } from "../tui/viewport"

function frame(over: Partial<Frame>): Frame {
  return { rgba: new Uint8Array(0), width: 0, height: 0, ink: [], hits: [], ...over }
}

describe("viewport clamp and pan", () => {
  test("pan moves by the delta", () => {
    const v: Viewport = { x: 10, y: 10, w: 100, h: 100 }
    expect(panViewport(v, 5, -3, 500, 500)).toEqual({ x: 15, y: 7, w: 100, h: 100 })
  })
  test("clamps at the floor's edges on every side", () => {
    const v: Viewport = { x: 10, y: 10, w: 100, h: 100 }
    expect(panViewport(v, -100, -100, 500, 500)).toEqual({ x: 0, y: 0, w: 100, h: 100 })
    expect(panViewport(v, 1000, 1000, 500, 500)).toEqual({ x: 400, y: 400, w: 100, h: 100 })
  })
  test("a viewport bigger than the floor centers and never reports negative room", () => {
    const v: Viewport = { x: 0, y: 0, w: 600, h: 600 }
    expect(clampViewport(v, 500, 500)).toEqual({ x: 0, y: 0, w: 600, h: 600 })
  })
})

describe("clipFrame", () => {
  const viewport: Viewport = { x: 0, y: 0, w: 100, h: 100 }
  test("a hit outside the viewport is dropped", () => {
    const fr = frame({ hits: [{ x: 500, y: 500, w: 10, h: 10, tip: "far", act: { kind: "crew" } }] })
    expect(clipFrame(fr, viewport).hits).toEqual([])
  })
  test("a hit inside the viewport survives", () => {
    const fr = frame({ hits: [{ x: 10, y: 10, w: 10, h: 10, tip: "near", act: { kind: "crew" } }] })
    expect(clipFrame(fr, viewport).hits).toHaveLength(1)
  })
  test("a label off to the right becomes a single-glyph edge marker pointing at it", () => {
    const fr = frame({ ink: [{ t: "text", s: "Name", x: 500, y: 50, color: "#fff", size: 11, align: "left" }] })
    const ink = clipFrame(fr, viewport).ink
    expect(ink).toHaveLength(1)
    expect(ink[0]).toMatchObject({ t: "text", s: "▸ Name" })
  })
  test("a label above becomes an up-pointing edge marker", () => {
    const fr = frame({ ink: [{ t: "text", s: "Name", x: 50, y: -500, color: "#fff", size: 11, align: "left" }] })
    expect(clipFrame(fr, viewport).ink[0]).toMatchObject({ t: "text", s: "▴ Name" })
  })
})
