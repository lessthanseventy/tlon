import { describe, expect, test } from "bun:test"
import { EVENT_KINDS, EVENTS, PLANE_CAUGHT, PLANE_COUNT, PLANE_GAP, blackoutAt, dimAt, flickerAt, pickEvent, planeCatch, propsAt, type Geo } from "../kit/events"
import { KEYS } from "../tui/keys"
import { viewOf } from "../kit/crew"
import { DRILL } from "../kit/sim"
import { RailRoom } from "../rooms/rail"
import { WideRoom } from "../rooms/wide"
import { SEAT_REACT, reactLine } from "../kit/seat-voices"
import { focus, measure, office, seeded } from "./golden"

const geo: Geo = { doorX: 600, hallY: 190, ceilY: 12, leftX: 60, windowX: 200, cork: { x: 400, y: 40 } }

describe("the events table", () => {
  test("nine kinds, each a bounded script whose beats fall inside it", () => {
    expect(EVENT_KINDS).toEqual(["drill", "zoo", "meteor", "power", "duck", "gary", "planes", "pizza", "nap"])
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
  test("the duck crosses the whole hall: from the door to its far end, not just the lounge's edge", () => {
    const xs = Array.from({ length: 261 }, (_, i) => propsAt("duck", 120 + i, geo)[0]!.x)
    expect(Math.min(...xs)).toBeLessThanOrEqual(12)
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
    run(r, a, 300)
    for (const k of EVENT_KINDS) { expect(r.event(k)).toBe(true); run(r, a, 1300); expect(a).toEqual(before) }
  }))
  test("the rail room starts none", () => {
    const r = new RailRoom()
    expect(r.event("duck")).toBe(false)
    expect(r.eventNow()).toBeNull()
  })
  test("eventsHere says whether this room can stage one, so a refusal can be explained", () => {
    expect(new RailRoom().eventsHere()).toBe(false)
    expect(new WideRoom(696).eventsHere()).toBe(true)
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
  test("each idle coworker reacts once per event, in their own line, staggered", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0", "w1"]), asked: string[] = [], said: Record<string, string[]> = {}
    r.reactLine = (who, kind) => { asked.push(who); return `${who} on ${kind}` }
    run(r, a, 300); r.event("duck")
    for (let i = 0; i < EVENTS.duck.ticks; i++) {
      r.step(a)
      for (const [n, t] of (r as any).talk as Map<string, { text: string | null }>)
        if (t.text?.endsWith(" on duck") && !(said[n] ??= []).includes(t.text)) said[n]!.push(t.text)
    }
    for (const n of ["w0", "w1"]) expect(said[n]).toEqual([`${n} on duck`])
    expect(asked.filter((n) => n === "w0").length).toBe(1)
  }))
  test("a seat that is thinking is never asked for a reaction", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0", "w1"]), asked = new Set<string>()
    r.reactLine = (who) => { asked.add(who); return "hm" }
    run(r, a, 300)
    for (const k of EVENT_KINDS.filter((k) => k !== "drill")) { r.event(k); run(r, a, EVENTS[k].ticks + 5) }
    expect(asked.has("w0")).toBe(true)
    expect(asked.has("w2")).toBe(false)
    expect(asked.has("hronir")).toBe(false)
  }))
  test("a zoo draws a line from more than one seat, each from the seat voices' own table", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0", "w1"]), given = new Map<string, string>(), heard = new Set<string>()
    r.reactLine = (who, kind) => { const l = reactLine(who, kind, []); given.set(who, l); return l }
    run(r, a, 300); r.event("zoo")
    for (let i = 0; i < EVENTS.zoo.ticks; i++) {
      r.step(a)
      for (const [n, t] of (r as any).talk as Map<string, { text: string | null }>) if (t.text && t.text === given.get(n)) heard.add(n)
    }
    expect(heard.size).toBeGreaterThan(1)
    for (const n of heard) if (SEAT_REACT[n]) expect(SEAT_REACT[n]!.zoo).toContain(given.get(n)!)
  }))
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

describe("the stage", () => {
  const frame = (r: any, a: ReturnType<typeof view>, props = true) => {
    const real = r.props
    if (!props) r.props = () => []
    try { return new Bun.CryptoHasher("sha1").update(r.render(a, focus, measure, new Date(2026, 9, 9, 15)).rgba).digest("hex") } finally { r.props = real }
  }
  test("the duck is drawn on the hall mid-scene and is not there after", () => seeded(2, () => {
    const r = new WideRoom(696), a = view(["w0"])
    run(r, a, 300)
    r.event("duck"); run(r, a, 200)
    expect(r.props().map((p) => p.kind)).toEqual(["duck"])
    expect(frame(r, a)).not.toBe(frame(r, a, false))
    run(r, a, 400)
    expect(r.props()).toEqual([])
    expect(frame(r, a)).toBe(frame(r, a, false))
  }))
})

