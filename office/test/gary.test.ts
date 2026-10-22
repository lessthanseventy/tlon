import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { EVENT_KINDS, EVENTS, GARY_ACT, garyLeads, garyRoll, propsAt, type Geo, type Prop } from "../kit/events"
import { newLedger, SHERIFF, tickSlap } from "../kit/scharlach"
import { DEFAULT, PRESETS, parse, resolve, setPreset } from "../kit/whimsy"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

const geo: Geo = { doorX: 600, hallY: 190, ceilY: 12, leftX: 60, windowX: 200, cork: { x: 400, y: 40 } }
const kinds = (ps: Prop[]) => ps.map((p) => p.kind)
const END = EVENTS.gary.ticks

describe("Gary's roll and script (pure)", () => {
  test("the roll is a third each: a sandwich, a sock, or the SLAP", () => {
    expect([0, 0.2, 0.33].map(garyRoll)).toEqual(["sandwich", "sandwich", "sandwich"])
    expect([0.34, 0.5, 0.66].map(garyRoll)).toEqual(["sock", "sock", "sock"])
    expect([0.67, 0.9, 0.999].map(garyRoll)).toEqual(["slap", "slap", "slap"])
  })
  test("he is one more event, bounded like the rest", () => {
    expect(EVENT_KINDS).toContain("gary")
    expect(END).toBeGreaterThanOrEqual(500)
    expect(END).toBeLessThanOrEqual(1200)
    expect(GARY_ACT).toBeLessThan(END)
  })
  test("the dumpster sits just outside the door, from the first tick to the last", () => {
    for (const t of [0, 100, GARY_ACT, END - 1]) {
      const d = propsAt("gary", t, geo).find((p) => p.kind === "dumpster")!
      expect(d.y).toBe(geo.hallY)
      expect(d.x).toBeGreaterThan(geo.doorX - 60)
      expect(d.x).toBeLessThan(geo.doorX)
    }
    expect(propsAt("gary", END, geo)).toEqual([])
  })
  test("a peek is the lid and the eyes only: no Gary, no outcome", () => {
    for (let t = 0; t < END; t += 20) expect(kinds(propsAt("gary", t, geo, 1, { peek: true }))).toEqual(["dumpster"])
  })
  test("a visit: shut, then out with the fish bone and the mutter, then the outcome, then back in", () => {
    expect(kinds(propsAt("gary", 10, geo))).toEqual(["dumpster"])
    const growl = kinds(propsAt("gary", GARY_ACT - 20, geo))
    expect(growl).toEqual(expect.arrayContaining(["dumpster", "gary", "bone", "mutter"]))
    expect(propsAt("gary", GARY_ACT - 20, geo).find((p) => p.kind === "mutter")!.text).toBe("I WILL END YOU, and then I will eat your yogurt")
    expect(kinds(propsAt("gary", END - 5, geo, 1, { outcome: "slap" }))).not.toContain("gary")
  })
  test("each outcome shows: the sandwich in his hand, the sock left behind, the SLAP! and his cackle", () => {
    const at = GARY_ACT + 20
    expect(kinds(propsAt("gary", at, geo, 1, { outcome: "sandwich" }))).toContain("sandwich")
    expect(kinds(propsAt("gary", at, geo, 1, { outcome: "sock" }))).toContain("sock")
    expect(kinds(propsAt("gary", END - 5, geo, 1, { outcome: "sock" }))).toContain("sock")
    const slap = propsAt("gary", at, geo, 1, { outcome: "slap" })
    expect(slap.find((p) => p.kind === "shout")!.text).toBe("SLAP!")
    expect(kinds(propsAt("gary", at + 80, geo, 1, { outcome: "slap" }))).toContain("cackle")
    expect(kinds(propsAt("gary", at, geo, 1, { outcome: "sandwich" }))).not.toContain("shout")
  })
  test("a bigger event is not more Garys", () => {
    for (let t = 0; t < END; t += 25) expect(propsAt("gary", t, geo, 3)).toEqual(propsAt("gary", t, geo, 1))
  })
  test("in the zoo's parade he walks ahead of the penguin; in nothing else", () => {
    const pen = (t: number) => propsAt("zoo", t, geo).find((p) => p.kind === "penguin")
    for (const t of [100, 300, 700]) {
      const g = garyLeads("zoo", t, geo)
      expect(kinds(g)).toEqual(["gary"])
      expect(Math.abs(g[0]!.x - pen(t)!.x)).toBeGreaterThanOrEqual(10)
    }
    expect(garyLeads("zoo", 20, geo)).toEqual([])
    expect(garyLeads("duck", 300, geo)).toEqual([])
  })
})

describe("the wackiness dial", () => {
  test("never in business; a peek in casual; a visit in party; at the zoo's head in rimworld", () => {
    expect(PRESETS.business.events.gary).toBe(false)
    expect(PRESETS.casual).toMatchObject({ gary: "peek" })
    expect(PRESETS.casual.events.gary).toBe(true)
    expect(PRESETS.party).toMatchObject({ gary: "visit" })
    expect(PRESETS.party.events.gary).toBe(true)
    expect(PRESETS.rimworld).toMatchObject({ gary: "lead" })
    expect(PRESETS.rimworld.events.gary).toBe(true)
  })
  test("an override is read back, and junk falls to the preset's", () => {
    expect(resolve(parse(JSON.stringify({ preset: "casual", overrides: { gary: "visit" } }))).gary).toBe("visit")
    expect(resolve(parse(JSON.stringify({ preset: "party", overrides: { gary: "nope" } }))).gary).toBe("visit")
  })
})

