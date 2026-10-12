import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { BATH, DOOR, FALL_LIFE, LIFE, RIM } from "../kit/bathroom"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

type Inside = { cat: { x: number; y: number; mode: string; wet: number; fell: boolean; path: unknown[] }; tick: number; prints: { x: number; y: number; at: number; until: number }[] }
const inside = (r: WideRoom) => r as unknown as Inside

/** a trip from the start (the room's own catDo, no waiting on chance): the cat's tile at every change, and every print laid */
function trip(seed: number, fall: boolean) {
  return seeded(seed, () => {
    const room = new WideRoom(696), a = viewOf(office(2), 1), r = inside(room)
    for (let i = 0; i < 20; i++) room.step(a)
    const real = Math.random
    expect(room.catDo("drink")).toBe(true)
    const tiles: [number, number][] = [], laid = new Map<string, { x: number; y: number; at: number; until: number }>()
    for (let i = 0; i < 2_000; i++) {
      // the fall is the one draw taken as she lands on the rim: pin it, so the contract is the branch, not luck
      const landing = r.cat.mode === "walk" && r.cat.path.length <= 1 && Math.abs(r.cat.x - RIM.x) <= 1 && Math.abs(r.cat.y - RIM.y) <= 1
      if (landing) Math.random = () => (fall ? 0 : 0.999)
      room.step(a)
      Math.random = real
      for (const p of r.prints) laid.set(`${p.at}:${p.x}:${p.y}`, { ...p })
      const last = tiles[tiles.length - 1]
      if (!last || last[0] !== r.cat.x || last[1] !== r.cat.y) tiles.push([r.cat.x, r.cat.y])
    }
    return { tiles, prints: [...laid.values()], fell: r.cat.fell }
  })
}

describe("Nina's drinking trip", () => {
  test("she goes in by the door, up on the rim, and the way is the same every run", () => {
    const t = trip(7, false)
    expect(trip(7, false).tiles).toEqual(t.tiles)
    const doorStep = t.tiles.findIndex(([x, y]) => x === DOOR.x && y === DOOR.y - 3)
    const rimStep = t.tiles.findIndex(([x, y]) => x === RIM.x && y === RIM.y)
    expect(doorStep).toBeGreaterThan(-1)
    expect(rimStep).toBeGreaterThan(doorStep)
    for (const [x, y] of t.tiles.slice(doorStep, rimStep + 1)) {
      expect(x).toBeGreaterThanOrEqual(BATH.x)
      expect(x).toBeLessThan(BATH.x + BATH.w)
      expect(y).toBeLessThan(BATH.y + BATH.h)
    }
  })

  test("leaving, every print is laid at its tick and fades LIFE ticks later, exactly", () => {
    const t = trip(7, false)
    expect(t.fell).toBe(false)
    expect(t.prints.length).toBeGreaterThan(0)
    for (const p of t.prints) expect(p.until - p.at).toBe(LIFE)
    expect(t.prints.map((p) => [p.x, p.y, p.at, p.until])).toEqual(
      [[38,172,332,932],
      [42,178,344,944],
      [48,180,356,956],
      [54,180,368,968],
      [60,180,380,980],
      [66,180,392,992],
      [68,184,404,1004],
      [70,188,416,1016],
      [76,188,428,1028],
      [82,188,440,1040],
      [88,188,452,1052],
      [94,188,464,1064],
      [94,182,476,1076],
      [94,176,488,1088],
      [94,170,500,1100],
      [94,164,512,1112],
      [92,158,524,1124],
      [86,152,536,1136],
      [80,146,548,1148],
      [74,140,560,1160],
      [68,134,572,1172],
      [62,128,584,1184],
      [56,128,596,1196]],
    )
  })

  test("when she falls in the trail is longer and each print lasts longer", () => {
    const ok = trip(7, false), fell = trip(7, true)
    expect(fell.fell).toBe(true)
    expect(fell.prints.length).toBeGreaterThan(ok.prints.length)
    for (const p of fell.prints) expect(p.until - p.at).toBe(FALL_LIFE)
  })

  test("the prints are gone a LIFE after the last was laid", () => seeded(7, () => {
    const room = new WideRoom(696), a = viewOf(office(2), 1), r = inside(room)
    for (let i = 0; i < 20; i++) room.step(a)
    room.catDo("drink")
    for (let i = 0; i < 2_000 && !(r.cat.wet > 0 && r.tick > r.cat.wet); i++) room.step(a)
    const last = Math.max(...r.prints.map((p) => p.until))
    while (r.tick < last) room.step(a)
    expect(r.prints).toHaveLength(0)
  }))
})
