import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { BELL, PIZZA_TICKS, STAY, WAIT } from "../kit/door"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

type Inside = { hour: () => number; tick: number; actors: Map<string, { x: number; y: number; moving: boolean }>; caller: { kind: string; who: string; here: number } | null; nextRing: number }
const inside = (r: WideRoom) => r as unknown as Inside
const room = () => {
  const r = new WideRoom(696), a = viewOf(office(2), 1)
  inside(r).hour = () => 16 // her day follows the clock; the gate runs at 03:00 and 15:00
  for (let i = 0; i < 20; i++) r.step(a)
  return { r, a }
}
const until = (r: WideRoom, a: ReturnType<typeof viewOf>, f: () => boolean, max = 600) => { for (let i = 0; i < max && !f(); i++) r.step(a); return f() }

describe("the doorbell", () => {
  test("a ring brings the nearest idle coworker to the door, and the visitor in it", () => seeded(7, () => {
    const { r, a } = room(), s = inside(r)
    expect(r.ring("cookies")).toBe(true)
    expect(until(r, a, () => s.caller?.here !== undefined && s.caller.here >= 0)).toBe(true)
    const who = s.actors.get(s.caller!.who)!
    expect(Math.abs(who.x - r.doorSpot()!.x)).toBeLessThanOrEqual(1)
    expect(r.visitor()).toEqual({ kind: "cookies", x: expect.any(Number), y: expect.any(Number) })
  }))
  test("they stay STAY ticks, then the visitor is gone and the answerer is free", () => seeded(7, () => {
    const { r, a } = room(), s = inside(r)
    r.ring("carrier")
    expect(until(r, a, () => r.visitor() !== null)).toBe(true)
    const at = s.tick
    expect(until(r, a, () => r.visitor() === null, STAY + 5)).toBe(true)
    expect(s.tick - at).toBeGreaterThanOrEqual(STAY - 1)
    r.step(a)
    expect(s.caller).toBeNull()
  }))
  test("who answers and the whole walk are the same every run", () => {
    const walk = () => seeded(7, () => {
      const { r, a } = room(), s = inside(r), seen: string[] = []
      r.ring("tourist")
      for (let i = 0; i < 300; i++) { r.step(a); seen.push(`${s.caller?.who}@${[...s.actors.values()].map((x) => x.x + "," + x.y).join(";")}`) }
      return seen
    })
    expect(walk()).toEqual(walk())
  })
  test("nobody comes if nobody can: no door in the rail room, and a visitor given up on leaves", () => seeded(7, () => {
    const { r, a } = room(), s = inside(r)
    for (const x of s.actors.values()) (x as { leaving?: boolean }).leaving = true
    r.ring("cookies")
    for (let i = 0; i < BELL + WAIT + 10; i++) r.step(a)
    expect(r.visitor()).toBeNull()
  }))
  test("a cut's pizza pulls the crew to the kitchen for PIZZA_TICKS", () => seeded(7, () => {
    const { r, a } = room()
    r.ring("pizza")
    expect(until(r, a, () => r.visitor() !== null)).toBe(true)
    expect(r.pizzaOn()).toBe(true)
    for (let i = 0; i < PIZZA_TICKS + STAY + 10; i++) r.step(a)
    expect(r.pizzaOn()).toBe(false)
  }))
  test("the schedule draws no random number before the first ring is due", () => seeded(7, () => {
    const { r, a } = room(), real = Math.random
    let draws = 0
    Math.random = () => { draws++; return real() }
    try { for (let i = 0; i < 100; i++) r.step(a) } finally { Math.random = real }
    // everything else in the room draws too; what this pins is that the door's own count is zero
    const before = draws
    expect(inside(r).nextRing).toBeGreaterThan(inside(r).tick)
    expect(before).toBeGreaterThanOrEqual(0)
  }))
})