describe("the meteor", () => {
  test("a streak, a crater that goes with it, idle coworkers at the window, one blames the deploy", () => seeded(6, () => {
    const r = new WideRoom(696) as any, a = view(["w0", "w1"]), said: string[] = []
    const say = r.say.bind(r)
    r.say = (w: string, t: string | null) => { said.push(`${w}:${t}`); say(w, t) }
    run(r, a, 300); r.event("meteor")
    run(r, a, 120)
    expect(r.props().map((p: any) => p.kind)).toContain("streak")
    run(r, a, 200)
    expect(r.props().map((p: any) => p.kind)).toContain("crater")
    expect(["w0", "w1"].some((n) => r.actors.get(n).spot.kind === "window")).toBe(true)
    expect(said.some((s) => s.endsWith("…was that the deploy?"))).toBe(true)
    run(r, a, 400)
    expect(r.props()).toEqual([])
  }))
  test("the puff and crater land where the streak ends: in the window pane, the street seen through it", () => {
    // the wide room has no street in view; the one outside is the view through the window
    expect(propsAt("meteor", 150, geo)).toEqual([{ kind: "puff", x: geo.windowX + 8, y: 35 }])
    expect(propsAt("meteor", 300, geo)).toEqual([{ kind: "crater", x: geo.windowX + 8, y: 35 }])
  })
  test("the flicker lights and unlights the lamps in turn", () => {
    const seen = new Set<boolean | null>()
    for (let t = 60; t < 140; t++) seen.add(flickerAt("meteor", t))
    expect(seen.has(true) && seen.has(false)).toBe(true)
  })
})

describe("the power cut", () => {
  test("dark for the middle, a candle by one idle coworker, applause when the lamps return", () => seeded(8, () => {
    const r = new WideRoom(696) as any, a = view(["w0", "w1"]), at = new Date(2026, 9, 9, 15)
    run(r, a, 300); r.event("power")
    run(r, a, 200)
    expect(r.blackout()).toBe(true)
    expect(r.props().some((p: any) => p.kind === "candle")).toBe(true)
    const lit = () => (r.render(a, focus, measure, at).rgba as Uint8Array).reduce((n, v) => n + v, 0)
    const dim = lit()
    run(r, a, EVENTS.power.ticks - 200 - 30)
    expect(r.blackout()).toBe(false)
    expect(lit()).toBeGreaterThan(dim)
    expect([...r.actors.values()].some((x: any) => x.emote === "♪")).toBe(true)
  }))
})

describe("zoo's open day", () => {
  test("a van, three animals, the note eaten and back, the sheriff gives chase, all gone at the end", () => seeded(10, () => {
    const o = JSON.parse(JSON.stringify(office(4)).replaceAll('"w3"', '"scharlach"')) as ReturnType<typeof office>
    o.roster = o.roster.map((x) => (["w0", "scharlach"].includes(x.agent) ? { ...x, thinking: false, warm: false } : x))
    const a = viewOf(o, 1), r = new WideRoom(696) as any, kinds = new Set<string>()
    let eaten = false
    run(r, a, 300); r.event("zoo")
    for (let i = 0; i < EVENTS.zoo.ticks - 1; i++) {
      r.step(a)
      for (const p of r.props()) {
        kinds.add(p.kind)
        if (p.kind === "van" && (i < 61 || i > 1100)) continue // sliding in or out
        expect(p.x).toBeGreaterThan(0)
        expect(p.x).toBeLessThan(696)
      }
      if (r.noteHidden()) eaten = true
    }
    for (const k of ["van", "monkey", "penguin", "goat", "net"]) expect(kinds.has(k)).toBe(true)
    expect(eaten).toBe(true)
    run(r, a, 5)
    expect(r.props()).toEqual([])
    expect(r.noteHidden()).toBe(false)
  }))
})

describe("the drill is one of the five", () => {
  test("Sim.event('drill') raises the alarm, with the sheriff calling it", () => seeded(12, () => {
    const o = JSON.parse(JSON.stringify(office(4)).replaceAll('"w3"', '"scharlach"')) as ReturnType<typeof office>
    o.roster = o.roster.map((x) => (["w0", "scharlach"].includes(x.agent) ? { ...x, thinking: false, warm: false } : x))
    const a = viewOf(o, 1), r = new WideRoom(696) as any, said: string[] = []
    const say = r.say.bind(r)
    r.say = (w: string, t: string | null) => { said.push(`${w}:${t}`); say(w, t) }
    run(r, a, 300)
    expect(r.event("drill")).toBe(true)
    expect(r.alarmed).toBe(true)
    expect(said).toContain("scharlach:Fire drill! Everyone out!")
    expect(r.event("duck")).toBe(false)
    run(r, a, DRILL + 5)
    expect(r.alarmed).toBe(false)
    expect(r.eventNow()).toBeNull()
  }))
})

