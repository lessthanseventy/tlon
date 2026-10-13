import { describe, expect, test } from "bun:test"
import { EVENT_KINDS, EVENTS, blackoutAt, flickerAt, pickEvent, propsAt, type Geo } from "../kit/events"
import { DRILL } from "../kit/sim"

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
