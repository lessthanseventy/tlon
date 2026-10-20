import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

// The room over a simulated hour, both ways: what it does must be coherent (nothing a real office
// would not do: a game playing itself, two bodies on one spot, someone standing in the furniture),
// and it must stay fun (the pets get up to things, the crew talks). A change that breaks either
// fails here, not in the operator's eye a day later.

const HOUR = 36_000 // ticks are 100 ms
const LINGER = 50 // five seconds: passing through each other is fine, staying put is not
const GAMES = ["pool", "foosball", "pingpong"]

type Day = { antics: number; catModes: number; lines: number; faults: string[] }

function hour(seed: number): Day {
  return seeded(seed, () => {
    const o = office(10)
    o.roster = o.roster.map((r, i) => (i > 2 ? { ...r, thinking: false, warm: false } : r))
    const a = viewOf(o, 1), r: any = new WideRoom(696)
    r.hour = () => 12
    const day: Day = { antics: 0, catModes: 0, lines: 0, faults: [] }
    const fault = (s: string) => { if (day.faults.length < 5) day.faults.push(`tick ${r.tick}: ${s}`) }
    const say = r.say.bind(r)
    r.say = (n: string, t: string | null) => { if (t) day.lines++; return say(n, t) }
    let antic: unknown = null, mode = r.cat.mode, petsTogether = 0
    const stacked = new Map<string, number>()
    for (let i = 0; i < HOUR; i++) {
      r.step(a)
      if (r.antic && r.antic !== antic) day.antics++
      antic = r.antic
      if (r.cat.mode !== mode) { day.catModes++; mode = r.cat.mode }

      // a game plays only with both its players at it
      for (const g of GAMES) {
        const at = r.peopleAt(g)
        if (at.length > 2) fault(`${at.length} people at the ${g} table`)
        for (const x of at) if (x.x !== x.spot.x || x.y !== x.spot.y) fault(`${x.seat.agent} counted at the ${g} table from ${x.x},${x.y}`)
      }
      // Nina and Argos pass each other, they do not merge
      petsTogether = Math.abs(r.cat.x - r.dog.x) <= 4 && Math.abs(r.cat.y - r.dog.y) <= 3 ? petsTogether + 1 : 0
      if (petsTogether === LINGER) fault(`Nina and Argos on one spot at ${r.cat.x},${r.cat.y}`)
      // nobody stands on somebody, nobody stands in the furniture
      const still = [...r.actors.values()].filter((x: any) => !x.moving && !x.path.length)
      const blocks = r.plan.blocks(r.plan.layout(a))
      const here = new Map<string, number>()
      for (const x of still) {
        const k = `${x.x},${x.y}`
        here.set(k, (here.get(k) ?? 0) + 1)
        const off = x.x !== x.spot.x || x.y !== x.spot.y
        if (off && blocks.some((b: any) => x.x > b.x && x.x < b.x + b.w && x.y > b.y && x.y < b.y + b.h)) fault(`${x.seat.agent} stands inside furniture at ${k}`)
      }
      for (const k of [...stacked.keys()]) if (!here.has(k) || here.get(k)! < 2) stacked.delete(k)
      for (const [k, n] of here) if (n > 1) { const t = (stacked.get(k) ?? 0) + 1; stacked.set(k, t); if (t === LINGER) fault(`${n} people on one spot at ${k}`) }
    }
    return day
  })
}

describe("the room over an hour", () => {
  for (const seed of [11]) {
    const day = hour(seed)
    test(`seed ${seed}: coherent — nothing a real office would not do`, () => {
      expect(day.faults).toEqual([])
    })
    // floors at about half of what a seeded hour does today: room to tune, none to go quiet
    test(`seed ${seed}: still fun — the pets get up to things, the crew talks`, () => {
      expect(day.antics).toBeGreaterThanOrEqual(1)
      expect(day.catModes).toBeGreaterThanOrEqual(30)
      expect(day.lines).toBeGreaterThanOrEqual(2)
    })
  }
})