describe("Scharlach's ledger", () => {
  test("a SLAP is one demerit against himself", () => {
    const l = tickSlap(tickSlap(newLedger()))
    expect(l.demerits.get(SHERIFF)).toBe(2)
  })
})

const view = (idle: string[] = ["w0", "w1"]) => {
  const o = office(4)
  o.roster = o.roster.map((r) => (idle.includes(r.agent) ? { ...r, thinking: false, warm: false } : r))
  return viewOf(o, 1)
}
const run = (r: WideRoom, a: ReturnType<typeof view>, n: number) => { for (let i = 0; i < n; i++) r.step(a) }
const withRoll = <T>(roll: number, f: () => T): T => { const real = Math.random; Math.random = () => roll; try { return f() } finally { Math.random = real } }
const room = (preset: "business" | "casual" | "party" | "rimworld") => {
  const r = new WideRoom(696), a = view()
  ;(r as any).hour = () => 12
  r.setWhimsy(resolve(setPreset(DEFAULT, preset)))
  run(r, a, 300)
  return { r, a }
}
const kindsNow = (r: WideRoom) => r.props().map((p) => p.kind)

describe("Gary in the room", () => {
  test("business keeps him out, even when asked", () => seeded(3, () => {
    const { r } = room("business")
    expect(r.event("gary")).toBe(false)
  }))
  test("casual: only the lid and the eyes, and nobody is hurt", () => seeded(3, () => {
    const { r, a } = room("casual")
    let slapped = 0
    r.onSlap = () => slapped++
    expect(withRoll(0.9, () => r.event("gary"))).toBe(true)
    const seen = new Set<string>()
    for (let i = 0; i < END; i++) { r.step(a); for (const k of kindsNow(r)) seen.add(k) }
    expect([...seen]).toEqual(["dumpster"])
    expect(slapped).toBe(0)
    expect(r.eventNow()).toBeNull()
  }))
  test("party, rolled low: he steals a sandwich and nobody is slapped", () => seeded(3, () => {
    const { r, a } = room("party")
    let slapped = 0
    r.onSlap = () => slapped++
    expect(withRoll(0.1, () => r.event("gary"))).toBe(true)
    const seen = new Set<string>()
    for (let i = 0; i < END; i++) { r.step(a); for (const k of kindsNow(r)) seen.add(k) }
    expect(seen.has("sandwich")).toBe(true)
    expect(seen.has("shout")).toBe(false)
    expect(slapped).toBe(0)
  }))
  test("party, rolled middling: he leaves one sock", () => seeded(3, () => {
    const { r, a } = room("party")
    expect(withRoll(0.5, () => r.event("gary"))).toBe(true)
    const seen = new Set<string>()
    for (let i = 0; i < END; i++) { r.step(a); for (const k of kindsNow(r)) seen.add(k) }
    expect(seen.has("sock")).toBe(true)
    expect(seen.has("shout")).toBe(false)
  }))
  test("party, rolled high: the nearest coworker is SLAPped, spins with stars, and the ledger hears of it", () => seeded(3, () => {
    const { r, a } = room("party")
    const slapped: string[] = []
    r.onSlap = (who) => slapped.push(who)
    expect(withRoll(0.9, () => r.event("gary"))).toBe(true)
    const g = (r as any).eventGeo() as Geo, d = propsAt("gary", 0, g).find((p) => p.kind === "dumpster")!
    const actors = (r as any).actors as Map<string, { x: number; y: number; face: string; emote: string | null; leaving: boolean }>
    const dist = ([, x]: [string, { x: number; y: number }]) => Math.hypot(x.x - d.x, x.y - d.y)
    let near = ""
    const faces = new Set<string>(), seen = new Set<string>()
    for (let i = 0; i < END; i++) {
      r.step(a)
      for (const k of kindsNow(r)) seen.add(k)
      // the SLAP lands during the step after this one, on the positions this step left
      if (i === GARY_ACT - 2) near = [...actors].filter(([, x]) => !x.leaving).sort((p, q) => dist(p) - dist(q) || (p[0] < q[0] ? -1 : 1))[0]![0]
      if (slapped[0] && i < GARY_ACT + 60) faces.add(actors.get(slapped[0])!.face)
    }
    expect(slapped).toEqual([near])
    expect(faces.size).toBeGreaterThanOrEqual(3)
    for (const k of ["shout", "stars", "cackle"]) expect(seen.has(k)).toBe(true)
  }))
  test("the same seed rolls the same visit twice", () => {
    const trace = () => seeded(7, () => {
      const { r, a } = room("party"), out: string[] = []
      r.onSlap = (w) => out.push(`slap ${w}`)
      r.event("gary")
      for (let i = 0; i < END; i++) { r.step(a); out.push(kindsNow(r).join()) }
      return out
    })
    expect(trace()).toEqual(trace())
  })
  test("rimworld: Gary heads the zoo's parade; casual's zoo has no Gary", () => seeded(3, () => {
    for (const [preset, led] of [["rimworld", true], ["casual", false]] as const) {
      const { r, a } = room(preset)
      expect(r.event("zoo")).toBe(true)
      let gary = false
      for (let i = 0; i < EVENTS.zoo.ticks; i++) { r.step(a); if (kindsNow(r).includes("gary")) gary = true }
      expect(gary).toBe(led)
    }
  }))
})
