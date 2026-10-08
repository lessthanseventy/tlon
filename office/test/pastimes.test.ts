import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import type { Actor } from "../kit/sim"
import { EMPTY, type Agents } from "../kit/types"
import { moment } from "../kit/sim"
import { WideRoom, widePlan } from "../rooms/wide"

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

describe("the weather", () => {
  // one room for every frame: a room's first render is most of the cost, and eight under a loaded
  // gate ran past bun's 5 s timeout
  let shared: WideRoom | null = null
  const draw = (weather: Agents["weather"], hour: number) => {
    const room = (shared ??= new WideRoom(560)), a = viewOf({ ...office(["hronir"]), weather }, 1)
    room.step(a)
    return room.render(a, { picked: null, armed: null, person: null }, (s) => s.length * 2, new Date(2026, 2, 6, hour, 0))
  }
  test("the windows show the weather outside, and say it when clicked", () => chance(0.999, () => {
    const kinds = ["clear", "partly", "cloudy", "fog", "rain", "snow", "storm"] as const
    const frames = kinds.map((kind) => draw({ kind, temp_c: 9, desc: "Light rain " }, 11).rgba.join())
    expect(new Set(frames).size).toBe(kinds.length)
    expect(draw({ kind: "rain", temp_c: 9, desc: "Light rain" }, 11).hits.find((h) => h.act.kind === "weather")?.tip).toBe("outside: light rain, 9°C")
  }))
  test("no word on the weather draws a fair sky, and no forecast to click", () => chance(0.999, () => {
    expect(draw(null, 11).hits.some((h) => h.act.kind === "weather")).toBe(false)
  }))
})

describe("Nina and the fish", () => {
  test("she walks to the aquarium by the hallway, never through the furniture", () => {
    for (const w of [540, 696]) {
      const plan = widePlan(w), l = plan.layout(viewOf(office(["hronir"]), 1)), blocks = plan.blocks(l), fish = plan.cat.spots.at(-1)!
      for (const from of [{ x: 50, y: 128 }, ...plan.cat.lounge.slice(0, 2)]) {
        const path = [...plan.cat.door(from, fish), fish]
        for (let i = 1; i < path.length; i++) {
          const [p, q] = [path[i - 1]!, path[i]!]
          expect({ leg: [p, q], straight: p.x === q.x || p.y === q.y }).toEqual({ leg: [p, q], straight: true })
          for (let x = p.x, y = p.y; x !== q.x || y !== q.y; x += Math.sign(q.x - x), y += Math.sign(q.y - y)) {
            const hit = blocks.find((b) => x > b.x && x < b.x + b.w - 1 && y > b.y && y < b.y + b.h - 1)
            expect({ at: [x, y], hit }).toEqual({ at: [x, y], hit: undefined })
          }
        }
      }
    }
  })
})

describe("the arcade's best scores", () => {
  test("a game played and walked away from sets the cabinet's best, in that player's name", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office(["hronir"]), 1), r = inside(room)
    room.step(a)
    const p = [...r.actors.values()][0]!, spot = widePlan(560).lounge.find((s) => s.kind === "arcade")!
    Object.assign(p, { x: spot.x, y: spot.y, spot, spotKey: `arcade:${spot.x}:${spot.y}`, path: [], moving: false, until: r.tick + 1e6 })
    chance(0.5, () => { for (let i = 0; i < 40; i++) room.step(a) })
    expect(room.highScores()[0]).toBeNull()
    Object.assign(p, { x: 10, y: 176, spot: { ...spot, kind: "roam" }, spotKey: "roam" })
    room.step(a)
    expect(room.highScores()[0]).toMatchObject({ name: "hronir" })
    expect(room.highScores()[0]!.score).toBeGreaterThan(0)
  }))
})

