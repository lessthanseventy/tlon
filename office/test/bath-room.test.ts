import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { BATH, DOOR, TUB_IN } from "../kit/bathroom"
import { SINK_BOX, TOILET, TUB, WALLS } from "../kit/tiles/bathroom"
import { closet, HALL, OFF_W, WideRoom, widePlan } from "../rooms/wide"
import { focus, measure, office, seeded } from "./golden"

type Box = { x: number; y: number; w: number; h: number }
const overlap = (a: Box, b: Box) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
const inside = (p: { x: number; y: number }, r: Box) => p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h

describe("the bathroom is a room of its own", () => {
  test("walled into the bottom-left corner, its door on the hallway", () => {
    expect(BATH.x).toBe(0)
    expect(BATH.y + BATH.h).toBe(HALL - 6)
    expect(BATH.x + BATH.w).toBeLessThan(OFF_W)
    expect(DOOR.y).toBe(BATH.y + BATH.h)
    // a wall the whole way along the top and down both sides; only the door's gap is open
    expect(WALLS.some((w) => w.x === BATH.x && w.y === BATH.y && w.w === BATH.w)).toBe(true)
    expect(WALLS.some((w) => w.x === BATH.x && w.h === BATH.h)).toBe(true)
    expect(WALLS.some((w) => w.x + w.w === BATH.x + BATH.w && w.h === BATH.h)).toBe(true)
  })

  test("nothing of the office stands in it: no other furniture, no other spot, not the server closet", () => {
    const p = widePlan(696), l = p.layout(viewOf(office(6), 1) as never)
    const own = new Set<Box>([...WALLS, TUB, SINK_BOX, TOILET])
    for (const b of p.blocks(l)) if (!own.has(b)) expect({ b, in: overlap(b, BATH) }).toEqual({ b, in: false })
    expect(overlap(closet(), BATH)).toBe(false)
    for (const s of p.lounge) if (s.kind !== "bathroom") expect({ s, in: inside(s, BATH) }).toEqual({ s, in: false })
  })

  test("the tub, the sink and the toilet stand apart, a clear gap between each", () => {
    const left = [TUB, SINK_BOX, TOILET].sort((a, b) => a.x - b.x)
    for (let i = 1; i < left.length; i++) expect(left[i]!.x - (left[i - 1]!.x + left[i - 1]!.w)).toBeGreaterThanOrEqual(4)
  })

  test("the office plant's waterer walks to it without crossing a wall or the closet", () => {
    const p = widePlan(696), l = p.layout(viewOf(office(2), 1) as never), spot = p.lounge.find((x) => x.kind === "plant" && x.x < OFF_W)!
    const blocks = [...p.blocks(l), closet()]
    const pts = [{ x: 150, y: 100 }, ...p.route(150, 100, spot)]
    for (let i = 1; i < pts.length; i++) for (let t = 0; t <= 1; t += 0.05) {
      const x = pts[i - 1]!.x + (pts[i]!.x - pts[i - 1]!.x) * t, y = pts[i - 1]!.y + (pts[i]!.y - pts[i - 1]!.y) * t
      expect(blocks.find((b) => x > b.x && x < b.x + b.w - 1 && y > b.y && y < b.y + b.h - 1)).toBeUndefined()
    }
    expect(inside(spot, BATH)).toBe(false)
  })
})

describe("Nina in the tub", () => {
  test("sent there, she goes in by the door and curls up in the tub", () => seeded(3, () => {
    const room = new WideRoom(696), a = viewOf(office(2), 1), r = room as unknown as { hour: () => number; cat: { x: number; y: number; mode: string; path: unknown[] } }
    r.hour = () => 16
    for (let i = 0; i < 20; i++) room.step(a)
    expect(room.catDo("tub")).toBe(true)
    let door = false
    for (let i = 0; i < 3000 && !(r.cat.x === TUB_IN.x && r.cat.y === TUB_IN.y && !r.cat.path.length); i++) {
      room.step(a)
      if (r.cat.x === DOOR.x && r.cat.y === DOOR.y - 3) door = true
    }
    expect([r.cat.x, r.cat.y]).toEqual([TUB_IN.x, TUB_IN.y])
    expect(door).toBe(true)
    room.step(a)
    expect(r.cat.mode).toBe("sleep")
  }))

  test("left to herself the tub is one of her places, hopped into from the floor", () => {
    const cat = widePlan(696).cat
    expect(cat.spots).toContainEqual(TUB_IN)
    expect(cat.bath?.tub).toEqual(TUB_IN)
    const floor = cat.via(TUB_IN)!
    expect(inside(floor, BATH)).toBe(true)
    expect(inside(floor, TUB)).toBe(false)
  })

  test("in the tub, its front is drawn over her: she is in it, not on it", () => seeded(3, () => {
    const room = new WideRoom(696), a = viewOf(office(2), 1), at = new Date(2026, 9, 9, 15)
    const r = room as unknown as { cat: { x: number; y: number; mode: string; path: unknown[] } }
    for (let i = 0; i < 20; i++) room.step(a)
    const put = (x: number, y: number) => Object.assign(r.cat, { x, y, mode: "sleep", path: [] })
    put(TUB_IN.x, TUB_IN.y)
    const inTub = room.render(a, focus, measure, at)
    put(300, 120)
    const away = room.render(a, focus, measure, at)
    const px = (f: typeof inTub, x: number, y: number) => [...f.rgba.subarray((y * f.width + x) * 4, (y * f.width + x) * 4 + 4)].join()
    // the front lip, under where she lies, reads the same with her there or not
    for (let x = TUB_IN.x - 3; x <= TUB_IN.x + 3; x++) expect(px(inTub, x, TUB.y + TUB.h - 2)).toBe(px(away, x, TUB.y + TUB.h - 2))
    // and above it she shows
    let shows = false
    for (let y = TUB.y; y < TUB.y + TUB.h - 2; y++) for (let x = TUB_IN.x - 3; x <= TUB_IN.x + 3; x++) if (px(inTub, x, y) !== px(away, x, y)) shows = true
    expect(shows).toBe(true)
  }))
})