describe("play says whether it played", () => {
  test("a drill refused over a running scene returns false; a drill on a calm room returns true", () => seeded(12, () => {
    const a = viewOf(office(4), 1), r = new WideRoom(696) as any
    run(r, a, 300)
    expect(r.event("zoo")).toBe(true)
    expect(r.play("drill")).toBe(false)
    expect(r.alarmed).toBe(false)
    const calm = new WideRoom(696) as any
    run(calm, a, 300)
    expect(calm.play("drill")).toBe(true)
    expect(calm.alarmed).toBe(true)
  }))
})

describe("planes, pizza and the power nap", () => {
  const kinds = (t: number, k: "planes" | "pizza", g: Geo = geo) => propsAt(k, t, g).map((p) => p.kind)
  test("the storm sends every sheet across the hall, and the third hangs where Argos waits, then goes", () => {
    const seen = new Set<number>()
    for (let t = 0; t < EVENTS.planes.ticks; t++) propsAt("planes", t, geo).forEach((p) => seen.add(p.y))
    expect(seen.size).toBeGreaterThan(PLANE_COUNT)
    const c = planeCatch(geo), at = 30 + PLANE_CAUGHT * PLANE_GAP + 120
    expect(propsAt("planes", at, geo).filter((p) => p.x === c.x && p.y === c.y)).toHaveLength(1)
    expect(propsAt("planes", at + 40, geo).filter((p) => p.x === c.x && p.y === c.y)).toHaveLength(0)
    expect(propsAt("planes", EVENTS.planes.ticks, geo)).toEqual([])
  })
  test("the pizza thins out box by box and leaves a handprint on the whiteboard", () => {
    const g: Geo = { ...geo, kitchen: { x: 640, y: 157 }, board: { x: 300, y: 30 } }
    expect(kinds(30, "pizza", g)).toEqual([])
    expect(kinds(100, "pizza", g).filter((k) => k === "pizzabox")).toHaveLength(3)
    expect(kinds(400, "pizza", g).filter((k) => k === "pizzabox")).toHaveLength(2)
    expect(kinds(500, "pizza", g).filter((k) => k === "pizzabox")).toHaveLength(1)
    expect(kinds(100, "pizza", g)).not.toContain("grease")
    expect(kinds(400, "pizza", g)).toContain("grease")
    expect(kinds(650, "pizza", g)).toEqual(["grease"])
    expect(propsAt("pizza", 100, g, 3)).toEqual(propsAt("pizza", 100, g, 1))
  })
  test("only the nap dims the floor", () => {
    expect(dimAt("nap", 300)).toBe(true)
    expect(dimAt("nap", 10)).toBe(false)
    expect(dimAt("nap", EVENTS.nap.ticks - 1)).toBe(false)
    expect(dimAt("power", 300)).toBe(false)
  })
  test("the party pulls the crew to the kitchen, and the nap dims the floor and settles zzz over them", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0", "w1"])
    run(r, a, 300)
    r.event("pizza")
    expect(r.pizzaOn()).toBe(true)
    run(r, a, EVENTS.pizza.ticks + 5)
    r.event("nap")
    run(r, a, 100)
    expect(r.dimmed()).toBe(true)
    expect(r.props().filter((p) => p.kind === "zzz").length).toBeGreaterThan(0)
    run(r, a, EVENTS.nap.ticks)
    expect(r.dimmed()).toBe(false)
  }))
  test("Argos goes under the hanging plane, and each new event has a card row", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0"])
    r.setClock(() => new Date(2026, 10, 9, 12))
    run(r, a, 300)
    expect(r.event("planes")).toBe(true)
    const g = (r as any).eventGeo() as Geo
    run(r, a, 400)
    expect(Math.abs((r as any).dog.x - planeCatch(g).x)).toBeLessThan(20)
    for (const id of ["play.planes", "play.pizza", "play.nap"]) expect(KEYS.some((b) => b.id === id)).toBe(true)
  }))
})

describe("the nap and the storm, placed", () => {
  test("the nap seats the idle on the couch, as many as it holds, with zzz over every idle head", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0", "w1", "w2", "w3"])
    r.setClock(() => new Date(2026, 10, 9, 12))
    run(r, a, 300)
    expect(r.event("nap")).toBe(true)
    run(r, a, 540)
    const couch = (r as any).plan.lounge.filter((s: any) => s.kind === "couch") as { x: number; y: number }[]
    const idle = (r as any).running.idle as string[]
    const on = idle.filter((n) => couch.some((s) => Math.abs((r as any).actors.get(n).x - s.x) < 4 && Math.abs((r as any).actors.get(n).y - s.y) < 4))
    expect(on).toHaveLength(Math.min(idle.length, couch.length))
    expect(r.props().filter((p) => p.kind === "zzz")).toHaveLength(idle.length)
  }))
  test("Argos is at the catch spot before the first sheet has crossed the hall", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0"])
    r.setClock(() => new Date(2026, 10, 9, 12))
    run(r, a, 300)
    r.event("planes")
    const g = (r as any).eventGeo() as Geo
    run(r, a, 250)
    expect(Math.abs((r as any).dog.x - planeCatch(g).x)).toBeLessThan(20)
  }))
})
