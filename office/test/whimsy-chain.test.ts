import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { CHAINS, EVENT_KINDS, EVENTS, propsAt, type Geo } from "../kit/events"
import { DEFAULT, resolve, setDial, setPreset, type State } from "../kit/whimsy"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

const geo: Geo = { doorX: 600, hallY: 190, ceilY: 12, leftX: 60, windowX: 200, cork: { x: 400, y: 40 } }

describe("chains and severity (pure)", () => {
  test("every chain target is an event, nothing chains to itself, and the chains end", () => {
    for (const k of EVENT_KINDS) {
      for (const n of CHAINS[k]) {
        expect(EVENT_KINDS).toContain(n)
        expect(n).not.toBe(k)
      }
      let at = k
      for (let i = 0; i < 10 && CHAINS[at].length; i++) at = CHAINS[at][0]!
      expect(CHAINS[at]).toEqual([])
    }
    expect(CHAINS.zoo).toContain("drill")
    expect(CHAINS.drill).toContain("power")
  })
  test("severity 1 is exactly today's props; 3 puts more on the stage", () => {
    for (const k of EVENT_KINDS) for (let t = 0; t < EVENTS[k].ticks; t += 25) {
      expect(propsAt(k, t, geo, 1)).toEqual(propsAt(k, t, geo))
    }
    for (const k of ["meteor", "zoo", "duck"] as const) {
      const n = (s: 1 | 3) => Math.max(...Array.from({ length: EVENTS[k].ticks / 10 }, (_, i) => propsAt(k, i * 10, geo, s).length))
      expect(n(3)).toBeGreaterThan(n(1))
    }
  })
})

const view = () => {
  const o = office(4)
  o.roster = o.roster.map((r) => (["w0", "w1"].includes(r.agent) ? { ...r, thinking: false, warm: false } : r))
  return viewOf(o, 1)
}
function run(state: State, n: number, seed = 11) {
  return seeded(seed, () => {
    const r = new WideRoom(696), a = view()
    ;(r as any).hour = () => 12
    r.setWhimsy(resolve(state))
    const log: { kind: string; since: number }[] = []
    r.onEvent = (kind) => {}
    let last = ""
    for (let i = 0; i < n; i++) {
      r.step(a)
      const e = r.eventNow()
      if (e && `${e.kind}@${e.since}` !== last) { last = `${e.kind}@${e.since}`; log.push({ kind: e.kind, since: e.since }) }
    }
    return { r, a, log }
  })
}

describe("rimworld chains", () => {
  test("an event can start the next the moment it ends; with chain off it never does", () => {
    const chained = (log: { kind: string; since: number }[]) =>
      log.some((e, i) => i > 0 && e.since === log[i - 1]!.since + EVENTS[log[i - 1]!.kind as keyof typeof EVENTS].ticks && (CHAINS as any)[log[i - 1]!.kind].includes(e.kind))
    const on = run(setPreset(DEFAULT, "rimworld"), 60_000).log
    expect(on.length).toBeGreaterThan(1)
    expect(chained(on)).toBe(true)
    const off = run(setDial(setPreset(DEFAULT, "rimworld"), "chain", false), 60_000).log
    expect(chained(off)).toBe(false)
  }, 60_000)
})

describe("sour moods", () => {
  // the idle pool is the only thing sourMood touches; pets and high-fives also make hearts, so compare traces, not absolutes
  const trace = (moods: boolean, sour: boolean) => seeded(3, () => {
    const r = new WideRoom(696), a = view()
    ;(r as any).hour = () => 12
    r.setWhimsy(resolve(setDial(DEFAULT, "moods", moods)))
    for (let i = 0; i < 200; i++) r.step(a)
    if (sour) for (const n of (r as any).actors.keys()) r.sourMood(n)
    const out: string[] = []
    for (let i = 0; i < 6000; i++) {
      r.step(a)
      for (const x of (r as any).actors.values()) out.push(x.emote ?? "")
    }
    return out
  })
  test("under moods a soured coworker idles on grumpy glyphs; with moods off sourMood is a no-op", () => {
    const warm = (t: string[]) => t.filter((e) => e === "♥" || e === "♪").length
    expect(warm(trace(true, true))).toBeLessThan(warm(trace(true, false)))
    expect(trace(false, true)).toEqual(trace(false, false))
  }, 30_000)
})