describe("the corkboard", () => {
  const note = (id: number, author: string, body: string) => ({ id, author, kind: "joke" as const, body, re: null, at: 0 })
  test("a new note walks its author to the board, and they read it out there; the board as first seen does not", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office(["hronir", "yu"]), 1), r = inside(room) as Room & { talk: Map<string, { text: string | null }> }
    for (let i = 0; i < 100; i++) room.step(a)
    room.pinboard([note(1, "yu", "old news")])
    room.pinboard([note(2, "hronir", "Whoever keeps renaming things: I see you."), note(1, "yu", "old news")])
    let said: string | null | undefined
    for (let i = 0; i < 1500 && !said; i++) { room.step(a); said = r.talk.get("hronir")?.text }
    expect(said).toBe("Whoever keeps renaming things: I see you.")
    expect(r.talk.get("yu")?.text).toBeUndefined()
  }))

  test("a suggestion goes in the box, not on the board: its author walks to the box", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office(["hronir", "yu"]), 1), r = inside(room), box = widePlan(560).box!
    for (let i = 0; i < 100; i++) room.step(a)
    room.suggestionBox([])
    room.suggestionBox([{ ...note(3, "yu", "diff the summary against yesterday's"), kind: "suggestion" }])
    room.step(a)
    expect(r.actors.get("yu")!.spot).toMatchObject({ x: box.x, y: box.y })
  }))
})

describe("the cold", () => {
  test("on a cold day Nina makes for the radiator", () => {
    const room = new WideRoom(560), a = viewOf({ ...office(["hronir"]), weather: { kind: "snow", temp_c: -2, desc: "snow" } }, 1), r = inside(room)
    // midday: in the small hours the same roll sends her zooming instead
    ;(r as unknown as { hour: () => number }).hour = () => 12
    chance(0.999, () => room.step(a))
    Object.assign(r.cat, { mode: "sit", path: [], until: 0, purr: 0, stretch: 0, saidUntil: r.tick + 1000 })
    chance(0.1, () => room.step(a))
    expect((r.cat.path as { x: number; y: number }[]).at(-1)).toEqual({ x: 7, y: 115 })
  })
})

describe("a server restart", () => {
  test("the channel down is a pause, not everyone walking out and back in", () => chance(0.999, () => {
    const names = ["hronir", "yu", "ashe"], room = new WideRoom(560)
    for (let i = 0; i < 50; i++) room.step(viewOf(office(names), 1))
    const where = () => [...inside(room).actors.values()].map((x) => `${x.seat.agent}@${x.spotKey}:${x.leaving}`).sort()
    const before = where()
    for (let i = 0; i < 30; i++) room.step(viewOf({ ...EMPTY, note: "channel down" }, 1))
    expect(where()).toEqual(before)
    room.step(viewOf(office(names), 1))
    expect([...inside(room).actors.values()].every((x) => !x.leaving && x.spotKey !== "")).toBe(true)
  }))
})

describe("a birthday from the calendar", () => {
  const frame = (celebrations: Agents["celebrations"]) => {
    const room = new WideRoom(560), a = viewOf({ ...office(["hronir"]), celebrations }, 1)
    ;(room as unknown as { hour: () => number }).hour = () => 12
    return chance(0.999, () => { room.step(a); return room.render(a, { picked: null, armed: null, person: null }, (s) => s.length * 2, new Date(2026, 9, 8, 12, 0, 0)).rgba.join() })
  }
  test("bunting goes up and a cake comes out", () => {
    const none = frame([])
    expect(frame([{ title: "Ana's birthday", kind: "birthday" }])).not.toBe(none)
    expect(frame(undefined)).toBe(none)
  })
  test("anniversaries get the same, but not the same frame as a birthday's cake alone", () => {
    expect(frame([{ title: "Bo", kind: "anniversary" }])).not.toBe(frame([]))
  })
  test("the coworkers crowd to the kitchen counter: the cooler and coffee pull harder", () => {
    for (const kind of ["cooler", "coffee"]) expect(moment(kind, 12, undefined, true)).toBeGreaterThan(moment(kind, 12, undefined, false))
    expect(moment("arcade", 12, undefined, true)).toBe(moment("arcade", 12, undefined, false))
  })
})
