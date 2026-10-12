import { describe, expect, test } from "bun:test"
import { createHash } from "node:crypto"
import { viewOf } from "../kit/crew"
import { BATH, DOOR, FALL_LIFE, LIFE, doorOpen, fadeStage, layPrint, prune, type Print } from "../kit/bathroom"
import { WideRoom } from "../rooms/wide"
import { focus, measure, office } from "./golden"

describe("prints", () => {
  test("a print lives LIFE ticks (a minute at 100 ms), longer when she fell in", () => {
    expect(layPrint(10, 20, 100, false)).toEqual({ x: 10, y: 20, at: 100, until: 100 + LIFE })
    expect(layPrint(10, 20, 100, true).until).toBe(100 + FALL_LIFE)
    expect(FALL_LIFE).toBeGreaterThan(LIFE)
  })
  test("fadeStage is 0 fresh, rises to 3 just before it goes, and prune drops it at until", () => {
    const p = layPrint(0, 0, 0, false)
    expect([0, LIFE / 3 - 1, LIFE / 3, (2 * LIFE) / 3, LIFE - 1].map((t) => fadeStage(p, t))).toEqual([0, 0, 1, 2, 2])
    expect(fadeStage(p, LIFE)).toBe(3)
    expect(prune([p], LIFE - 1)).toHaveLength(1)
    expect(prune([p], LIFE)).toHaveLength(0)
  })
  test("they go one by one: laid in order, they vanish in order", () => {
    const ps = [0, 12, 24].map((t) => layPrint(t, 0, t, false))
    expect(prune(ps, LIFE + 12).map((p) => p.at)).toEqual([24])
  })
})

describe("the room", () => {
  test("the door is in the bottom wall, inside the box", () => {
    expect(DOOR.y).toBe(BATH.y + BATH.h)
    expect(DOOR.x).toBeGreaterThan(BATH.x)
    expect(DOOR.x).toBeLessThan(BATH.x + BATH.w)
  })
  test("the door is open while anyone is at it, and for HOLD ticks after, else shut", () => {
    const at = { x: DOOR.x, y: DOOR.y - 2 }, far = { x: 300, y: 100 }
    expect(doorOpen([at], 50, -1000)).toBe(true)
    expect(doorOpen([far], 50, -1000)).toBe(false)
    expect(doorOpen([far], 50, 45)).toBe(true)
    expect(doorOpen([far], 80, 45)).toBe(false)
  })
})

describe("the prints on the floor", () => {
  test("a fresh print is drawn, a faded one is fainter, a gone one is not drawn", () => {
    const room = new WideRoom(696), a = viewOf(office(2), 1), r = room as unknown as { prints: Print[]; tick: number }
    const frame = () => createHash("sha256").update(Buffer.from(room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0)).rgba)).digest("hex")
    for (let i = 0; i < 5; i++) room.step(a)
    const base = frame()
    r.prints = [{ x: 200, y: 188, at: r.tick, until: r.tick + LIFE }]
    const fresh = frame()
    r.prints = [{ x: 200, y: 188, at: r.tick - LIFE + 1, until: r.tick + 1 }]
    const faded = frame()
    r.prints = []
    expect(fresh).not.toBe(base)
    expect(faded).not.toBe(fresh)
    expect(frame()).toBe(base)
  })
})
