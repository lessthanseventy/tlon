import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { toysOf, type Toys } from "../kit/door"
import { parseSoul, useSouls } from "../kit/souls"
import { DEFAULT, resolve, setDial } from "../kit/whimsy"
import { WideRoom } from "../rooms/wide"
import { EMPTY, type Agents } from "../kit/types"
import { seeded } from "./golden"

function office(names: string[]): Agents {
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }],
    bench: names.map((name, i) => ({ workspace_id: 1, seat_id: i, agent_id: i + 1, name, archetype: "builder", lead: i === 0, model: null, ask: null })),
    threads: names.map((name, i) => ({ id: 100 + i, title: `t${i}`, stage: null, awaiting: null, workspace_id: 1, lead: name })),
    roster: names.map((name, i) => ({ agent: name, thread_id: 100 + i, title: `t${i}`, warm: false, thinking: false, workspace_id: 1 })),
  }
}
const CREW = ["hronir", "yu"]
const withDials = (souls: boolean, weirdness: "curated" | "procedural" | "invented") => {
  const room = new WideRoom(560)
  room.setWhimsy(resolve(setDial(setDial(DEFAULT, "souls", souls), "weirdness", weirdness)))
  return room
}
const inner = (r: WideRoom) => r as unknown as { actors: Map<string, { five: number; finished: number; x: number; y: number; pose: string }>; tick: number; callers: { kind: string; guest?: { name: string } }[]; talk: Map<string, { text: string | null }>; caller: unknown; stepDoor: () => boolean }
const pool: Toys = {
  visitors: [{ name: "Mr. Plover", look_seed: "plover", line: "Is this the room with the ducks?" }],
  puns: ["I would tell you a UDP joke, but you might not get it."],
  reactions: { hronir: { fire_drill: ["Calmly. Calmly. Run."] } },
  parts: [],
}
const fixed = <T,>(r: number, f: () => T): T => { const real = Math.random; Math.random = () => r; try { return f() } finally { Math.random = real } }

describe("the souls dial", () => {
  const highFived = (souls: boolean) => fixed(0.999, () => {
    useSouls({ hronir: parseSoul("## People\nneedles yu") })
    try {
      const room = withDials(souls, "curated"), a = viewOf(office(CREW), 1), r = inner(room)
      room.step(a)
      const [p, q] = [...r.actors.values()]
      Object.assign(p!, { finished: r.tick, x: 200, y: 176, pose: "stand" }); Object.assign(q!, { x: 205, y: 176, pose: "stand" })
      room.step(a)
      return p!.five > r.tick
    } finally { useSouls({}) }
  })
  test("on: a seat that needles the other gets no high five; off: the souls are ignored and they do", () => {
    expect(highFived(true)).toBe(false)
    expect(highFived(false)).toBe(true)
  })
})

describe("the weirdness dial", () => {
  const rung = (w: "curated" | "procedural" | "invented", toys: Toys | null) => seeded(3, () => fixed(0.1, () => {
    const room = withDials(false, w), a = viewOf(office(CREW), 1), r = inner(room)
    room.step(a)
    room.setToys(toys)
    room.ring()
    return r.callers[0]!
  }))
  test("curated: the door's own visitors, whatever the server generated", () => {
    expect(rung("curated", pool).kind).not.toBe("guest")
  })
  test("procedural and invented: a pooled visitor can come, with the server's name and line", () => {
    for (const w of ["procedural", "invented"] as const) expect(rung(w, pool)).toMatchObject({ kind: "guest", guest: { name: "Mr. Plover" } })
  })
  test("an empty pool, or none at all (an older server), changes nothing", () => {
    expect(rung("invented", { visitors: [], puns: [], reactions: {}, parts: [] }).kind).not.toBe("guest")
    expect(rung("invented", null).kind).not.toBe("guest")
  })
  test("a pooled seat's reaction replaces the scripted line at an event; curated keeps the script", () => {
    const said = (w: "curated" | "invented") => seeded(3, () => {
      const room = withDials(false, w), a = viewOf(office(CREW), 1), r = inner(room)
      room.step(a)
      room.setToys(pool)
      room.event("drill")
      return r.talk.get("hronir")?.text
    })
    expect(said("invented")).toBe("Calmly. Calmly. Run.")
    expect(said("curated")).not.toBe("Calmly. Calmly. Run.")
  })
  test("after a visit the answerer groans a pooled pun, only when the dial is up", () => {
    const after = (w: "curated" | "invented") => seeded(3, () => fixed(0.1, () => {
      const room = withDials(false, w), a = viewOf(office(CREW), 1), r = inner(room)
      for (let i = 0; i < 80; i++) room.step(a)
      room.setToys(pool)
      const who = [...r.actors.keys()][0]!
      Object.assign(r, { caller: { kind: "carrier", who, bell: 0, here: 0 } })
      r.stepDoor()
      return r.talk.get(who)?.text
    }))
    expect(after("invented")).toBe(pool.puns[0]!)
    expect(after("curated")).not.toBe(pool.puns[0]!)
  })
})

describe("the toys payload", () => {
  test("narrowed to what is usable; junk and an absent route are null or empty", () => {
    expect(toysOf(null)).toBeNull()
    expect(toysOf({ visitors: [{ name: "A", line: "hi" }, { nope: 1 }], puns: ["p", 3, ""], reactions: { x: { fire_drill: ["a", 2], duck: [] } } }))
      .toEqual({ visitors: [{ name: "A", look_seed: "A", line: "hi" }], puns: ["p"], reactions: { x: { fire_drill: ["a"] } }, parts: [] })
  })
})

describe("a cut on the wide room", () => {
  test("the TV takes the release and Uqbar is sent to it; settling lets the book go home", () => seeded(3, () => {
    const room = new WideRoom(560), a = { ...viewOf(office(CREW), 1), uqbar: { agent: "uqbar", thread_id: 9, title: "", warm: true, thinking: false } }
    const r = room as unknown as { errand: { kind: string; name?: string; dwell: number } | null; awake: boolean }
    for (let i = 0; i < 5; i++) room.step(a)
    expect(r.awake).toBe(true)
    room.cut("650fa4a", ["one", "two"])
    expect(room.cutting).toBe(true)
    expect(r.errand).toMatchObject({ kind: "tv", name: "cut", dwell: Infinity })
    room.cutDone()
    expect(r.errand!.dwell).toBeLessThan(Infinity)
  }))
})
