import { describe, expect, test } from "bun:test"
import { EVENT_KINDS, EVENTS, blackoutAt, flickerAt, pickEvent, propsAt, type Geo } from "../kit/events"
import { viewOf } from "../kit/crew"
import { DRILL } from "../kit/sim"
import { RailRoom } from "../rooms/rail"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

const geo: Geo = { doorX: 600, hallY: 190, ceilY: 12, leftX: 60, windowX: 200, cork: { x: 400, y: 40 } }

describe("the events table", () => {
  test("five kinds, each a bounded script whose beats fall inside it", () => {
    expect(EVENT_KINDS).toEqual(["drill", "zoo", "meteor", "power", "duck"])
    for (const k of EVENT_KINDS) {
      const s = EVENTS[k]
      expect(s.ticks).toBeGreaterThanOrEqual(500)
      expect(s.ticks).toBeLessThanOrEqual(1200)
      for (const b of s.beats) {
        expect(b.at).toBeGreaterThanOrEqual(0)
        expect(b.at).toBeLessThan(s.ticks)
      }
    }
    expect(EVENTS.drill.ticks).toBe(DRILL)
  })
  test("pickEvent never repeats the last and is a function of the roll", () => {
    for (const last of EVENT_KINDS) for (const r of [0, 0.3, 0.99]) expect(pickEvent(r, last)).not.toBe(last)
    expect(pickEvent(0.5, null)).toBe(pickEvent(0.5, null))
  })
  test("props are empty after the end; pure in t", () => {
    for (const k of EVENT_KINDS) {
      expect(propsAt(k, EVENTS[k].ticks, geo)).toEqual([])
      expect(propsAt(k, 100, geo)).toEqual(propsAt(k, 100, geo))
    }
    expect(propsAt("duck", 250, geo).map((p) => p.kind)).toEqual(["duck"])
    expect(propsAt("drill", 100, geo)).toEqual([])
  })
  test("only the power cut blacks out; only the meteor flickers", () => {
    expect(blackoutAt("power", 300)).toBe(true)
    expect(blackoutAt("power", EVENTS.power.ticks - 1)).toBe(false)
    expect(blackoutAt("meteor", 300)).toBe(false)
    expect(flickerAt("meteor", 0)).toBeNull()
    expect(typeof flickerAt("meteor", 90)).toBe("boolean")
    expect(flickerAt("zoo", 90)).toBeNull()
  })
})

const view = (idle: string[] = []) => {
  const o = office(4)
  o.roster = o.roster.map((r) => (idle.includes(r.agent) ? { ...r, thinking: false, warm: false } : r))
  return viewOf(o, 1)
}
const run = (r: WideRoom, a: ReturnType<typeof view>, n: number) => { for (let i = 0; i < n; i++) r.step(a) }

describe("Sim.event", () => {
  test("each kind starts, runs its length, and leaves nothing on the stage", () => {
    for (const kind of EVENT_KINDS) seeded(3, () => {
      const r = new WideRoom(696), a = view(["w0", "w1"])
      run(r, a, 300)
      expect(r.event(kind)).toBe(true)
      expect(r.eventNow()?.kind).toBe(kind)
      run(r, a, EVENTS[kind].ticks + 5)
      expect(r.eventNow()).toBeNull()
      expect(r.props()).toEqual([])
      expect(r.blackout()).toBe(false)
    })
  })
  test("a second request while one runs is refused", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0"])
    run(r, a, 300)
    expect(r.event("duck")).toBe(true)
    run(r, a, 10)
    expect(r.event("meteor")).toBe(false)
    expect(r.eventNow()?.kind).toBe("duck")
  }))
  test("a keyless request draws a kind that is not the last", () => seeded(5, () => {
    const r = new WideRoom(696), a = view(["w0"])
    run(r, a, 300)
    r.event("duck"); run(r, a, EVENTS.duck.ticks + 1)
    expect(r.event()).toBe(true)
    expect(r.eventNow()!.kind).not.toBe("duck")
  }))
  test("onEvent fires at the start and at each beat", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0"]), seen: string[] = []
    r.onEvent = (kind, beat) => seen.push(`${kind}:${beat?.at ?? "start"}`)
    run(r, a, 300); r.event("duck"); run(r, a, 600)
    expect(seen).toEqual(["duck:start", "duck:200"])
  }))
  test("an event touches nothing the server owns", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0"]), before = structuredClone(a)
    run(r, a, 300); r.event("meteor"); run(r, a, 800)
    expect(a).toEqual(before)
  }))
  test("the rail room starts none", () => {
    const r = new RailRoom()
    expect(r.event("duck")).toBe(false)
    expect(r.eventNow()).toBeNull()
  })
})

describe("the cast", () => {
  test("a thinking seat never leaves its desk in any event", () => {
    for (const kind of EVENT_KINDS.filter((k) => k !== "drill")) seeded(9, () => {
      const r = new WideRoom(696), a = view(["w0", "w1"])
      run(r, a, 300)
      const pos = (n: string) => { const x = (r as any).actors.get(n); return `${x.x}:${x.y}` }
      const at = { w2: pos("w2"), hronir: pos("hronir") }
      r.event(kind)
      for (let i = 0; i < EVENTS[kind].ticks; i++) {
        r.step(a)
        expect(pos("w2")).toBe(at.w2)
        expect(pos("hronir")).toBe(at.hronir)
      }
    })
  })
  test("the same seed runs the same twice", () => {
    const trace = () => seeded(4, () => {
      const r = new WideRoom(696), a = view(["w0", "w1"]), out: string[] = []
      run(r, a, 300); r.event("meteor")
      for (let i = 0; i < 700; i++) { r.step(a); out.push(JSON.stringify([...(r as any).actors.values()].map((x: any) => [x.x, x.y]))) }
      return out
    })
    expect(trace()).toEqual(trace())
  })
})
