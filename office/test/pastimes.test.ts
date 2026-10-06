import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import type { Actor } from "../kit/sim"
import { EMPTY, type Agents } from "../kit/types"
import { WideRoom } from "../rooms/wide"

/** run `f` with Math.random fixed at `r`: every chance taken (0), or none (0.999) */
function chance<T>(r: number, f: () => T): T {
  const real = Math.random
  Math.random = () => r
  try { return f() } finally { Math.random = real }
}
function office(names: string[], open = names.map((_, i) => 100 + i)): Agents {
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }],
    bench: names.map((name, i) => ({ workspace_id: 1, seat_id: i, agent_id: i + 1, name, archetype: "builder", lead: i === 0, model: null, ask: null })),
    threads: names.map((name, i) => ({ id: 100 + i, title: `t${i}`, stage: null, awaiting: null, workspace_id: 1, lead: name })).filter((t) => open.includes(t.id)),
    roster: names.map((name, i) => ({ agent: name, thread_id: 100 + i, title: `t${i}`, warm: false, thinking: false, workspace_id: 1 })),
  }
}
type Room = { actors: Map<string, Actor>; party: { agent: string } | null; tick: number; cat: { x: number; y: number; mode: string; path: unknown[]; purr: number; stretch: number; saidUntil: number; fuss: { kind: string } | null } }
const inside = (r: WideRoom) => r as unknown as Room

describe("the office celebrates", () => {
  test("a thread that ships throws its lead a party, with confetti over them", () => chance(0.999, () => {
    const names = ["hronir", "yu", "ashe"], room = new WideRoom(560)
    for (let i = 0; i < 50; i++) room.step(viewOf(office(names), 1))
    const before = room.render(viewOf(office(names), 1), { picked: null, armed: null, person: null }, (s) => s.length * 2).rgba.join()
    room.step(viewOf(office(names, [100, 102]), 1))
    expect(inside(room).party?.agent).toBe("yu")
    expect(room.render(viewOf(office(names, [100, 102]), 1), { picked: null, armed: null, person: null }, (s) => s.length * 2).rgba.join()).not.toBe(before)
  }))

  test("many threads gone at once is a new view, not a party", () => chance(0.999, () => {
    const names = ["hronir", "yu", "ashe", "daneri"], room = new WideRoom(560)
    for (let i = 0; i < 50; i++) room.step(viewOf(office(names), 1))
    room.step(viewOf(office(names, []), 1))
    expect(inside(room).party).toBeNull()
  }))

  test("someone just done high-fives whoever they pass, once", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office(["hronir", "yu"]), 1), r = inside(room)
    room.step(a)
    const [p, q] = [...r.actors.values()]
    Object.assign(p!, { finished: r.tick, x: 200, y: 176, pose: "stand" }); Object.assign(q!, { x: 205, y: 176, pose: "stand" })
    room.step(a)
    expect([p!.five > r.tick, q!.five > r.tick]).toEqual([true, true])
    q!.five = 0
    room.step(a)
    expect(q!.five).toBe(0)
  }))
})

describe("snacks", () => {
  test("a snack from the machine goes to Nina as a treat", () => {
    const room = new WideRoom(560), a = viewOf(office(["hronir"]), 1), r = inside(room)
    chance(0.999, () => { for (let i = 0; i < 300; i++) room.step(a) })
    const p = [...r.actors.values()][0]!
    Object.assign(p, { snack: r.tick + 500, x: 300, y: 150, moving: false, path: [], spot: { ...p.spot, kind: "couch" } })
    Object.assign(r.cat, { x: 310, y: 150, mode: "sit", path: [], purr: 0, stretch: 0, saidUntil: 0 })
    chance(0, () => room.step(a))
    expect(r.cat.fuss?.kind).toBe("treat")
    expect(p.snack).toBe(0)
  })
})

describe("the date", () => {
  test("October brings its decorations, and the dark its bats and lamplight", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office(["hronir"]), 1)
    for (let i = 0; i < 20; i++) room.step(a)
    const at = (month: number, hour: number) => room.render(a, { picked: null, armed: null, person: null }, (s) => s.length * 2, new Date(2026, month, 6, hour, 30)).rgba.join()
    // the windows' sky changes with the hour anyway, so compare like with like
    expect(at(9, 21)).not.toBe(at(2, 21))
    expect(at(9, 14)).not.toBe(at(2, 14))
  }))
})
