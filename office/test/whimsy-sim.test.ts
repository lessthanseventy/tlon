import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { EVENT_KINDS, pickEvent } from "../kit/events"
import { DEFAULT, PRESETS, resolve, setDial, setPreset, type State } from "../kit/whimsy"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

const view = () => {
  const o = office(4)
  o.roster = o.roster.map((r) => (["w0", "w1"].includes(r.agent) ? { ...r, thinking: false, warm: false } : r))
  return viewOf(o, 1)
}

/** a seeded 12:00 room under `state`, stepped `n` ticks; reports every event started and every ring */
function play(state: State, n: number, seed = 7) {
  return seeded(seed, () => {
    const r = new WideRoom(696), a = view()
    ;(r as any).hour = () => 12
    r.setWhimsy(resolve(state))
    const kinds: string[] = []
    let rings = 0
    r.onEvent = (k, beat) => { if (!beat) kinds.push(k) }
    const ring = r.ring.bind(r)
    r.ring = (k?: any) => { const ok = ring(k); if (ok) rings++; return ok }
    for (let i = 0; i < n; i++) r.step(a)
    return { r, a, kinds, rings }
  })
}

describe("the dials gate the room", () => {
  test("business plays no event and rings no bell", () => {
    const { kinds, rings, r } = play({ ...DEFAULT, preset: "business" }, 30_000)
    expect(kinds).toEqual([])
    expect(rings).toBe(0)
    expect(r.eventNow()).toBeNull()
  }, 40_000)
  test("a toggled-off event never plays, keyed or not", () => {
    const only = { ...PRESETS.casual.events, drill: false, zoo: false, meteor: false, power: false }
    const s = setDial(setDial(DEFAULT, "frequency", "lots"), "events", only)
    const { kinds, r } = play(s, 45_000)
    expect(kinds.length).toBeGreaterThan(0)
    expect(kinds.every((k) => k === "duck")).toBe(true)
    expect(r.event("zoo")).toBe(false)
    expect(r.eventNow()).toBeNull()
  }, 40_000)
  test("a dial overridden under rimworld holds: no bell, events still start", () => {
    const { kinds, rings } = play(setDial(setPreset(DEFAULT, "rimworld"), "doorbell", "off"), 45_000)
    expect(rings).toBe(0)
    expect(kinds.length).toBeGreaterThan(0)
  }, 40_000)
  test("pets off: the post carries itself, Nina sleeps through the doorbell", () => {
    const { r } = play(setDial(DEFAULT, "pets", false), 10)
    expect((r as any).catLetter("w2")).toBe(false)
    expect((r as any).cat.errand ?? null).toBeNull()
  })
  test("pets off: Nina is asleep and silent", () => seeded(5, () => {
    const { r } = play(setDial(DEFAULT, "pets", false), 6_000, 5)
    const a = view()
    const said = [(r as any).cat.said, (r as any).dog.said]
    for (let i = 0; i < 5_000; i++) {
      r.step(a)
      expect((r as any).cat.mode).toBe("sleep")
    }
    expect([(r as any).cat.said, (r as any).dog.said]).toEqual(said)
    expect((r as any).dog.mode).toBe("sleep")
  }))
  test("the keyed event key plays nothing at all when every event is switched off", () => {
    const { r, a } = play({ ...DEFAULT, preset: "business" }, 600)
    r.play("event")
    r.step(a)
    expect(r.eventNow()).toBeNull()
    const emotes = [...(r as any).actors.values()].filter((x: any) => x.emote === "!" && x.emoteUntil > (r as any).tick).length
    expect(emotes).toBe(0)
    expect((r as any).talk.size).toBe(0)
  })
  test("pickEvent draws from the enabled set only", () => {
    for (const roll of [0, 0.5, 0.99]) expect(pickEvent(roll, null, ["duck", "zoo"])).toMatch(/duck|zoo/)
    expect(pickEvent(0.5, "duck", ["duck"])).toBe("duck")
    expect(EVENT_KINDS.length).toBe(5)
  })
})
