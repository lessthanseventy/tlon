import { describe, expect, test } from "bun:test"
import { clampViewport, panViewport, type Viewport } from "../tui/viewport"

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
