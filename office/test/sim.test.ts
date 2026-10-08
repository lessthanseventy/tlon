import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { glowOf, steamOf } from "../kit/draw"
import { ROLE } from "../kit/palette"
import { MEET_BOTTOM, WideRoom, zones } from "../rooms/wide"
import { office } from "./wcag.test"

describe("Sim.at", () => {
  test("Sim.at returns a seated actor's current spot, or null for a stranger", () => {
    const room = new WideRoom(696)
    room.step(viewOf(office(), 1)) // seeds actors from the roster
    const at = room.at("yu")
    expect(at === null || (typeof at.x === "number" && typeof at.y === "number")).toBe(true)
    expect(room.at("nobody-by-this-name")).toBeNull()
  })
})

describe("warmth at the desk", () => {
  type A = { spot: { kind: string; x: number; y: number }; warmth: number }
  const actor = (room: WideRoom, name: string) => (room as unknown as { actors: Map<string, A> }).actors.get(name)!
  /** the office with `names` warm and between turns, everyone else as `office()` has them */
  // no fresh notes: a note's author walks to the board to write it
  const between = (names: string[]) => { const a = office(); return viewOf({ ...a, notes: [], roster: a.roster.map((r) => (names.includes(r.agent) ? { ...r, warm: true, thinking: false } : r)) }, 1) }
  const dist = (p: string, q: string) => Math.hypot(...[1, 3, 5].map((i) => parseInt(p.slice(i, i + 2), 16) - parseInt(q.slice(i, i + 2), 16)))

  test("a coworker who just finished a turn stays at their desk, with a full mug's steam", () => {
    const room = new WideRoom(560)
    for (let i = 0; i < 300; i++) room.step(viewOf(office(), 1)) // ashe is mid-turn, at her desk
    expect(actor(room, "ashe").spot.kind).toBe("desk")
    for (let i = 0; i < 50; i++) room.step(between(["ashe"]))
    expect(actor(room, "ashe").spot.kind).toBe("desk")
    expect(actor(room, "ashe").warmth).toBeGreaterThan(0.95)
    expect(steamOf(actor(room, "ashe").warmth)).toBe(3)
  })

  test("the server's warmth rules: a fresh room (the TUI just restarted) shows a nearly cold coworker as nearly cold", () => {
    const room = new WideRoom(560)
    const a = office()
    const view = viewOf({ ...a, notes: [], roster: a.roster.map((r) => (r.agent === "ashe" ? { ...r, warm: true, thinking: false, warmth: 0.05 } : r)) }, 1)
    for (let i = 0; i < 5; i++) room.step(view)
    expect(actor(room, "ashe").warmth).toBeCloseTo(0.05, 3)
    expect(steamOf(actor(room, "ashe").warmth)).toBe(1)
  })

  test("near the end of the warmth window the steam is thin and the monitor's glow is dim", () => {
    const room = new WideRoom(560)
    ;(room as unknown as { warmTicks: number }).warmTicks = 100
    for (let i = 0; i < 300; i++) room.step(viewOf(office(), 1))
    for (let i = 0; i < 95; i++) room.step(between(["ashe"]))
    const w = actor(room, "ashe").warmth
    expect(actor(room, "ashe").spot.kind).toBe("desk")
    expect(w).toBeLessThan(0.1)
    expect(steamOf(w)).toBe(1)
    expect(dist(glowOf(w), ROLE.ground)).toBeLessThan(dist(ROLE.live, ROLE.ground) * 0.1)
  })

  test("nobody warm goes to the meeting room; gone cold, they get up from their desks", () => {
    // yu's thread waits on you, so yu queues at your door instead
    const room = new WideRoom(560), z = zones(560), names = office().roster.map((r) => r.agent).filter((n) => n !== "yu")
    for (let i = 0; i < 600; i++) room.step(between(names))
    for (const n of names) {
      const s = actor(room, n).spot
      expect(s.kind).toBe("desk")
      expect(s.x >= z.M0 && s.x <= z.M0 + z.MW && s.y < MEET_BOTTOM).toBe(false)
    }
    const cold = office()
    for (let i = 0; i < 600; i++) room.step(viewOf({ ...cold, notes: [], roster: cold.roster.map((r) => ({ ...r, warm: false, thinking: false })) }, 1))
    for (const n of names) expect(actor(room, n).spot.kind).not.toBe("desk")
  })
})

describe("the cat's temperament", () => {
  type Internals = { cat: { path: { x: number; y: number }[] }; plan: { cat: { nap: { x: number; y: number }; desk: { x: number; y: number } } } }
  /** the first place she sets off for once her opening nap is over, with every die rolled at 0.5 */
  const firstDest = (temperament?: { warmth: number; wits: number; energy: number }) => {
    const room = new WideRoom(560), real = Math.random, w = room as unknown as Internals & { setTemperament(t: unknown): void }
    if (temperament) w.setTemperament(temperament)
    Math.random = () => 0.5
    try {
      for (let i = 0; i < 400 && !w.cat.path.length; i++) room.step(viewOf(office(), 1))
    } finally { Math.random = real }
    const to = w.cat.path.at(-1)!
    return to.x === w.plan.cat.desk.x && to.y === w.plan.cat.desk.y ? "desk" : to.x === w.plan.cat.nap.x && to.y === w.plan.cat.nap.y ? "nap" : "other"
  }
  test("an unset temperament is today's table: 0.5 is the desk", () => { expect(firstDest()).toBe("desk") })
  test("a lazy cat at the same roll naps instead", () => { expect(firstDest({ warmth: 0, wits: 0, energy: -2 })).toBe("nap") })
})

describe("Nina's voice follows her warmth", () => {
  test("a warm cat, patted, says a sweet line; an unset one a sassy one", async () => {
    const { NINA, SWEET } = await import("../kit/voices")
    const said = (t?: { warmth: number; wits: number; energy: number }) => {
      const room = new WideRoom(560), real = Math.random, w = room as unknown as { cat: { said: string | null }; setTemperament(t: unknown): void }
      if (t) w.setTemperament(t)
      Math.random = () => 0
      try { room.pet() } finally { Math.random = real }
      return w.cat.said!
    }
    expect(SWEET.pet).toContain(said({ warmth: 2, wits: 0, energy: 0 }))
    expect(NINA.pet).toContain(said())
  })
})

describe("setPets", () => {
  test("the cat slot takes the file's name and temperament", async () => {
    const { resolvePets, TEMPERAMENTS } = await import("../kit/pets")
    const room = new WideRoom(560), w = room as unknown as { cat: { name: string }; temperament: unknown }
    expect(w.cat.name).toBe("Nina")
    room.setPets(resolvePets({ cat: { name: "Mimi", temperament: "zen" } }))
    expect(w.cat.name).toBe("Mimi")
    expect(w.temperament).toEqual(TEMPERAMENTS.zen)
  })
})
