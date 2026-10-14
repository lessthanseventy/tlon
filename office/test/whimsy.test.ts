import { describe, expect, test } from "bun:test"
import { DEFAULT, PRESET_IDS, resolve, setPreset, setDial, isCustom, parse, meanGap } from "../kit/whimsy"
import { EVENT_KINDS } from "../kit/events"

describe("whimsy presets", () => {
  test("default is casual, everything on, mode office", () => {
    expect(DEFAULT).toEqual({ mode: "office", preset: "casual", overrides: {} })
    expect(Object.values(resolve(DEFAULT).events).every(Boolean)).toBe(true)
  })
  test("business is silent: no banter, no events, no bell, pets asleep", () => {
    const d = resolve({ ...DEFAULT, preset: "business" })
    expect(d.banter).toBe(false)
    expect(d.frequency).toBe("never")
    expect(d.doorbell).toBe("off")
    expect(d.pets).toBe(false)
    expect(d.souls).toBe(false)
    expect(d.chain).toBe(false)
  })
  test("rimworld chains, escalates and sours moods", () => {
    const d = resolve({ ...DEFAULT, preset: "rimworld" })
    expect(d.chain).toBe(true)
    expect(d.severity).toBe(3)
    expect(d.moods).toBe(true)
  })
  test("a dial overridden under a preset holds, and shows as custom", () => {
    let s = setDial({ ...DEFAULT, preset: "rimworld" }, "banter", false)
    expect(resolve(s).banter).toBe(false)
    expect(resolve(s).chain).toBe(true)
    expect(isCustom(s)).toBe(true)
    s = setDial(s, "events", { ...resolve(s).events, duck: false })
    expect(resolve(s).events.duck).toBe(false)
    expect(resolve(s).events.zoo).toBe(true)
  })
  test("choosing a preset sets the dials: it clears every override", () => {
    const s = setPreset(setDial(DEFAULT, "banter", false), "party")
    expect(s.overrides).toEqual({})
    expect(isCustom(s)).toBe(false)
    expect(resolve(s).banter).toBe(true)
  })
  test("an override equal to the preset's value is dropped, so custom un-sticks", () => {
    expect(isCustom(setDial(DEFAULT, "banter", resolve(DEFAULT).banter))).toBe(false)
  })
  test("mean gaps are ordered never > rare > some > lots", () => {
    expect(meanGap("never")).toBe(Infinity)
    expect(meanGap("rare")).toBeGreaterThan(meanGap("some"))
    expect(meanGap("some")).toBeGreaterThan(meanGap("lots"))
  })
  test("parse: junk, a partial file and an unknown preset all fall back to defaults field by field", () => {
    expect(parse("not json")).toEqual(DEFAULT)
    expect(
      parse(JSON.stringify({ preset: "nope", mode: "sandbox", overrides: { severity: 9, banter: false } })),
    ).toEqual({ mode: "sandbox", preset: "casual", overrides: { banter: false } })
    expect(PRESET_IDS).toEqual(["business", "casual", "party", "rimworld"])
    expect(EVENT_KINDS.every((k) => k in resolve(DEFAULT).events)).toBe(true)
  })
})
